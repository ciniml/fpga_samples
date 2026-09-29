#!/usr/bin/env python3
"""Arm the sample capture in the usb_device design, dump it and decode the
FS/HS line samples (8 samples per 60MHz word, bit 0 first).

  usb_capture.py [-p /dev/ttyUSB1] [--out cap.bin] [--fs]
Prints run-length encoded line states: rx (D+ comparator, D- comparator,
differential) and tx (dp, dn, oe) so packets can be read by eye; --fs
additionally decodes the FS NRZI/bit-stuffed bytes on the RX comparators.
"""
import argparse, serial, time

def rle(bits):
    out = []; cur = bits[0]; n = 0
    for b in bits:
        if b == cur: n += 1
        else: out.append((cur, n)); cur = b; n = 1
    out.append((cur, n)); return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1"); ap.add_argument("--out", default="cap.bin")
    ap.add_argument("--wait", type=float, default=3.0, help="seconds to wait for the trigger before dumping")
    ap.add_argument("--reset", type=float, default=-1, help="send R (soft reset -> re-enumeration) and arm this many seconds later")
    ap.add_argument("--on-error", action="store_true", help="arm with 'E': trigger on utmi_rxerror (ring keeps ~1800 words of history)")
    ap.add_argument("--on-tx", action="store_true", help="arm with 'T': trigger on the device's first transmission (500 words of history)")
    ap.add_argument("--on-ping", action="store_true", help="arm with 'P': trigger on a received PING (history like --on-error)")
    a = ap.parse_args()
    with serial.Serial(a.port, 115200, timeout=0.05) as s:
        while s.read(4096): pass
        if a.reset >= 0:
            s.write(b"R"); time.sleep(a.reset)
        s.write(b"E" if a.on_error else b"P" if a.on_ping else b"T" if a.on_tx else b"C"); time.sleep(a.wait)
        while s.read(4096): pass                  # status frames while waiting
        s.timeout = 3; s.write(b"D")
        raw = b""
        while len(raw) < 8192 * 6:
            chunk = s.read(8192 * 6 - len(raw))
            if not chunk: break
            raw += chunk
    open(a.out, "wb").write(raw)
    n = len(raw) // 6
    print(f"{n} words captured -> {a.out}")
    if n == 0: raise SystemExit("no dump (capture state?)")
    rx_dp = []; rx_dn = []; rx_dd = []; tx_dp = []; tx_dn = []; tx_oe = []
    for i in range(n):
        w = raw[6*i:6*i+6]
        for b in range(8):
            rx_dp.append((w[0] >> b) & 1); rx_dn.append((w[1] >> b) & 1); rx_dd.append((w[2] >> b) & 1)
            tx_dp.append((w[3] >> b) & 1); tx_dn.append((w[4] >> b) & 1); tx_oe.append(w[5] & 1)
    ra = [ (raw[6*i+5] >> 1) & 7 for i in range(n) ]   # {rxerror, rxvalid, rxactive} per word
    ls = ["SE0", "K", "J", "SE1"]   # index = dp*2 + dn ... J = D+ high (FS)
    line = [ (rx_dp[i] << 1) | rx_dn[i] for i in range(len(rx_dp)) ]
    print("RX line state (single-ended comparators), run lengths in 480MHz samples (FS bit = 40):")
    print("  " + " ".join(f"{ls[v]}x{c}" for v, c in rle(line)[:120]))
    print("TX (oe, dp/dn) run lengths:")
    tl = [ (tx_oe[i] << 2) | (tx_dp[i] << 1) | tx_dn[i] for i in range(len(tx_oe)) ]
    tn = {0:"Z",1:"Z",2:"Z",3:"Z",4:"SE0",5:"K",6:"J",7:"SE1"}
    print("  " + " ".join(f"{tn[v]}x{c}" for v, c in rle(tl)[:120]))
    print("UTMI {rxerror,rxvalid,rxactive} per 60MHz word, run lengths in words:")
    print("  " + " ".join(f"{v:03b}x{c}" for v, c in rle(ra)[:80]))
    print("RX differential receiver run lengths:")
    print("  " + " ".join(f"{v}x{c}" for v, c in rle(rx_dd)[:80]))

if __name__ == "__main__":
    main()
