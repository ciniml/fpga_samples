#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
"""Host side of eda/camera_dvi: design registers over csi_ctrl ('X' / 'Y').

  camctl.py status [-n N]          genlock (error, display line of row 0, VTS, locked)
  camctl.py mode camera|bars|raw|grey
  camctl.py gains R G B            white balance gains (e.g. 1.6 1.0 1.4)
  camctl.py black N                black level (10 bit)
  camctl.py cfa 0..3               CFA phase (3 = BGGR)
  camctl.py lock on|off            genlock
  camctl.py target N               genlock lead in lines (2..6)
  camctl.py reg ADDR [VALUE]       raw register read / write
Sensor registers, stats, logs: eda/csi_capture/host/csictl.py (same port).
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../csi_capture/host'))
import csictl  # noqa: E402

MODES = {'camera': 0, 'bars': 1, 'raw': 2, 'grey': 3}


class Cam(csictl.Csi):
    def xw(self, a, v):
        r = self.xfer([ord('X'), a, v & 0xFF, v >> 8 & 0xFF], 1)
        if r[0] != ord('x'):
            raise IOError(f'X -> {r!r}')

    def xr(self, a):
        r = self.xfer([ord('Y'), a], 3)
        return r[1] | r[2] << 8


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--port', default=None)
    sp = ap.add_subparsers(dest='cmd', required=True)
    p = sp.add_parser('status'); p.add_argument('-n', type=int, default=1); p.add_argument('-t', type=float, default=1.0)
    p = sp.add_parser('mode'); p.add_argument('mode', choices=list(MODES))
    p = sp.add_parser('gains'); p.add_argument('g', type=float, nargs=3)
    p = sp.add_parser('black'); p.add_argument('v', type=int)
    p = sp.add_parser('cfa'); p.add_argument('v', type=int, choices=range(4))
    p = sp.add_parser('lock'); p.add_argument('on', choices=['on', 'off'])
    p = sp.add_parser('target'); p.add_argument('v', type=int)
    p = sp.add_parser('reg'); p.add_argument('addr', type=lambda x: int(x, 0)); p.add_argument('val', type=lambda x: int(x, 0), nargs='?')
    a = ap.parse_args()
    c = Cam(a.port or csictl.default_port())
    if a.cmd == 'status':
        for i in range(a.n):
            if i:
                time.sleep(a.t)
            print(f'genlock: error {s16(c.xr(0x10)):+4d} lines, row 0 on display line {c.xr(0x11):4d}, '
                  f'VTS {c.xr(0x12):4d}, locked {c.xr(0x13)}, VTS writes {c.xr(0x14)}')
    elif a.cmd == 'mode':
        c.xw(0x00, MODES[a.mode])
    elif a.cmd == 'gains':
        for k, g in enumerate(a.g):
            c.xw(0x03 + k, max(0, min(0xFFFF, round(g * 256))))
    elif a.cmd == 'black':
        c.xw(0x02, a.v)
    elif a.cmd == 'cfa':
        c.xw(0x01, a.v)
    elif a.cmd == 'lock':
        c.xw(0x06, 1 if a.on == 'on' else 0)
    elif a.cmd == 'target':
        c.xw(0x07, a.v)
    elif a.cmd == 'reg':
        if a.val is None:
            print(f'{a.addr:#04x}: {c.xr(a.addr):#06x}')
        else:
            c.xw(a.addr, a.val)


if __name__ == '__main__':
    main()
