#!/usr/bin/env python3
"""Make a built bitstream boot right as the SLogic16U3 flash application.

    host/mkdfu.py build/<dir>/impl/pnr/slogic16u3_la.fs OUT_PREFIX [--next 0x800000]

writes OUT_PREFIX.bin (for the official DFU tool) and OUT_PREFIX.fs (the same bits, for a JTAG
SRAM load). The SLogic16U3 flash holds the application at 0x0 and Sipeed's DFU image at
0x800000; the MODE button reconfigures the FPGA, which then loads the "next multiboot
address" of the running bitstream. The official images point at each other (app -> DFU ->
app), so the application written at 0x0 must point at 0x800000, or MODE reloads it and DFU
is out of reach.

That address is the word after command 0xD2 in the bitstream header (Gowin's -multi_boot 1
-multiboot_spi_flash_address); patching it is enough (the frame CRCs do not cover it), and
keeps the place and route of the build - running PnR again with the option changed the timing.
"""
import argparse
import sys


def fs_bits(lines):
    return [i for i, l in enumerate(lines) if l and set(l) <= set("01")]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("fs", help="bitstream (.fs) from the build")
    ap.add_argument("out", help="output prefix (OUT.bin, OUT.fs)")
    ap.add_argument("--next", type=lambda s: int(s, 0), default=0x800000, help="next multiboot address (default 0x800000, the DFU image)")
    a = ap.parse_args()

    lines = open(a.fs).read().split("\n")
    idx = fs_bits(lines)
    bits = "".join(lines[i] for i in idx)
    b = bytearray(int(bits[k:k + 8], 2) for k in range(0, len(bits) // 8 * 8, 8))

    sync = b.find(b"\xa5\xc3")
    if sync < 0:
        sys.exit("no A5 C3 sync word (encrypted or not a GW5A bitstream?)")
    # header commands after the sync: 4-byte words; the multiboot one is D2 00 FF FF + address
    p = b.find(b"\xd2\x00\xff\xff", sync, sync + 0x100)
    if p < 0 or (p - sync) % 4 != 2:
        sys.exit("no multiboot (0xD2) command in the header")
    old = int.from_bytes(b[p + 4:p + 8], "big")
    b[p + 4:p + 8] = a.next.to_bytes(4, "big")
    open(a.out + ".bin", "wb").write(b)

    nb = "".join(f"{x:08b}" for x in b)
    pos = 0
    for i in idx:
        n = len(lines[i])
        lines[i] = nb[pos:pos + n]
        pos += n
    open(a.out + ".fs", "w").write("\n".join(lines))
    print(f"next multiboot address 0x{old:06X} -> 0x{a.next:06X} (header offset 0x{p + 4:X}); "
          f"{a.out}.bin ({len(b)} bytes), {a.out}.fs")


if __name__ == "__main__":
    main()
