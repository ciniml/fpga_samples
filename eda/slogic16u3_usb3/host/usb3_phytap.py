#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Read the PHY boundary tap of the TAP=1 build (phy_tap.v, JTAG ER2).

The tap watches the plaintext wiring between Gowin's USB 3.0 PHY soft IP and the GTR12 quad: the DRP
(register port) accesses the IP makes, the quad's lane status, the PIPE control signals and the
transmit data written into the quad. The IP itself is not looked into.

    usb3_phytap.py status                       write pointers, trigger state, boundary clock frequencies
    usb3_phytap.py arm-log [--mask 0x108] [--start 7]   restart the event log (mask bits: see phy_tap.v),
                                                logging from when the LTSSM enters that state
    usb3_phytap.py log [--names X.csr] [-o F]   dump the event log (1024 entries, stops when full)
    usb3_phytap.py arm-win [--trig 4] [--post 895]   restart the transmit window
    usb3_phytap.py win [-o F]                   dump the transmit window (1024 x 40 bits)

--names takes a CSR file made with Gowin's converter and comments, which names each register group:
    serdes_toml_to_csr_15k.bin --comment -o /abs/names.csr /abs/src/slogic16u3/usb3_ln0/serdes_tmp.toml
"""
import argparse, json, os, re, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'slogic16u3_probe', 'host'))
import slogic_probe as sp  # noqa: E402

MAGIC = 0x5B3A
L2 = 288
OSC_HZ = 51.66e6
CLK_NAMES = ['drp', 'lane0_fabric_tx (txdata)', 'lane0_fabric_rx', 'pcs_tx_o_fabric', 'pcs_rx_o_fabric', 'cm_life']
# status bits of a type 3 entry (top.v tap_st)
ST_FIELDS = [('pd', 0, 2), ('tx_ei', 2, 1), ('tx_det', 3, 1), ('rx_term', 4, 1), ('rx_pol', 5, 1),
             ('rx_ei', 6, 1), ('physt_t', 7, 1), ('rx_st', 8, 3), ('rx_v', 11, 1), ('ltssm', 12, 5),
             ('astat', 17, 6), ('ei_o', 23, 1), ('ei_o_h', 24, 1), ('rx_lock', 25, 1), ('rxdet', 26, 1),
             ('cmu_ok', 27, 1), ('rstn', 28, 1), ('pcs_tx_rst', 29, 1), ('pcs_rx_rst', 30, 1),
             ('rx_vld', 31, 1), ('tx_vld', 32, 1), ('rx_aempty', 33, 1), ('stat', 34, 13), ('stat_h', 47, 13)]


class Args:
    sim = None
    cable = 'dap'
    serial = None
    freq = 1e6
    any_device = False


def find_off(j):
    j.ir(0x43)
    raw = j.dr(L2 + 8)
    for off in range(8):
        if (raw >> off) & 0xFFFF == MAGIC:
            return off
    raise SystemExit(f'ER2 magic not found (0x{raw & 0xFFFFFF:06x}): is the TAP=1 bitstream loaded?')


def scan(j, off, cmd=None):
    v = 0 if cmd is None else ((1 << (L2 - 1)) | (cmd << (L2 - 32)))
    for _ in range(4):   # an occasional bad scan: index writes are idempotent, so just repeat it
        raw = j.dr(L2 + off, v << off) >> off
        if raw & 0xFFFF == MAGIC:
            return raw
    raise IOError(f'ER2 magic lost (0x{raw & 0xFFFF:04x})')


def fields(r):
    return {'log_wp': (r >> 16) & 0x7FF, 'idx': (r >> 27) & 0xFFF, 'entry': (r >> 39) & ((1 << 104) - 1),
            'win_wp': (r >> 143) & 0x3FF, 'win_trig': (r >> 153) & 1, 'win_full': (r >> 154) & 1,
            'win_mode': ((r >> 155) & 3) | (((r >> 189) & 1) << 2), 'mask': (r >> 157) & 0xFFFF,
            'drop': (r >> 173) & 0xFFFF, 'gate': (r >> 190) & 1,
            'freq': [((r >> (192 + 16 * i)) & 0xFFFF) * 64 * OSC_HZ / (1 << 20) for i in range(6)]}


def read_entries(j, off, base, n):
    """entries base+0 .. base+n-1 (base 0 = log, 0x800 = window). The index register takes a moment,
    and a scan now and then comes back with a bit wrong: each entry is read until two reads agree."""
    ent = {}
    for i in range(n):
        scan(j, off, base + i)
        last = None
        for _ in range(8):
            f = fields(scan(j, off, base + i))
            if f['idx'] != base + i:
                continue
            if f['entry'] == last:
                ent[i] = last
                break
            last = f['entry']
        else:
            raise IOError(f'entry {i}: no two reads agree')
    return [ent[i] for i in range(n)]


def load_names(path):
    names = {}
    if path:
        for line in open(path):
            m = re.match(r'upar_write_driver\((0x[0-9a-fA-F]+),0x[0-9a-fA-F]+\)\s*#\s*(\S+)', line)
            if m:
                names.setdefault(int(m[1], 16), m[2])
    return names


def st_decode(v, prev=None):
    out = []
    for name, lo, w in ST_FIELDS:
        x = (v >> lo) & ((1 << w) - 1)
        if prev is None or ((prev >> lo) & ((1 << w) - 1)) != x:
            out.append(f'{name}={x:#x}' if w > 4 else f'{name}={x}')
    return ' '.join(out)


def cmd_status(j):
    off = find_off(j)
    f = fields(scan(j, off))
    print(f"log: {f['log_wp']} entries{' (full)' if f['log_wp'] >= 1024 else ''}, dropped {f['drop']}, "
          f"mask {f['mask']:#06x}, {'logging' if f['gate'] else 'waiting for the start state'}")
    print(f"window: wp {f['win_wp']}, trigger mode {f['win_mode']}, triggered {f['win_trig']}, full {f['win_full']}")
    for n, hz in zip(CLK_NAMES, f['freq']):
        print(f'  {n:26s} {hz / 1e6:8.2f} MHz')


def cmd_log(j, a):
    off = find_off(j)
    f = fields(scan(j, off))
    n = min(f['log_wp'], 1024)
    raw = read_entries(j, off, 0, 1024)[:n]
    names = load_names(a.names)
    out, prev_st, t0 = [], None, None
    for e in raw:
        typ, ts, p = e >> 100, (e >> 68) & 0xFFFFFFFF, e & ((1 << 68) - 1)
        t0 = ts if t0 is None else t0
        us = ((ts - t0) & 0xFFFFFFFF) / (f['freq'][0] or 100e6) * 1e6
        if typ == 1:
            addr, data, strb = (p >> 40) & 0xFFFFFF, (p >> 8) & 0xFFFFFFFF, p & 0xFF
            d = {'t_us': us, 'op': 'W', 'addr': addr, 'data': data, 'strb': strb}
            txt = f'W {addr:06x} = {data:08x}' + (f' strb {strb:02x}' if strb != 0xFF else '') + f'  {names.get(addr, "")}'
        elif typ == 2:
            rep, addr, data = (p >> 56) & 0xFFF, (p >> 32) & 0xFFFFFF, p & 0xFFFFFFFF
            d = {'t_us': us, 'op': 'R', 'addr': addr, 'data': data, 'rep': rep}
            txt = f'R {addr:06x} -> {data:08x}' + (f'  (+{rep} same before)' if rep else '') + f'  {names.get(addr, "")}'
        elif typ == 3:
            st = p & ((1 << 64) - 1)
            d = {'t_us': us, 'op': 'S', 'st': st}
            txt = 'S ' + st_decode(st, prev_st)
            prev_st = st
        elif typ == 4:
            d = {'t_us': us, 'op': 'A', 'mask': p & 0xFFFF, 'start': (p >> 16) & 0x3F}
            txt = f'A armed, mask {p & 0xFFFF:#06x}' + (f', start at LTSSM state {(p >> 16) & 0x1F}' if (p >> 21) & 1 else '')
        elif typ == 5:
            st = p & ((1 << 64) - 1)
            d = {'t_us': us, 'op': 'G', 'st': st}
            txt = 'G start: ' + st_decode(st)
            prev_st = st
        else:
            d = {'t_us': us, 'op': '?', 'raw': e}
            txt = f'? {e:026x}'
        out.append(d)
        print(f'{us:12.3f} us  {txt}')
    if a.out:
        json.dump({'freq': f['freq'], 'entries': out}, open(a.out, 'w'), indent=1)


def cmd_win(j, a):
    off = find_off(j)
    f = fields(scan(j, off))
    if not f['win_full']:
        raise SystemExit(f"window not complete (triggered={f['win_trig']})")
    raw = read_entries(j, off, 0x800, 1024)
    words = [raw[(f['win_wp'] + n) % 1024] for n in range(1024)]
    out = []
    for n, e in enumerate(words):
        txd, vld, ei, pd = e & ((1 << 40) - 1), (e >> 40) & 1, (e >> 41) & 1, (e >> 42) & 3
        syms = [(txd >> (10 * k)) & 0x3FF for k in range(4)]
        out.append({'txd': txd, 'vld': vld, 'tx_ei': ei, 'pd': pd})
        bits = ''.join(format(s, '010b')[::-1] for s in syms)   # first bit on the line = bit 0
        print(f'{n:5d} pd={pd} ei={ei} v={vld} ' + ' '.join(f'{s:03x}' for s in syms) + f'  {bits}')
    if a.out:
        json.dump(out, open(a.out, 'w'))


def main():
    global OSC_HZ
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('cmd', choices=['status', 'arm-log', 'log', 'arm-win', 'win'])
    ap.add_argument('--mask', type=lambda s: int(s, 0), default=0x108)
    ap.add_argument('--start', type=int, help='log only from when the LTSSM enters this state (rtl/usb3 State: '
                    '6 PollingLfps, 7 PollingRxEq, 11 U0, 14 RecoveryActive)')
    ap.add_argument('--trig', type=int, choices=range(8), default=4,
                    help='window trigger: 0 TxElecIdle falls, 1 PowerDown changes, 2 at once, 3 TxDetectRx rises, '
                    '4 / 5 TxElecIdle falls / rises in P2 (LFPS on / off), 6 TxElecIdle falls in P0, 7 PowerDown becomes P0')
    ap.add_argument('--post', type=int, default=895, help='window words after the trigger (0..1023)')
    ap.add_argument('--names', help='commented CSR file naming the registers')
    ap.add_argument('-o', '--out')
    ap.add_argument('--osc-hz', type=float, default=OSC_HZ)
    ap.add_argument('--serial')
    a = ap.parse_args()
    OSC_HZ = a.osc_hz
    Args.serial = a.serial
    j = sp.open_jtag(Args())
    if a.cmd == 'status':
        cmd_status(j)
    elif a.cmd == 'arm-log':
        st = 0 if a.start is None else (1 << 21) | ((a.start & 0x1F) << 16)
        scan(j, find_off(j), (1 << 30) | st | (a.mask & 0xFFFF))
        print(f'log re-armed, mask {a.mask:#06x}' + ('' if a.start is None else f', from LTSSM state {a.start}'))
    elif a.cmd == 'arm-win':
        scan(j, find_off(j), (1 << 29) | (a.trig << 24) | (a.post & 0x3FF))
        print(f'window re-armed, trigger {a.trig}, post {a.post}')
    elif a.cmd == 'log':
        cmd_log(j, a)
    else:
        cmd_win(j, a)


if __name__ == '__main__':
    main()
