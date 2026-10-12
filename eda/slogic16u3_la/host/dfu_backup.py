#!/usr/bin/env python3
"""Back up the SLogic16U3 SPI flash through the official DFU USB-SPI bridge (read only).

    host/dfu_backup.py --tools <sipeed/slogic16u3-tools> --out DIR [--reads 2] [REGION ...]

The board must be in DFU mode (MODE button; 359f:30f1 "SLogic DFU"). REGION is ADDR:LENGTH,
by default 0x0:0x100000 (the application: the official one ends near 0x78CF7, this design at
0x9186A) and 0x800000:0x60000 (the DFU image). Each region is read --reads times and must come
back the same; it is written as DIR/slogic16u3_<addr>.bin with a SHA256SUMS file. Nothing is
erased or programmed.

Uses SPIFlashDevice of the official tool (slogicpt/dfu, Fast Read 0x0B in 64-byte pieces).
"""
import argparse
import hashlib
import os
import sys
import time


def region(s):
    a, n = s.split(":")
    return int(a, 0), int(n, 0)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--tools", required=True, help="checkout of sipeed/slogic16u3-tools")
    ap.add_argument("--out", required=True, help="output directory")
    ap.add_argument("--reads", type=int, default=2, help="reads per region that must agree (default 2)")
    ap.add_argument("--pid", type=lambda s: int(s, 0), default=0x30F1)
    ap.add_argument("regions", nargs="*", type=region, default=[(0x0, 0x100000), (0x800000, 0x60000)])
    a = ap.parse_args()

    sys.path.insert(0, a.tools)
    from slogicpt.dfu.spi_flash import SPIFlashDevice

    os.makedirs(a.out, exist_ok=True)
    sums = []
    with SPIFlashDevice(0x359F, a.pid) as f:
        if not f.reset():
            sys.exit("SPI flash reset failed")
        jid = f.read_id().hex()
        print("flash JEDEC ID", jid)
        if jid in ("ffffff", "000000"):
            sys.exit("flash not responding")
        for addr, n in a.regions:
            t = time.time()
            reads = [f.read_data(addr, n) for _ in range(a.reads)]
            if any(r != reads[0] for r in reads[1:]):
                sys.exit(f"0x{addr:06X}: the reads differ - not saved")
            d = reads[0]
            name = f"slogic16u3_0x{addr:06X}.bin"
            open(os.path.join(a.out, name), "wb").write(d)
            h = hashlib.sha256(d).hexdigest()
            sums.append(f"{h}  {name}")
            used = len(d.rstrip(b"\xff"))
            print(f"0x{addr:06X}+0x{n:X} -> {name} (data up to +0x{used:X}, {a.reads} reads agree, {time.time() - t:.1f} s)")
    with open(os.path.join(a.out, "SHA256SUMS"), "a") as s:
        s.write("\n".join(sums) + "\n")


if __name__ == "__main__":
    main()
