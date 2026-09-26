#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
"""Host side of loop_report (eda/dvi_loopback, eda/dvi_capture).

  loopctl.py status [sec]          print R lines for sec seconds
  loopctl.py scan  [target]        coarse scan (0x00..0xFC step 4) of target
  loopctl.py fine  [target]        1-tap scan of target -16..+15
  loopctl.py words                 raw 10-bit words of the three lanes
  loopctl.py send <chars>          send command characters

  target: a = common offset (default), 0 / 1 / 2 = lane trim.
  The port defaults to the Tang Primer 25K USB Debugger's second
  interface (override with --port).
"""
import argparse
import glob
import sys
import time

import serial

LINE_MIN = 158


def default_port():
    ports = sorted(glob.glob('/dev/serial/by-id/*USB_Debugger*if01*'))
    return ports[0] if ports else '/dev/ttyUSB1'


class Loop:
    def __init__(self, port):
        self.p = serial.Serial(port, 115200, timeout=0.1)

    def send(self, chars):
        for c in chars:
            self.p.write(c.encode())
            time.sleep(0.02)

    def read_for(self, sec, until=None):
        buf = b''
        t = time.time()
        while time.time() - t < sec:
            buf += self.p.read(4096)
            if until and until(buf):
                break
        return buf.decode(errors='replace').replace('\r', '')

    def fresh(self):
        """Drop everything buffered so far (including a partial line)."""
        self.p.reset_input_buffer()
        self.read_for(0.2)

    def lines(self, sec, kind='R'):
        self.fresh()
        return [parse(l) for l in self.read_for(sec).splitlines() if is_line(l, kind)]

    def scan(self, target, fine=False):
        n = 32 if fine else 64
        self.fresh()
        self.send(target + ('f' if fine else 's'))
        txt = self.read_for(150, lambda b: b.count(b'\nS L') >= n)
        return [parse(l) for l in txt.splitlines() if is_line(l, 'S')]

    def words(self):
        self.fresh()
        self.send('w')
        txt = self.read_for(3, lambda b: b.count(b'\nW2') >= 1 and b.endswith(b'\n'))
        return [l for l in txt.splitlines() if l.startswith('W')]


def is_line(l, kind):
    return l.startswith(kind + ' ') and len(l) >= LINE_MIN


def parse(l):
    """Fixed positions of loop_report's R / S line."""
    h = lambda a, b: int(l[a:b + 1], 16)
    return dict(kind=l[0], L=l[3], F=h(6, 13), B=h(16, 23), E=h(26, 33),
                E0=h(37, 42), E1=h(46, 51), E2=h(55, 60), U=h(63, 66),
                N=h(69, 76), O=h(79, 80), P=l[83], C=h(86, 93),
                X=h(96, 103), Y=h(106, 113),
                Z0=h(117, 124), Z1=h(128, 135), Z2=h(139, 146),
                K=l[149:155], T=l[157])


def fmt(r):
    return (f"O{r['O']:02X} K{r['K']} L{r['L']} F{r['F']:4d} B{r['B']:4d} "
            f"E{r['E']:9d} [{r['E0']:8d} {r['E1']:8d} {r['E2']:8d}] U{r['U']} N{r['N']:8d} "
            f"X{r['X']:6d} Y{r['Y']:08X} Z[{r['Z0']} {r['Z1']} {r['Z2']}]")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default=default_port())
    ap.add_argument('cmd')
    ap.add_argument('arg', nargs='?')
    a = ap.parse_args()
    lp = Loop(a.port)
    if a.cmd == 'status':
        for r in lp.lines(float(a.arg or 3)):
            print(fmt(r))
    elif a.cmd in ('scan', 'fine'):
        for r in lp.scan(a.arg or 'a', fine=a.cmd == 'fine'):
            print(fmt(r))
    elif a.cmd == 'words':
        print('\n'.join(lp.words()))
    elif a.cmd == 'send':
        lp.send(a.arg)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
