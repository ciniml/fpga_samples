#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Read / write the GW5AT-15 SerDes quad registers over USB (NOARB=1 builds: vendor requests 0x03 / 0x04
to top.v, which runs the access on the quad's register port next to our PHY, quad_drp_mux.v).
Addresses are the byte addresses of the CSR (csr/gw5at15_csr.py): the value is the 32-bit word with the
addressed byte(s) in lane addr % 4.

    quad_reg.py read 0x808238 [0x808234 ...]
    quad_reg.py write 0x808238 0x805
    quad_reg.py csr [file.csr]      read back every address of the CSR, against the value written last
"""
import argparse
import os
import sys
import time

import usb.core

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '../csr'))


class Quad:
    def __init__(self):
        self.dev = usb.core.find(idVendor=0x1209, idProduct=0x0001)
        if self.dev is None:
            sys.exit('device not found')

    def _w(self, reg, val):
        self.dev.ctrl_transfer(0x40, 0x03, val & 0xFFFF, reg, b'')

    def _r(self, reg):
        return int.from_bytes(bytes(self.dev.ctrl_transfer(0xC0, 0x04, 0, reg, 4)), 'little')

    def _run(self, addr, data, wr):
        n0 = self._r(3) >> 16
        self._w(0, addr & 0xFFFF)
        self._w(1, addr >> 16)
        if wr:
            self._w(2, data & 0xFFFF)
            self._w(3, data >> 16)
        if self._r(0) != addr:
            raise RuntimeError(f'address register reads 0x{self._r(0):06x}, not 0x{addr:06x}')
        self._w(4, 1 if wr else 0)
        t = time.time() + 0.5
        while True:
            st = self._r(3)
            if not st & 1 and (st >> 16) == (n0 + 1) & 0xFFFF:
                break
            if time.time() > t:
                raise RuntimeError(f'access to 0x{addr:06x} did not finish (status 0x{st:08x})')

    def read(self, addr):
        self._run(addr, 0, False)
        return self._r(2)

    def write(self, addr, data):
        self._run(addr, data, True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('read'); p.add_argument('addr', nargs='+')
    p = sp.add_parser('write'); p.add_argument('addr'); p.add_argument('data')
    p = sp.add_parser('csr'); p.add_argument('file', nargs='?')
    a = ap.parse_args()
    q = Quad()
    if a.cmd == 'read':
        for x in a.addr:
            ad = int(x, 0)
            print(f'0x{ad:06x}: 0x{q.read(ad):08X}')
    elif a.cmd == 'write':
        q.write(int(a.addr, 0), int(a.data, 0))
    else:
        import gw5at15_csr as g
        w = g.load(a.file) if a.file else g.load()
        last = {}
        for ad, v, grp in w:
            last[ad] = (v, grp)
        same = 0
        for ad in sorted(last):
            v, grp = last[ad]
            r = q.read(ad)
            lane = (ad & 3) * 8
            # compare from the addressed byte up (the bytes below belong to other addresses)
            m = (0xFFFFFFFF << lane) & 0xFFFFFFFF
            ok = (r & m) == (v & m)
            same += ok
            print(f'0x{ad:06x} {grp:36s} wrote 0x{v:08X} read 0x{r:08X} {"" if ok else "  <- differs"}')
        print(f'{same} / {len(last)} addresses read back what was written last')


if __name__ == '__main__':
    main()
