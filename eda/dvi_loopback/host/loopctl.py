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
  loopctl.py gamma <g> [rgb] [bits]  colour tables (eda/dvi_hub75): out = in^g,
                                   rounded to `bits` (default 6) displayed bits;
                                   rgb = channels to write (default rgb)
  loopctl.py gamma identity        tables back to identity ("i")
  loopctl.py audio [sec]           HDMI audio / packet status (eda/dvi_hub75)

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
        # (count S lines at line starts, including one at the very start)
        txt = self.read_for(150, lambda b: (b'\n' + b).count(b'\nS L') >= n and b.endswith(b'\n'))
        return [parse(l) for l in txt.splitlines() if is_line(l, 'S')]

    def send_gamma(self, table, chans='rgb'):
        """Upload a 256-entry table: "G" <mask> <512 hex digits>."""
        mask = sum(1 << 'rgb'.index(c) for c in chans)
        self.send('G%X' % mask)
        self.p.write(''.join('%02X' % v for v in table).encode())
        self.p.flush()

    def words(self):
        self.fresh()
        self.send('w')
        txt = self.read_for(3, lambda b: b.count(b'\nW2') >= 1 and b.endswith(b'\n'))
        return [l for l in txt.splitlines() if l.startswith('W')]


def gamma_table(g, bits=6):
    """8-bit table for out = in^g, rounded to the `bits` displayed bits
    (the hardware shows the top `bits` of each entry)."""
    top = (1 << bits) - 1
    return [round(((i / 255.0) ** g) * top) << (8 - bits) for i in range(256)]


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


def audio(r, pclk):
    """eda/dvi_hub75 packs the HDMI packet / audio state into Z0..Z2."""
    z0, z1, z2 = r['Z0'], r['Z1'], r['Z2']
    n, cts = z1 >> 12, z2 >> 12
    fs = pclk * n / (128 * cts) if cts else 0
    return (f"pkts {z0 >> 16:5d} hdr_err {(z0 >> 8) & 0xFF:3d} sub_err {z0 & 0xFF:3d} "
            f"sym_err {z1 & 1} | N {n} CTS {cts} fs {fs:8.1f} Hz | "
            f"running {(z1 >> 1) & 1} level {((z1 >> 3) & 0x1FF) * 2:3d} "
            f"underrun {(z2 >> 6) & 0x3F} overflow {z2 & 0x3F} | limited_range {(z1 >> 2) & 1}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default=default_port())
    ap.add_argument('cmd')
    ap.add_argument('arg', nargs='?')
    ap.add_argument('extra', nargs='*')
    a = ap.parse_args()
    lp = Loop(a.port)
    if a.cmd == 'status':
        for r in lp.lines(float(a.arg or 3)):
            print(fmt(r))
    elif a.cmd in ('scan', 'fine'):
        for r in lp.scan(a.arg or 'a', fine=a.cmd == 'fine'):
            print(fmt(r))
    elif a.cmd == 'audio':
        rs = lp.lines(float(a.arg or 3))
        for prev, r in zip(rs, rs[1:]):
            # C = pixel clocks, R lines are 1 s apart
            pclk = ((r['C'] - prev['C']) & 0xFFFFFFFF) or 74.25e6
            print(audio(r, pclk))
    elif a.cmd == 'words':
        print('\n'.join(lp.words()))
    elif a.cmd == 'send':
        lp.send(a.arg)
    elif a.cmd == 'gamma':
        if a.arg == 'identity':
            lp.send('i')
        else:
            g = float(a.arg)
            chans = a.extra[0] if a.extra else 'rgb'
            bits = int(a.extra[1]) if len(a.extra) > 1 else 6
            lp.send_gamma(gamma_table(g, bits), chans)
    else:
        sys.exit(__doc__)


if __name__ == '__main__':
    main()
