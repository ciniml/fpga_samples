#!/usr/bin/env python3
"""Host-side check of the rtl/usb device (pyusb): vendor status read, vendor
register write, EP1 bulk loopback.

  usb_echo.py [--vid 1209] [--pid 0001] [--bytes 512] [--rounds 10]
"""
import argparse, os, time, usb.core, usb.util

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vid", default="1209"); ap.add_argument("--pid", default="0001")
    ap.add_argument("--bytes", type=int, default=512); ap.add_argument("--rounds", type=int, default=10)
    a = ap.parse_args()
    dev = usb.core.find(idVendor=int(a.vid, 16), idProduct=int(a.pid, 16))
    if dev is None: raise SystemExit("device not found (lsusb?)")
    print(f"found {dev.idVendor:04x}:{dev.idProduct:04x} speed={dev.speed} (3=HS 2=FS) bcdUSB={dev.bcdUSB:04x}")
    dev.set_configuration()
    st = dev.ctrl_transfer(0xC0, 0x01, 0, 0, 4)               # vendor IN: i_vendor_status
    print("vendor status:", bytes(st).hex())
    dev.ctrl_transfer(0x40, 0x02, 0x5AA5, 0, b"")              # vendor OUT: o_vendor_reg = 0x5AA5
    st = dev.ctrl_transfer(0xC0, 0x01, 0, 0, 4)
    print("vendor status after reg write:", bytes(st).hex())
    ep_out, ep_in = 0x01, 0x81
    total = 0; t0 = time.time()
    for r in range(a.rounds):
        data = os.urandom(a.bytes)
        n = dev.write(ep_out, data, timeout=1000)
        back = bytes(dev.read(ep_in, a.bytes, timeout=1000))
        if back != data[:len(back)] or len(back) != n:
            raise SystemExit(f"round {r}: mismatch (sent {n}, got {len(back)})")
        total += n
    dt = time.time() - t0
    print(f"bulk loopback OK: {a.rounds} x {a.bytes} bytes, {total / dt / 1e6:.2f} MB/s round trip")

if __name__ == "__main__":
    main()
