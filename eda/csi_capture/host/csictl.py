#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
"""Host side of eda/csi_capture (csi_ctrl.sv binary protocol, 115200 8N1).

  csictl.py ping                  version byte
  csictl.py id                    sensor chip id (IMX219: 0x0219)
  csictl.py rd 0x0100             register read
  csictl.py wr 0x0100 1           register write
  csictl.py init                  rerun the FPGA's init ROM (640x480, 2 x 456 Mbps)
  csictl.py rate 456|912          output PLL (lane rate) via standby / stream
  csictl.py tp 0..9               IMX219 test pattern (0 off, 2 colour bars, 4 PN9 ...)
  csictl.py stream on|off
  csictl.py trim OFS0 OFS1 [INV]  receiver sample offsets (8 = at the clock edge)
  csictl.py stats [-n N] [-t S]   rates: lane bit rate, fps, lines, CRC / ECC errors
  csictl.py scan                  sweep both offsets, CRC errors per setting
  csictl.py log [--at-fs]         packet log (one line per packet)
  csictl.py capture [-m MODE] [-o FILE]   raw lane samples + software decode
  csictl.py decode FILE           decode a saved capture again
The port defaults to the Tang Primer 25K USB Debugger's second interface.
"""
import argparse
import glob
import struct
import sys
import time

STAT_NAMES = [
    'words', 'bits', 'words_active', 'bits_active', 'ovf', 'sync0', 'sync1',
    'hdr', 'fs', 'fe', 'short_other', 'long_pix', 'long_emb', 'long_other',
    'crc_ok', 'crc_err', 'ecc_corr', 'ecc_err', 'abort', 'drop',
    'lines', 'last', 'frame_period', 'frame_num', 'status',
]
PCLK_HZ = 125e6
SAMPLES_PER_NS = 4.0
DT_NAMES = {0x00: 'FS', 0x01: 'FE', 0x02: 'LS', 0x03: 'LE', 0x12: 'EMB', 0x2A: 'RAW8', 0x2B: 'RAW10'}
CAP_MODES = {'now': 0, 'clock': 1, 'sync': 2, 'error': 3, 'fs': 4}


def default_port():
    ports = sorted(glob.glob('/dev/serial/by-id/*USB_Debugger*if01*'))
    return ports[0] if ports else '/dev/ttyUSB1'


class Csi:
    def __init__(self, port):
        import serial
        self.p = serial.Serial(port, 115200, timeout=2.0)
        self.p.reset_input_buffer()

    def xfer(self, req, n):
        self.p.write(bytes(req))
        r = self.p.read(n)
        if len(r) != n:
            raise IOError(f'short reply to {bytes(req[:1])!r}: {r!r}')
        return r

    def ping(self):
        r = self.xfer(b'P', 2)
        return r[1]

    def wr(self, addr, val):
        r = self.xfer([ord('W'), addr >> 8, addr & 0xFF, val & 0xFF], 2)
        if r[1]:
            print(f'NACK writing {addr:04x}', file=sys.stderr)
        return r[1] == 0

    def rd(self, addr):
        r = self.xfer([ord('R'), addr >> 8, addr & 0xFF], 3)
        if r[2]:
            print(f'NACK reading {addr:04x}', file=sys.stderr)
        return r[1]

    def init(self):
        self.p.timeout = 5.0
        r = self.xfer(b'I', 2)
        self.p.timeout = 2.0
        return r[1]

    def trim(self, ofs0, ofs1, inv=0):
        self.xfer([ord('C'), (ofs1 << 4) | ofs0, inv], 1)

    def stats(self):
        r = self.xfer(b'S', 1 + 4 * len(STAT_NAMES))
        v = struct.unpack('<%dI' % len(STAT_NAMES), r[1:])
        return dict(zip(STAT_NAMES, v))

    def arm_capture(self, mode):
        self.xfer([ord('A'), mode], 1)

    def read_capture(self):
        self.p.timeout = 10.0
        r = self.xfer(b'G', 1 + 1024 * 12)
        self.p.timeout = 2.0
        return r[1:]

    def arm_log(self, at_fs):
        self.xfer([ord('E'), 1 if at_fs else 0], 1)

    def read_log(self, n):
        self.p.timeout = 10.0
        r = self.xfer([ord('L'), n & 0xFF, n >> 8], 1 + 8 * n)
        self.p.timeout = 2.0
        return [struct.unpack('<Q', r[1 + 8 * i: 9 + 8 * i])[0] for i in range(n)]


def status_fields(s):
    st = s['status']
    return {'cap_done': st >> 31 & 1, 'cap_wp': st >> 16 & 0x3FF,
            'log_full': st >> 15 & 1, 'log_count': st & 0x7FF}


def print_rates(a, b):
    d = {k: (b[k] - a[k]) & 0xFFFFFFFF for k in STAT_NAMES}
    sec = d['words'] / PCLK_HZ if d['words'] else 0.0
    rate = d['bits_active'] / d['words_active'] * PCLK_HZ / 1e6 if d['words_active'] else 0.0
    fps = PCLK_HZ / b['frame_period'] if b['frame_period'] else 0.0
    last = b['last']
    longs = d['crc_ok'] + d['crc_err']
    print(f"{sec:5.2f}s lane {rate:6.1f} Mb/s | FS {d['fs']:4d} FE {d['fe']:4d} ({fps:5.1f} fps, frame #{b['frame_num']}) "
          f"| lines {b['lines']:4d} last DT {last >> 16 & 0x3F:02x} WC {last & 0xFFFF} "
          f"| long {longs} CRC err {d['crc_err']} ECC corr {d['ecc_corr']} err {d['ecc_err']} abort {d['abort']} "
          f"| sync {d['sync0']}/{d['sync1']} ovf {d['ovf']}")
    return d


# ---------------------------------------------------------------- decoding
def cap_words(raw, wp):
    """capture memory -> time-ordered list of (clk, d0, d1) 32-bit words"""
    w = [struct.unpack('<III', raw[12 * i: 12 * i + 12]) for i in range(1024)]
    return w[wp:] + w[:wp]


def to_bits(words, k):
    out = []
    for w in words:
        out.extend((w[k] >> i) & 1 for i in range(32))
    return out


def decode(words, ofs=(8, 8), zeros=24, verbose=True):
    c = to_bits(words, 0)
    d = [to_bits(words, 1), to_bits(words, 2)]
    n = len(c)
    m = [c[0]] + [1 if c[i - 1] + c[i] + c[i + 1] >= 2 else 0 for i in range(1, n - 1)] + [c[-1]]
    edges = [i for i in range(1, n) if m[i] != m[i - 1]]
    if verbose:
        trans = [sum(1 for i in range(1, n) if x[i] != x[i - 1]) for x in (c, d[0], d[1])]
        print(f'{len(words)} words = {n / SAMPLES_PER_NS / 1000:.2f} us; raw transitions clk {trans[0]} d0 {trans[1]} d1 {trans[2]}; '
              f'clock edges (filtered) {len(edges)}')
        if len(edges) > 2:
            gaps = [b - a for a, b in zip(edges, edges[1:])]
            hs = [g for g in gaps if g < 40]
            if hs:
                ui = sum(hs) / len(hs) / SAMPLES_PER_NS
                print(f'  mean edge spacing {ui:.3f} ns -> {1000 / ui:.1f} Mb/s per lane; '
                      f'spacing histogram {sorted(set(hs))[:12]}')
    lanes = []
    for l in range(2):
        bits = [(d[l][i + ofs[l] - 8] if 0 <= i + ofs[l] - 8 < n else 0) for i in edges]
        lanes.append(bits)
    syncw = (0xB8 << zeros)
    mask = (1 << (zeros + 8)) - 1
    res = []
    for l, bits in enumerate(lanes):
        sr = mask
        bursts = []
        cur = None
        for i, b in enumerate(bits):
            sr = ((sr >> 1) | (b << (zeros + 7))) & mask
            if sr == syncw:
                cur = []
                bursts.append((edges[i], cur))
                acc, cnt = 0, 0
                continue
            if cur is not None:
                acc = (acc >> 1) | (b << 7)
                cnt += 1
                if cnt == 8:
                    cur.append(acc)
                    cnt = 0
        res.append(bursts)
        if verbose:
            for t, by in bursts:
                print(f'  lane {l}: sync at sample {t} ({t / SAMPLES_PER_NS:.0f} ns): ' + ' '.join(f'{x:02x}' for x in by[:24])
                      + (' ...' if len(by) > 24 else ''))
    if verbose:
        for (t0, b0), (t1, b1) in zip(res[0], res[1]):
            if len(b0) >= 2 and len(b1) >= 2:
                di, wcl, wch, ecc = b0[0], b1[0], b0[1], b1[1]
                wc = wcl | wch << 8
                print(f'  packet: DI {di:02x} ({DT_NAMES.get(di & 0x3F, "?")}, VC {di >> 6}) WC {wc} ECC {ecc:02x} '
                      f'(expect {ecc6(di | wcl << 8 | wch << 16):02x})')
    return res


ECC_COLS = [0x07, 0x0B, 0x0D, 0x0E, 0x13, 0x15, 0x16, 0x19, 0x1A, 0x1C, 0x23, 0x25,
            0x26, 0x29, 0x2A, 0x2C, 0x31, 0x32, 0x34, 0x38, 0x1F, 0x2F, 0x37, 0x3B]


def ecc6(d):
    e = 0
    for i in range(24):
        if d >> i & 1:
            e ^= ECC_COLS[i]
    return e


# ---------------------------------------------------------------- commands
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--port', default=None)
    sp = ap.add_subparsers(dest='cmd', required=True)
    sp.add_parser('ping')
    sp.add_parser('id')
    p = sp.add_parser('rd'); p.add_argument('addr', type=lambda x: int(x, 0)); p.add_argument('n', nargs='?', type=int, default=1)
    p = sp.add_parser('wr'); p.add_argument('addr', type=lambda x: int(x, 0)); p.add_argument('val', type=lambda x: int(x, 0))
    sp.add_parser('init')
    p = sp.add_parser('rate'); p.add_argument('mbps', type=int, choices=[456, 912])
    p = sp.add_parser('tp'); p.add_argument('pattern', type=int)
    p = sp.add_parser('stream'); p.add_argument('on', choices=['on', 'off'])
    p = sp.add_parser('trim'); p.add_argument('ofs0', type=int); p.add_argument('ofs1', type=int); p.add_argument('inv', type=int, nargs='?', default=0)
    p = sp.add_parser('stats'); p.add_argument('-n', type=int, default=0); p.add_argument('-t', type=float, default=1.0)
    p = sp.add_parser('scan'); p.add_argument('-t', type=float, default=0.5)
    p = sp.add_parser('log'); p.add_argument('--at-fs', action='store_true'); p.add_argument('-n', type=int, default=64)
    p = sp.add_parser('capture'); p.add_argument('-m', '--mode', choices=list(CAP_MODES), default='clock'); p.add_argument('-o', '--out')
    p.add_argument('--ofs', type=int, nargs=2, default=[8, 8])
    p = sp.add_parser('decode'); p.add_argument('file'); p.add_argument('--ofs', type=int, nargs=2, default=[8, 8])
    a = ap.parse_args()

    if a.cmd == 'decode':
        raw = open(a.file, 'rb').read()
        wp = struct.unpack('<H', raw[:2])[0]
        decode(cap_words(raw[2:], wp), tuple(a.ofs))
        return

    c = Csi(a.port or default_port())
    if a.cmd == 'ping':
        print(f'version {c.ping():#04x}')
    elif a.cmd == 'id':
        cid = c.rd(0x0000) << 8 | c.rd(0x0001)
        print(f'chip id {cid:#06x}' + (' (IMX219)' if cid == 0x0219 else ''))
    elif a.cmd == 'rd':
        for i in range(a.n):
            print(f'{a.addr + i:04x}: {c.rd(a.addr + i):02x}')
    elif a.cmd == 'wr':
        c.wr(a.addr, a.val)
    elif a.cmd == 'init':
        n = c.init()
        print('init done' + (f', {n} NACKs' if n else ''))
    elif a.cmd == 'rate':
        mpy = 57 if a.mbps == 456 else 114
        c.wr(0x0100, 0)
        time.sleep(0.05)
        c.wr(0x030C, mpy >> 8)
        c.wr(0x030D, mpy & 0xFF)
        c.wr(0x0100, 1)
    elif a.cmd == 'tp':
        c.wr(0x0600, a.pattern >> 8)
        c.wr(0x0601, a.pattern & 0xFF)
    elif a.cmd == 'stream':
        c.wr(0x0100, 1 if a.on == 'on' else 0)
    elif a.cmd == 'trim':
        c.trim(a.ofs0, a.ofs1, a.inv)
    elif a.cmd == 'stats':
        prev = c.stats()
        i = 0
        while a.n == 0 or i < a.n:
            time.sleep(a.t)
            cur = c.stats()
            print_rates(prev, cur)
            prev = cur
            i += 1
    elif a.cmd == 'scan':
        print('ofs0 ofs1 : long  crc_err  ecc_err')
        for o in range(16):
            c.trim(o, o)
            time.sleep(0.05)
            s0 = c.stats()
            time.sleep(a.t)
            s1 = c.stats()
            d = {k: (s1[k] - s0[k]) & 0xFFFFFFFF for k in STAT_NAMES}
            print(f'{o:4d} {o:4d} : {d["crc_ok"] + d["crc_err"]:5d} {d["crc_err"]:8d} {d["ecc_err"]:8d}')
        c.trim(8, 8)
    elif a.cmd == 'log':
        c.arm_log(a.at_fs)
        t0 = time.time()
        while True:
            st = status_fields(c.stats())
            if st['log_count'] >= a.n or st['log_full'] or time.time() - t0 > 3.0:
                break
            time.sleep(0.05)
        n = min(st['log_count'], 1024)
        recs = c.read_log(n)
        t_first = None
        for r in recs:
            ts = (r >> 40) * 256 / PCLK_HZ * 1e6
            if t_first is None:
                t_first = ts
            kind, flags, di, wc = r >> 36 & 0xF, r >> 32 & 0xF, r >> 24 & 0xFF, r >> 8 & 0xFFFF
            name = DT_NAMES.get(di & 0x3F, f'DT{di & 0x3F:02x}')
            if kind == 1:
                print(f'{ts - t_first:10.1f} us  {name:5s} VC{di >> 6} data {wc}' + (' (ECC corrected)' if flags & 1 else ''))
            elif kind == 2:
                print(f'{ts - t_first:10.1f} us  {name:5s} VC{di >> 6} WC {wc:5d} CRC {"ok" if flags & 1 else "BAD"}'
                      + (' (ECC corrected)' if flags & 2 else ''))
            elif kind == 3:
                print(f'{ts - t_first:10.1f} us  header ECC error')
            else:
                print(f'{ts - t_first:10.1f} us  abort (sync inside a packet)')
    elif a.cmd == 'capture':
        c.arm_capture(CAP_MODES[a.mode])
        t0 = time.time()
        while True:
            st = status_fields(c.stats())
            if st['cap_done']:
                break
            if time.time() - t0 > 3.0:
                print('no trigger within 3 s', file=sys.stderr)
                sys.exit(1)
            time.sleep(0.05)
        raw = c.read_capture()
        if a.out:
            with open(a.out, 'wb') as f:
                f.write(struct.pack('<H', st['cap_wp']) + raw)
        decode(cap_words(raw, st['cap_wp']), tuple(a.ofs))


if __name__ == '__main__':
    main()
