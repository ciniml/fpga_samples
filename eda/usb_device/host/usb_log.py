#!/usr/bin/env python3
"""Packet log of the usb_device design: arm the log ('L'), run a host-side
test, dump the ring and print the transactions the device took part in
(tokens for other addresses and SOFs are not logged).

  usb_log.py [-p /dev/ttyUSB1] [--cmd "python3 ../host/usb_echo.py --rounds 2"] [--wait 1.0]
"""
import argparse, serial, subprocess, time

PID = {0xe1:'OUT',0x69:'IN',0xa5:'SOF',0x2d:'SETUP',0xc3:'DATA0',0x4b:'DATA1',0x87:'DATA2',0x0f:'MDATA',
       0xd2:'ACK',0x5a:'NAK',0x1e:'STALL',0x96:'NYET',0x3c:'PRE',0x78:'SPLIT',0xb4:'PING'}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1"); ap.add_argument("--out", default="log.bin")
    ap.add_argument("--cmd", default=None, help="shell command to run while the log is armed")
    ap.add_argument("--wait", type=float, default=1.0)
    ap.add_argument("--decode", default=None, help="decode a previously dumped log file instead of capturing")
    a = ap.parse_args()
    if a.decode:
        raw = open(a.decode, "rb").read(); decode(raw); return
    with serial.Serial(a.port, 115200, timeout=0.05) as s:
        while s.read(4096): pass
        s.write(b"L"); time.sleep(0.2)
        if a.cmd: subprocess.run(a.cmd, shell=True)
        time.sleep(a.wait)
        while s.read(4096): pass
        s.timeout = 3; s.write(b"D")
        raw = b""
        while len(raw) < 8192 * 6:
            chunk = s.read(8192 * 6 - len(raw))
            if not chunk: break
            raw += chunk
    open(a.out, "wb").write(raw)
    decode(raw)

def decode(raw):
    # status-frame bytes may precede (or trail) the dump on the serial line: pick the byte alignment
    # under which most words carry a valid tag, and take the last 2048 words
    best = None
    for o in range(6):
        m = (len(raw) - o) // 6
        ok = sum(1 for k in range(m) if 1 <= ((int.from_bytes(raw[o+6*k:o+6*k+6], "little") >> 44) & 15) <= 4)
        if best is None or ok > best[0]: best = (ok, o)
    o = best[1]; m = (len(raw) - o) // 6; raw = raw[o:o+6*m][-8192*6:]
    n = len(raw) // 6
    ents = []
    for i in range(n):
        w = int.from_bytes(raw[6*i:6*i+6], "little")
        tag = (w >> 44) & 15; sess = (w >> 40) & 15; ts = (w >> 20) & 0xFFFFF; byte = (w >> 12) & 0xFF; extra = w & 0xFFF
        ents.append((tag, sess, ts, byte, extra))
    # the ring is dumped oldest-first; keep the latest session only
    sess = ents[-1][1] if ents else 0
    ents = [e for e in ents if e[1] == sess and e[0] != 0]
    print(f"{len(ents)} log entries (session {sess})")
    t0 = None; pkt = []
    for tag, _, ts, byte, extra in ents:
        if t0 is None: t0 = ts
        dt = ((ts - t0) & 0xFFFFF) / 60.0
        if tag == 1: pkt.append(byte)
        elif tag == 2:
            if byte == 0xff and extra == 1: print(f"{dt:10.2f} us  RX error (no packet)")
            else:
                pid = PID.get(pkt[0], f"?{pkt[0]:02x}") if pkt else "-"
                fl = f"{'ERR ' if byte & 1 else ''}{'DUP ' if byte & 2 else ''}tog_out={byte >> 2 & 1} tog_in={byte >> 3 & 1}{' in_pending' if byte & 16 else ''}"
                print(f"{dt:10.2f} us  RX {pid:6s} n={extra:4d} {' '.join(f'{b:02x}' for b in pkt[:3]):8s} {fl}")
            pkt = []
        elif tag == 3: print(f"{dt:10.2f} us  TX {PID.get(byte, f'?{byte:02x}')}")
        elif tag == 4: print(f"{dt:10.2f} us  TX end (sum {byte << 8 | (extra & 0xff):04x})")

if __name__ == "__main__":
    main()
