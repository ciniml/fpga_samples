#!/usr/bin/env python3
"""Load the colour tables of ethernet_hub75 over UDP (port 10005).

  send_lut.py gamma 2.2            all channels, gamma 2.2
  send_lut.py gamma 2.0 --ch r     only R
  send_lut.py identity             back to the identity
  send_lut.py scale 1.0 0.8 0.9    white balance: R G B gains (gamma 1)

Payload: byte 0 = channel mask (bit0 R, bit1 G, bit2 B), then 64 8-bit
values from entry 0. R / B are indexed by the 5-bit RGB565 value (the first
32 values), G by the 6-bit value. The FPGA keeps the top COMPONENT_BITS
bits, so values are rounded to --bits (default 8, the DDR2 builds; 6 for
the BSRAM builds and the Tang Primer 20K) before being sent.
"""
import argparse
import socket


def table(n_in, f, bits):
    out = []
    top = (1 << bits) - 1
    for i in range(64):
        x = min(i, n_in - 1) / (n_in - 1)
        v = round(max(0.0, min(1.0, f(x))) * top)
        out.append(v << (8 - bits))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["gamma", "identity", "scale"])
    ap.add_argument("values", nargs="*", type=float)
    ap.add_argument("--ch", default="rgb", help="channels to load (subset of rgb)")
    ap.add_argument("--bits", type=int, default=8, help="COMPONENT_BITS of the build")
    ap.add_argument("--dest", default="192.168.10.2")
    ap.add_argument("--port", type=int, default=10005)
    args = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    chans = [("r", 1, 32), ("g", 2, 64), ("b", 4, 32)]
    for idx, (name, mask, n_in) in enumerate(chans):
        if name not in args.ch:
            continue
        if args.mode == "identity":
            f = lambda x: x
        elif args.mode == "gamma":
            g = args.values[0] if args.values else 2.2
            f = lambda x, g=g: x ** g
        else:
            gain = args.values[idx] if len(args.values) > idx else 1.0
            f = lambda x, k=gain: x * k
        sock.sendto(bytes([mask] + table(n_in, f, args.bits)), (args.dest, args.port))


if __name__ == "__main__":
    main()
