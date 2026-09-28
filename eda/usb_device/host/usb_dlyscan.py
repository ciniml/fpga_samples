#!/usr/bin/env python3
"""Sweep the dynamic IODELAY taps of the single-ended receive paths and print
how well their samples agree with the differential receiver during HS traffic.

  usb_dlyscan.py [-p /dev/ttyUSB1] [--path p|n|d] [--step 8] [--max 255]
Reply of 'm': 'M' active(32) match_dp(32) match_dn(32) (samples; dn counted inverted).
"""
import argparse, serial, struct, time

def measure(s):
    s.write(b"m")
    t0 = time.time(); buf = b""
    while time.time() - t0 < 3:
        buf += s.read(64)
        i = buf.find(b"M")
        while i >= 0 and len(buf) - i >= 13:
            act, mdp, mdn = struct.unpack_from("<III", buf, i + 1)
            if act and mdp <= act and mdn <= act:   # plausible frame (status frames use 'U')
                return act, mdp, mdn
            i = buf.find(b"M", i + 1)
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1")
    ap.add_argument("--path", default="p", help="which delay to sweep: p (D+ comparator), n (D- comparator), d (differential)")
    ap.add_argument("--step", type=int, default=8); ap.add_argument("--max", type=int, default=255)
    ap.add_argument("--fixed", default="", help="other taps, e.g. d=40,n=0")
    a = ap.parse_args()
    with serial.Serial(a.port, 115200, timeout=0.05) as s:
        while s.read(4096): pass
        for kv in filter(None, a.fixed.split(",")):
            k, v = kv.split("="); s.write(k.encode() + bytes([int(v)]))
        print(f"sweep '{a.path}' 0..{a.max} step {a.step} ({12.5:.1f} ps/tap, HS UI = 2083 ps = 167 taps)")
        for tap in range(0, a.max + 1, a.step):
            s.write(a.path.encode() + bytes([tap])); time.sleep(0.02)
            r = measure(s)
            if r is None: print(f"tap {tap:3d}: no reply"); continue
            act, mdp, mdn = r
            print(f"tap {tap:3d} ({tap * 12.5:6.0f} ps): active {act:9d}  dp==dd {mdp / act * 100:6.2f}%  ~dn==dd {mdn / act * 100:6.2f}%")

if __name__ == "__main__":
    main()
