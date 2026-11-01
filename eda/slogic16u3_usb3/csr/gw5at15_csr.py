#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Static configuration (CSR) of the GW5AT-15 SerDes quad Q0, lane 0, without Gowin's generator.

The CSR file that PnR takes ("RES.serdes.csr") is a list of register writes,
`upar_write_driver(addr, data)`, done in that order at configuration. Addresses are byte addresses in the
quad's 24-bit register space; a write puts its byte(s) in the 32-bit data at lane addr % 4 (0x800224 <-
0x41, 0x800225 <- 0x4100 ...), the same as the runtime DRP writes seen with TAP=1.

q0_ln0_base.csr is the write list for this design's settings (eda/slogic16u3_usb3: lane 0 only,
5 Gb/s, 20 bits, gear 1:2, QPLL0 from REFCLK0 125 MHz, the quad's 8b/10b, word alignment and CTC
bypassed), with the register group names Gowin's tool gives with --comment. The fields below were
located by changing one key of the tool's input at a time (check_csr.py repeats that comparison):

  cfg_fpcs  0x809068 (base 0x1FF): bit 7 = 0 encoder on, bit 3 = 0 decoder on, bit 2 = 0 word
            alignment on, bit 5 = 0 CTC on; 0x80906c bits 9:8 = 1, 2 with CTC (3 of its 4 writes)
  rx / tx polarity: 0x809008 bit 7, 0x80903c bit 10
  signal detect threshold (sr_sd_thsel 0..7): 0x80025c = 0x11 | thsel << 5
  rxsd_use_dlogic / locked_from_fabric: 0x8082f8 bit 16 / 17 written after 0x80025c; the latter also
            clears bits 10:9 of 0x80881c
  receiver coupling DC: 0x8082dc 0x31 -> 0x21, 0x8003a7 <- 0x10000000, 0x800224..7 <- 0x41 each
  manual receiver equaliser (eq_manual): 0x8003a7 <- 0x60000000, 0x8082d4 = att x4, 0x8082d0 =
            boost x4 (one nibble each, then 1), 0x8003a2 = 0x10000 | att_boost << 17, before toggle_rxsd
  manual transmit FFE (ffe_manual): 0x808234 = txlev << 12, 0x808238 = c1 << 8 | cm, 0x8082d8 <-
            0x10, after qpll0.release_reset. Gowin's USB 3.0 PHY writes 0x808238 <- 0x805 (c1 8, cm 5:
            de-emphasis) and 0x8082d8 <- 0, 0x110 at run time when it goes to P0.

usage: gw5at15_csr.py [--comment] [--keep PREFIX ...] [--verilog] [-o out] [key=value ...]   (keys: see Lane)
  --keep: only the writes of the register groups starting with PREFIX ("none": no write at all)
  --verilog: the list as a Verilog ROM (quad_csr_rom.vh for quad_drp_mux.v, QCSR=1 builds)
"""
import argparse
import dataclasses
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LINE = re.compile(r'upar_write_driver\((0x[0-9a-fA-F]+),(0x[0-9a-fA-F]+)\)(?:\s*#\s*(.*))?')


@dataclasses.dataclass
class Lane:
    encode_8b10b: bool = False
    decode_8b10b: bool = False
    word_align: bool = False
    ctc: bool = False
    rx_pol_invert: bool = False
    tx_pol_invert: bool = False
    rx_coupling_dc: bool = False
    sr_sd_thsel: int = 3
    rxsd_use_dlogic: bool = False
    locked_from_fabric: bool = False
    eq_manual: bool = False
    rx_att: int = 7         # dr_rx_att
    rx_boost: int = 9       # dr_rx_boost
    rx_att_boost: int = 0   # dr_rx_att_boost
    ffe_manual: bool = False
    txlev: int = 15
    ffe_c1: int = 0
    ffe_cm: int = 0


def load(path=os.path.join(HERE, 'q0_ln0_base.csr')):
    out = []
    for l in open(path):
        m = LINE.match(l.strip())
        if m:
            out.append([int(m[1], 16), int(m[2], 16), m[3] or ''])
    return out


def build(p: Lane, base=None):
    w = [list(x) for x in (base or load())]

    def find(addr, group=None):
        return [i for i, (a, _, g) in enumerate(w) if a == addr and (group is None or g == group)]

    def after(addr, group, new):
        i = find(addr, group)[-1] + 1
        w[i:i] = [[a, v, g] for a, v, g in new]

    # ---- quad PCS functions
    fpcs = 0x1FF
    if p.encode_8b10b: fpcs &= ~0x80
    if p.decode_8b10b: fpcs &= ~0x08
    if p.word_align:   fpcs &= ~0x04
    if p.ctc:          fpcs &= ~0x20
    for i in find(0x809068):
        w[i][1] = fpcs
    for i in find(0x80906c):
        if w[i][2] in ('q0.ln0.cfg_ln', 'q0.ln0.setParallelTx2RxLoopBack', 'q0.ln0.cfg_fpcs'):
            w[i][1] = (w[i][1] & ~0x300) | ((2 if p.ctc else 1) << 8)
    for i in find(0x809008):
        w[i][1] = (w[i][1] & ~0x80) | (0x80 if p.rx_pol_invert else 0)
    for i in find(0x80903c):
        w[i][1] = (w[i][1] & ~0x400) | (0x400 if p.tx_pol_invert else 0)

    # ---- receiver: signal detect, CDR
    for i in find(0x80025c):
        w[i][1] = 0x11 | (p.sr_sd_thsel & 7) << 5
    if p.locked_from_fabric:
        for i in find(0x80881c):
            w[i][1] &= ~0x600
    if p.rxsd_use_dlogic or p.locked_from_fabric:
        after(0x80025c, 'q0.ln0.CDR.config_cdr',
              [(0x8082f8, (p.rxsd_use_dlogic << 16) | (p.locked_from_fabric << 17), 'q0.ln0.CDR.config_cdr')])
    if p.eq_manual:
        g = 'q0.ln0.CDR.eq_base_par_config'
        nib = lambda v: (v & 0xF) * 0x11110 | 1
        after(0x800ad4, 'q0.ln0.CDR.config_cdr',
              [(0x8003a7, 0x60000000, g), (0x8082d4, nib(p.rx_att), g), (0x8082d0, nib(p.rx_boost), g),
               (0x8003a2, 0x10000 | (p.rx_att_boost & 1) << 17, g)])
    if p.rx_coupling_dc:
        g = 'q0.ln0.cfg_rx_couple_mode'
        for i in find(0x8082dc, g):
            w[i][1] = 0x21
        for i in find(0x8003a7, g):
            w[i][1] = 0x10000000
        after(0x8003a7, g, [(0x800224 + k, 0x41 << (8 * k), g) for k in range(4)])

    # ---- transmitter FFE
    if p.ffe_manual:
        g = 'q0.ln0.cfg_txFFE'
        after(0x808104, 'q0.qpll0.release_reset',
              [(0x808234, (p.txlev & 0xF) << 12, g), (0x808238, (p.ffe_c1 & 0xF) << 8 | (p.ffe_cm & 0xF), g),
               (0x8082d8, 0x10, g)])
    return w


def text(writes, comment=False):
    return ''.join(f'upar_write_driver(0x{a:06x},0x{v:08X})' + (f' # {g}' if comment else '') + '\n'
                   for a, v, g in writes)


def verilog(writes):
    n = len(writes)
    s = ['// generated by csr/gw5at15_csr.py: quad register writes, {addr[23:0], data[31:0]}',
         f'localparam QCSR_N = {n};',
         'function [55:0] qcsr_rom(input [8:0] i);',
         '    case (i)']
    s += [f"    9'd{i}: qcsr_rom = {{24'h{a:06x}, 32'h{v:08x}}}; // {g}" for i, (a, v, g) in enumerate(writes)]
    s += ["    default: qcsr_rom = 56'd0;", '    endcase', 'endfunction', '']
    return '\n'.join(s)


def keep(writes, prefixes):
    if not prefixes:
        return writes
    return [w for w in writes if any(w[2].startswith(p) for p in prefixes if p != 'none')]


def parse_kv(items):
    p = Lane()
    for kv in items:
        k, v = kv.split('=', 1)
        t = type(getattr(p, k))
        setattr(p, k, (v.lower() in ('1', 'true', 'yes')) if t is bool else int(v, 0))
    return p


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--comment', action='store_true', help='register group names, as Gowin --comment')
    ap.add_argument('--keep', action='append', help='only these register groups (prefix; "none": nothing)')
    ap.add_argument('--verilog', action='store_true')
    ap.add_argument('-o', '--out')
    ap.add_argument('kv', nargs='*', help='Lane field=value')
    a = ap.parse_args()
    w = keep(build(parse_kv(a.kv)), a.keep)
    s = verilog(w) if a.verilog else text(w, a.comment)
    if a.out:
        open(a.out, 'w').write(s)
    else:
        sys.stdout.write(s)


if __name__ == '__main__':
    main()
