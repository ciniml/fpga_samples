#!/usr/bin/env python3
"""Print the UART status frames of the usb_device bring-up design.

  usb_status.py [-p /dev/ttyUSB1] [-b 115200] [-n 20]
frame: 'U' flags addr frame_l frame_h rst_cnt err_cnt sof_l sof_h vendor_reg_l
"""
import argparse, serial

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("-n", "--frames", type=int, default=20)
    a = ap.parse_args()
    LS = ["SE0", "J(D+)", "K(D-)", "SE1"]
    with serial.Serial(a.port, a.baud, timeout=2) as s:
        # drain everything already buffered (the OS/FTDI buffers hold minutes of old frames)
        s.timeout = 0.05
        while s.read(4096): pass
        s.timeout = 2; n = 0; buf = b""
        while n < a.frames:
            buf += s.read(64)
            i = buf.find(b"U")
            if i < 0 or len(buf) - i < 10: 
                if not buf: print("no data (bridge holding the port? wrong port?)")
                continue
            f = buf[i:i + 10]; buf = buf[i + 10:]
            fl = f[1]
            print(f"linestate={LS[fl & 3]:6s} hs={(fl >> 2) & 1} cfg={(fl >> 3) & 1} susp={(fl >> 4) & 1} "
                  f"vbus={(fl >> 5) & 1} pll={(fl >> 6) & 1} rxact={(fl >> 7) & 1} addr={f[2] >> 1} "
                  f"frame={f[3] | (f[4] << 8)} resets={f[5]} rxerr={f[6]} sofs={f[7] | (f[8] << 8)} cap={f[9]}")
            n += 1

if __name__ == "__main__":
    main()
