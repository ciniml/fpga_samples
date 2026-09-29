#!/usr/bin/env python3
"""Hardware check of the reverse Manchester control channel (through
util/serial_bridge). Sequence:
  1. '?'            -> descriptor [VER][WIDTH][TS_BITS][ADDR_BITS]
  2. capture + dump -> baseline records (counter bits toggling)
  3. IGNORE_MASK = 0x00ff (mask the 8-bit counter) -> records only from bit 8 (S2) / none
  4. ENABLE=0 -> no records; ENABLE=1 -> records again
  5. RESET -> timestamps restart near zero
Every step prints what it saw; a failing step says so.
"""
import argparse, os, time
import trace_transport as tt
T = None   # transport (serial_bridge / serial / USB), see trace_transport.py

def api(url, body, to=8000):
    return T.xfer(body, to)
def flush(url):
    T.flush()

def crc8(a, d):
    c = 0
    for b in (a, d):
        c ^= b
        for _ in range(8): c = ((c << 1) ^ 0x07) & 0xff if c & 0x80 else (c << 1) & 0xff
    return c
def ctrl_frames(addr, data):
    out = []
    for i, d in enumerate(data):
        a = (addr + i) & 0xff; out += [0xA5, a, d, crc8(a, d)]
    return out

def main():
    ap = argparse.ArgumentParser()
    tt.add_args(ap)
    ap.add_argument("--addr-bits", type=int, default=14)
    ap.add_argument("--tick-ns", type=float, default=37.037, help="trace sample clock period (Nano9K demo: 27MHz)")
    ap.add_argument("--wait-s2", type=float, default=0.0, help="seconds to wait for an S2 press after arming (0 = skip)")
    ap.add_argument("--pulse", action="store_true", help="Nano9K built with CTRL_PULSE=1: test the 'P' reset burst only")
    ap.add_argument("--selftest", action="store_true", help="25K alone, USB-C cable pmod0 -> pmod2: check the receiver with its own stream")
    ap.add_argument("--map", help="signal map file (maps/*.map) to check against the TX descriptor hash")
    ap.add_argument("--fetch-map", action="store_true", help="request the signal-map text from the TX (CTRL.MAP_REQ) and read it with 'N'")
    a = ap.parse_args()
    global T; T = tt.from_args(a)
    url = a.url
    entries = 1 << a.addr_bits
    ok_all = True
    t_start = time.time()
    def check(name, cond, detail=""):
        nonlocal ok_all
        print(f"[{time.time()-t_start:5.1f}s] " + ("ok:   " if cond else "FAIL: ") + name + (f"  ({detail})" if detail else ""), flush=True)
        ok_all &= bool(cond)

    def link_diag():
        flush(url)
        d = api(url, {"write": [0x4C], "read": 14, "timeout_ms": 2000})["data"]           # 'L'
        if len(d) != 14: return None
        u16 = lambda i: d[i] | (d[i+1] << 8)
        return {"status": d[0], "ver": d[1], "commas": u16(2), "records": u16(4), "errors": u16(6),
                "ovf": u16(8), "desc": u16(10), "data": u16(12)}
    # 1. link diagnostics: is the receiver locked and are records arriving?
    link_diag(); time.sleep(0.2); lg = link_diag()
    if lg is None:
        check("'L' link diagnostics", False, "no reply: is the 25K programmed / the bridge on the right port?"); return
    st = lg["status"]
    bits = [n for i, n in enumerate(["lock", "align", "desc", "commas", "ip_reset"]) if st & (1 << i)] + (["CLOCK_DEAD"] if st & 0x80 else [])
    check("'L' link: lock+align+commas", (st & 0x0b) == 0x0b and not (st & 0x80),
          f"status 0x{st:02x} [{' '.join(bits)}] in 0.2s: commas {lg['commas']} records {lg['records']} errors {lg['errors']} ovf {lg['ovf']} desc {lg['desc']}")
    if (st & 0x0b) != 0x0b:
        print("      no lock/commas: check the cable (TX lane -> RX lane), the TX board's PLL/bitstream, and the link rate variant"); return
    check("'L' link: no decode errors", lg["errors"] == 0)
    flush(url)
    r = api(url, {"write": [0x3F], "read": 8, "timeout_ms": 2000})
    d = r["data"]
    h = (d[4] | (d[5] << 8) | (d[6] << 16) | (d[7] << 24)) if len(d) == 8 else None
    check("'?' descriptor", len(d) == 8 and d[0] in (1, 2), f"VER={d[0] if d else None} WIDTH={d[1] if len(d)>1 else None} TS_BITS={d[2] if len(d)>2 else None} ADDR_BITS={d[3] if len(d)>3 else None} HASH={('0x%08x' % h) if h is not None else None}")
    if len(d) < 8 or d[0] not in (1, 2):
        print("descriptor not seen: trace link (Nano9K -> 25K) not up?"); return
    if a.map:
        import importlib.util
        spec = importlib.util.spec_from_file_location("tracemap", os.path.join(os.path.dirname(__file__), "tracemap.py"))
        tm = importlib.util.module_from_spec(spec); spec.loader.exec_module(tm)
        sigs, mw = tm.parse(open(a.map).read()); mh = tm.crc32(sigs)
        check(f"signal map {a.map} matches the TX build", d[0] >= 2 and mh == h and mw == d[1], f"map WIDTH={mw} HASH=0x{mh:08x} vs TX WIDTH={d[1]} HASH={('0x%08x' % h) if h is not None else None}")
    width, ts_bits, addr_bits = d[1], d[2], d[3]
    db, tb = width // 8, ts_bits // 8
    entries = 1 << addr_bits

    def capture(timeout_s=8.0):
        flush(url)
        api(url, {"write": [0x53], "read": 0})                       # 'S'
        r = api(url, {"write": [], "read": 1, "timeout_ms": int(timeout_s * 1000)})
        if r["timeout"] or r["data"] != [0x4B]:
            flush(url); api(url, {"write": [0x5A], "read": 1, "timeout_ms": 2000})   # 'Z' abort -> 'Z'
            return None
        raw = []
        api(url, {"write": [0x44], "read": 0})                       # 'D'
        while len(raw) < entries * 2:
            r = api(url, {"write": [], "read": min(4096, entries * 2 - len(raw)), "timeout_ms": 20000})
            raw += r["data"]
            if r["timeout"]: break
        return parse(raw)

    def parse(raw):
        recs, i, n = [], 0, len(raw) // 2
        rl = tb + db
        while i < n:
            k, b = raw[2*i] & 1, raw[2*i+1]
            if k and b == 0xFC and i + tb < n:          # K28.7 tick [ts]: skip (no data)
                i += 1 + tb
            elif k and b == 0x3C and i + rl < n and not any(raw[2*(i+j)] & 1 for j in range(1, rl + 1)):
                body = [raw[2*(i+j)+1] for j in range(1, rl + 1)]
                ts = int.from_bytes(bytes(body[:tb]), "little"); data = int.from_bytes(bytes(body[tb:]), "little")
                recs.append((ts, data)); i += 1 + rl
            else:
                i += 1
        return recs

    def send_ctrl(frames):
        api(url, {"write": [0x58, len(frames)] + frames, "read": 0})   # 'X'
        time.sleep(0.05)

    if a.fetch_map:
        flush(url); n0 = api(url, {"write": [0x4E], "read": 1, "timeout_ms": 2000})["data"]
        send_ctrl(ctrl_frames(0x00, [0x12]))                              # ENABLE | MAP_REQ
        time.sleep(0.1); flush(url)
        n = api(url, {"write": [0x4E], "read": 1, "timeout_ms": 2000})["data"]
        txt = bytes(api(url, {"write": [], "read": n[0], "timeout_ms": 2000})["data"]).decode() if n and n[0] else ""
        exp = None
        if a.map:
            import importlib.util
            spec = importlib.util.spec_from_file_location("tracemap", os.path.join(os.path.dirname(__file__), "tracemap.py"))
            tm = importlib.util.module_from_spec(spec); spec.loader.exec_module(tm)
            exp = tm.display(tm.parse(open(a.map).read())[0])
        check("'N' signal-map text from TX", bool(txt) and (exp is None or txt == exp), f"before request LEN={n0[0] if n0 else None}; got {len(txt)} bytes: {txt!r}" + (f" expected {exp!r}" if exp is not None and txt != exp else ""))

    if a.selftest:
        # the 25K's own 16-bit counter stream (steps every 5.12us): consecutive records differ by exactly 1
        check("self-test descriptor WIDTH=16", width == 16)
        recs = capture()
        check("self-test capture", recs is not None and len(recs) > 100, f"{len(recs) if recs else 0} records")
        if recs:
            bad = sum(1 for i in range(1, len(recs)) if ((recs[i][1] - recs[i-1][1]) & 0xffff) != 1)
            gaps = [(recs[i][0] - recs[i-1][0]) & 0xffffff for i in range(1, len(recs))]
            med = sorted(gaps)[len(gaps)//2]
            check("self-test counter increments by 1", bad == 0, f"{bad} irregular steps out of {len(recs)-1}")
            check("self-test interval 256 sample clocks", med == 256, f"median gap {med}")
        lg = link_diag(); check("self-test no decode errors", lg is not None and lg["errors"] == 0, f"{lg}")
        print("ALL OK" if ok_all else "SOME CHECKS FAILED")
        return
    if a.pulse:
        # reset-only reverse channel: 'P' -> 80us burst -> Nano9K soft reset -> timestamps restart
        recs = capture()
        check("baseline capture", recs is not None and len(recs) > 0, f"{len(recs) if recs else 0} records")
        for n in range(3):
            # 'S' then 'P' in one write: the capture window (~7ms at the demo rate) starts ~90us
            # before the burst, so the timestamp discontinuity of the reset must be inside it
            flush(url)
            r = api(url, {"write": [0x53, 0x50], "read": 2, "timeout_ms": 8000})      # 'S' 'P' -> 'P' 'K'
            check(f"'P' acknowledged #{n+1}", r["data"] == [0x50, 0x4B], f"reply {r['data']}")
            recs = None
            if r["data"] == [0x50, 0x4B]:
                raw = []
                api(url, {"write": [0x44], "read": 0})                                # 'D'
                while len(raw) < entries * 2:
                    rr = api(url, {"write": [], "read": min(4096, entries * 2 - len(raw)), "timeout_ms": 20000})
                    raw += rr["data"]
                    if rr["timeout"]: break
                recs = parse(raw)
            # a reset: ts falls to ~0 from a value that is not near the 24-bit wrap (natural wrap: 16777xxx -> 0)
            drops = [i for i in range(1, len(recs or [])) if recs[i][0] < recs[i-1][0] and recs[i][0] < 100000 and recs[i-1][0] < 16000000]
            check(f"timestamp restarts inside the window #{n+1}", len(drops) == 1,
                  f"{len(recs) if recs else 0} records, drops at {drops[:3]}" +
                  (f": ts {recs[drops[0]-1][0]} -> {recs[drops[0]][0]} ({recs[drops[0]-1][0]*a.tick_ns/1e3:.0f}us after arm)" if len(drops) == 1 else ""))
        print("ALL OK" if ok_all else "SOME CHECKS FAILED")
        return

    # 2. baseline (soft reset first: a previous run may have left the TX armed / done)
    send_ctrl(ctrl_frames(0x00, [0x03]))        # RESET | ENABLE
    time.sleep(0.01)
    send_ctrl(ctrl_frames(0x04, [0x00] * db))   # mask off
    send_ctrl(ctrl_frames(0x00, [0x02]))        # enable
    recs = capture()
    check("baseline capture", recs is not None and len(recs) > 0, f"{len(recs) if recs else 0} records")
    if recs:
        ch = sum(1 for i in range(1, len(recs)) if (recs[i][1] ^ recs[i-1][1]) & 0xff)
        print(f"      low-byte (counter) changes between records: {ch}/{len(recs)-1}")

    # 3. ignore the counter byte -> the buffer should not fill (capture times out)
    send_ctrl(ctrl_frames(0x04, [0xff] + [0x00] * (db - 1)))
    t0 = time.time(); recs = capture(timeout_s=3.0); dt = time.time() - t0
    check("IGNORE_MASK 0x00ff suppresses counter records", recs is None, f"capture {'timed out' if recs is None else 'completed with %d records' % len(recs)} after {dt:.1f}s")
    send_ctrl(ctrl_frames(0x04, [0x00] * db))
    recs = capture()
    check("mask cleared -> records again", recs is not None and len(recs) > 0)

    # 4. enable off / on
    send_ctrl(ctrl_frames(0x00, [0x00]))
    recs = capture(timeout_s=3.0)
    check("ENABLE=0 -> no records", recs is None)
    send_ctrl(ctrl_frames(0x00, [0x02]))
    recs = capture()
    check("ENABLE=1 -> records", recs is not None and len(recs) > 0)

    # 5. reset -> timestamps restart
    send_ctrl(ctrl_frames(0x00, [0x03]))
    time.sleep(0.01)
    recs = capture()
    if recs:
        first_ts = recs[0][0]
        check("RESET restarts timestamp", first_ts * a.tick_ns < 200e6, f"first record ts = {first_ts * a.tick_ns / 1e6:.1f} ms after reset (buffer fill takes ~{entries/6*256*a.tick_ns/1e6:.0f} ms at the demo rate)")
    else:
        check("RESET restarts timestamp", False, "no capture")
    # 6. flags + periodic sampling: change detection off, period 1e5 clocks (1ms) -> ~1000 rec/s
    def flags():
        flush(url); return api(url, {"write": [0x46], "read": 1, "timeout_ms": 2000})["data"][0]
    per = round(1e6 / a.tick_ns)                                                    # 1ms in sample clocks
    send_ctrl(ctrl_frames(0x08, [0x03]) + ctrl_frames(0x09, list(per.to_bytes(3, 'little'))))   # MODE, PERIOD
    time.sleep(0.05)
    f = flags(); check("flags: periodic set", f & 0x10, f"flags=0x{f:02x}")
    t0 = time.time(); recs = capture(timeout_s=8.0); dt = time.time() - t0
    check("periodic capture (buffer fill ~2.7s at 1 rec/ms)", recs is not None and len(recs) > 2000, f"{len(recs) if recs else 0} records in {dt:.1f}s")
    if recs:
        gaps = [(recs[i][0] - recs[i-1][0]) & 0xffffff for i in range(1, min(len(recs), 200))]
        med = sorted(gaps)[len(gaps)//2]
        check(f"periodic interval ~{per} sample clocks", abs(med - per) <= per // 100, f"median gap {med} clocks")
    send_ctrl(ctrl_frames(0x08, [0x00]))
    # 7. TX trigger on S2 (bit 8 == 1) with POST=100: armed -> no records until S2 is pressed
    m = [0x00, 0x01] + [0x00] * (db - 2)                                             # bit 8 (S2), width-relative offsets
    send_ctrl(ctrl_frames(0x0c, m) + ctrl_frames(0x0c + db, m) + ctrl_frames(0x0c + 2 * db, [100, 0]))
    send_ctrl(ctrl_frames(0x00, [0x0a]))      # ARM | ENABLE
    time.sleep(0.05)
    f = flags(); check("flags: armed", f & 0x02, f"flags=0x{f:02x}")
    recs = capture(timeout_s=3.0)
    check("armed TX sends nothing (capture times out)", recs is None)
    if a.wait_s2 > 0:
        print(f"      >>> Nano9K の S2 を押してください ({a.wait_s2:.0f} 秒待ちます) ... ", flush=True)
        t_end = time.time() + a.wait_s2; fired = False
        while time.time() < t_end:
            f = flags()
            if f & 0x0c: fired = True; break
            time.sleep(0.2)
        check("S2 press triggers (flags triggered/done)", fired, f"flags=0x{f:02x}")
        send_ctrl(ctrl_frames(0x0c + 2 * db, [0, 0]) + ctrl_frames(0x00, [0x02]))   # POST=0, enable (free running: not armed)
    else:
        print("      (TX left ARMED on S2 with POST=100: press S2, then read flags with 'F' / capture)")
    print("ALL OK" if ok_all else "SOME CHECKS FAILED")

if __name__ == "__main__":
    main()
