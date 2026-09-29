#!/usr/bin/env python3
"""Eye scan of the HS receiver: freeze the CDR at a sample class ('F') and
sweep the differential receiver's IODELAY ('d', 1 UI = 144 taps) while counting
packets / bad packets ('m': 17.5 ms window, the hub's IN-token polling is the
bit-error reference). Prints bad-packet ratio per point and the eye width.

  usb_eye.py --classes [--windows 2]     # coarse: the 8 CDR sample classes (260 ps apart)
  usb_eye.py --dps 20 [--class 4]        # fine: step the oversampling PLL phase ('Z', 130 ps) 20 times
                                         # forward with the CDR frozen at --class, then step back
The IODELAY sweep ('d') only applies to designs with DYN_DLY=1 (not the OSIDES32 path).
"""
import argparse, serial, time

HIST = [0] * 8
TXFIFO = [0, 0]   # cumulative {underrun, overrun} counts of the HS transmit FIFO (from the last frame)
def meas(s, windows):
    tot = bad = err = 0
    for k in range(8): HIST[k] = 0
    for _ in range(windows):
        while s.read(4096): pass
        s.write(b"m")
        buf = b""; t0 = time.time()
        while len(buf) < 41 and time.time() - t0 < 1.0:
            buf += s.read(41 - len(buf))
        i = buf.find(b"M")
        if i < 0 or len(buf) < i + 41: continue
        f = buf[i:i+41]
        tot += int.from_bytes(f[1:5], "little"); bad += int.from_bytes(f[5:9], "little"); err += int.from_bytes(f[9:13], "little")
        for k in range(8): HIST[k] += int.from_bytes(f[13+3*k:16+3*k], "little")
        TXFIFO[0] = int.from_bytes(f[37:39], "little"); TXFIFO[1] = int.from_bytes(f[39:41], "little")
    return tot, bad, err

def hist_str():
    n = max(sum(HIST), 1)
    return " ".join(f"{h/n*100:5.1f}%" for h in HIST)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1"); ap.add_argument("--class", dest="cls", type=int, default=4)
    ap.add_argument("--taps", default="0:160:4"); ap.add_argument("--windows", type=int, default=2)
    ap.add_argument("--classes", action="store_true"); ap.add_argument("--dwell", type=float, default=0.05)
    ap.add_argument("--csv", default=None); ap.add_argument("--tap-ps", type=float, default=14.5)
    ap.add_argument("--dps", type=int, default=0, help="PLL phase steps to scan (130 ps each, 16 per bit)")
    ap.add_argument("--ofs", action="store_true", help="scan the sample class as an offset from each packet's own SYNC phase (-4..+3, 260 ps)")
    ap.add_argument("--hist", action="store_true", help="only print the transition histogram (edge jitter per 1/8 UI class) while tracking")
    a = ap.parse_args()
    rows = []
    with serial.Serial(a.port, 115200, timeout=0.05) as s:
        while s.read(4096): pass
        if a.hist:
            tot, bad, err = meas(s, a.windows)
            print(f"tracking: packets {tot} bad {bad} rxerr {err}\nedge histogram per class 0..7 (1/8 UI = 260 ps bins): {hist_str()}")
            print(f"HS transmit FIFO: underruns {TXFIFO[0]}, overruns {TXFIFO[1]} (cumulative)")
        elif a.ofs:
            for o in (-4, -3, -2, -1, 0, 1, 2, 3):
                s.write(b"F" + bytes([0x40 | (o & 7)])); time.sleep(a.dwell)
                tot, bad, err = meas(s, a.windows)
                rows.append((o, tot, bad, err)); print(f"offset {o:+d} ({o*260:+5d} ps from the SYNC-derived centre): packets {tot:7d} bad {bad:6d} ({bad/max(tot,1):.2e}) rxerr {err}  hist {hist_str()}")
        elif a.dps:
            s.write(b"F" + bytes([0x80 | (a.cls & 7)])); time.sleep(a.dwell)
            for k in range(a.dps + 1):
                tot, bad, err = meas(s, a.windows)
                rows.append((k, tot, bad, err)); print(f"step {k:3d} ({k*130:5d} ps): packets {tot:7d} bad {bad:6d} ({bad/max(tot,1):.2e}) rxerr {err}")
                if k < a.dps: s.write(b"Z" + bytes([0x80])); time.sleep(a.dwell)
            for k in range(a.dps): s.write(b"Z" + bytes([0x00])); time.sleep(a.dwell)   # back to the start
            good = [r[0] for r in rows if r[1] > 0 and r[2] == 0]
            if good:
                runs = []; cur = [good[0]]
                for t in good[1:]:
                    if t - cur[-1] == 1: cur.append(t)
                    else: runs.append(cur); cur = [t]
                runs.append(cur); best = max(runs, key=len)
                print(f"eye: error-free run {best[0]}..{best[-1]} = {len(best)*130} ps of the 2083 ps bit")
        elif a.classes:
            for c in range(8):
                s.write(b"F" + bytes([0x80 | c])); time.sleep(a.dwell)
                tot, bad, err = meas(s, a.windows)
                rows.append((c, tot, bad, err)); print(f"class {c}: packets {tot:7d} bad {bad:6d} ({bad/max(tot,1):.2e}) rxerr {err}")
        else:
            lo, hi, st = (int(x) for x in a.taps.split(":"))
            s.write(b"F" + bytes([0x80 | (a.cls & 7)])); time.sleep(a.dwell)
            for t in range(lo, hi, st):
                s.write(b"d" + bytes([t])); time.sleep(a.dwell)
                tot, bad, err = meas(s, a.windows)
                rows.append((t, tot, bad, err)); print(f"tap {t:3d} ({t*a.tap_ps:6.0f} ps): packets {tot:7d} bad {bad:6d} ({bad/max(tot,1):.2e}) rxerr {err}")
            good = [r[0] for r in rows if r[1] > 0 and r[2] == 0]
            if good:
                runs = []; cur = [good[0]]
                for t in good[1:]:
                    if t - cur[-1] == st: cur.append(t)
                    else: runs.append(cur); cur = [t]
                runs.append(cur); best = max(runs, key=len)
                print(f"eye: error-free from tap {best[0]} to {best[-1]} = {(best[-1]-best[0]+st)*a.tap_ps:.0f} ps of {144*a.tap_ps:.0f} ps UI "
                      f"(centre tap {(best[0]+best[-1])//2})")
            s.write(b"d" + bytes([0])); time.sleep(a.dwell)
        s.write(b"F" + bytes([0]))          # unfreeze
    if a.csv:
        with open(a.csv, "w") as f:
            f.write("point,packets,bad,rxerr\n"); [f.write(",".join(map(str, r)) + "\n") for r in rows]

if __name__ == "__main__":
    main()
