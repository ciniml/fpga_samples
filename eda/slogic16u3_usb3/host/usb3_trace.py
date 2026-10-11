#!/usr/bin/env python3
"""Dump the U0 packet trace of the SLogic16U3 USB 3.0 device (top.v, JTAG ER2).

1024 pclk words of the PIPE receive and transmit streams around the first data packet header
received in U0. The data symbols are scrambled; the scrambler state of each direction is recovered
from the first run of logical idle (scrambled zeros) and the streams are descrambled from there.

    usb3_trace.py [-o trace.json] [--raw]
"""
import argparse, json, os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'slogic16u3_probe', 'host'))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'rtl', 'usb3', 'test'))
import slogic_probe as sp  # noqa: E402
from usb3_ref import lfsr_adv8  # noqa: E402

MAGIC = 0x5B33
K_NAMES = {0x3C: 'SKP', 0x5C: 'SDP', 0x7C: 'EDB', 0x9C: 'SUB', 0xBC: 'COM', 0xFB: 'SHP', 0xFD: 'END',
           0xFE: 'SLC', 0xF7: 'EPF'}


class Args:
    sim = None
    cable = 'dap'
    serial = None
    freq = 1e6
    any_device = False


L2 = 192


def scan(j, off, idx=None):
    v = 0 if idx is None else ((1 << (L2 - 1)) | (idx << (L2 - 32)))
    raw = j.dr(L2 + off, v << off) >> off
    if raw & 0xFFFF != MAGIC:
        raise IOError(f'ER2 magic lost (0x{raw & 0xFFFF:04x})')
    return raw


def find_off(j):
    j.ir(0x43)
    raw = j.dr(L2 + 8)
    for off in range(8):
        if (raw >> off) & 0xFFFF == MAGIC:
            return off
    raise SystemExit(f'ER2 magic not found (0x{raw & 0xFFFFFF:06x}): is the usb3 bitstream (trace) loaded?')


def read_trace(j):
    off = find_off(j)
    r = scan(j, off)
    if not (r >> 17) & 1:
        raise SystemExit(f'trace not complete (triggered={(r >> 16) & 1})')
    wp = (r >> 18) & 0x3FF
    ent = {}
    scan(j, off, 0)
    for i in range(1024):
        r = scan(j, off, (i + 1) % 1024)
        idx = (r >> 28) & 0x7FF
        ent[idx] = (r >> 39) & ((1 << 76) - 1)
    missing = [i for i in range(1024) if i not in ent]
    if missing:   # the index register takes a moment: re-read those one at a time
        for i in missing:
            scan(j, off, i)
            for _ in range(3):
                r = scan(j, off, i)
                if (r >> 28) & 0x7FF == i:
                    ent[i] = (r >> 39) & ((1 << 76) - 1)
                    break
    words = []
    for n in range(1024):
        e = ent[(wp + n) % 1024]
        words.append({'tx_d': e & 0xFFFFFFFF, 'tx_k': (e >> 32) & 0xF, 'rx_d': (e >> 36) & 0xFFFFFFFF,
                      'rx_k': (e >> 68) & 0xF, 'rx_v': (e >> 72) & 1, 'rx_st': (e >> 73) & 7})
    return words


def read_hlog(j):
    """Header log: [(dir, timestamp, header96)] in order."""
    off = find_off(j)
    r = scan(j, off)
    wp = (r >> 160) & 0xFF
    wrapped = (r >> 170) & 1
    n = 128 if wrapped else min(wp, 128)
    first = (wp & 0x7F) if wrapped else 0       # ring mode: the oldest entry is at the pointer
    out = []
    scan(j, off, 1024 + first)
    for k in range(n):
        i = (first + k) % 128
        for _ in range(4):
            r = scan(j, off, 1024 + ((i + 1) % 128))
            if (r >> 28) & 0x7FF == 1024 + i:
                break
            scan(j, off, 1024 + i)
        e = (r >> 39) & ((1 << 121) - 1)
        out.append(((e >> 120) & 1, (e >> 96) & 0xFFFFFF, e & ((1 << 96) - 1)))
    return out


TP_SUB = {1: 'ACK', 2: 'NRDY', 3: 'ERDY', 4: 'STATUS', 5: 'STALL', 6: 'DEV_NOTIFY', 7: 'PING', 8: 'PING_RSP'}
LMP_SUB = {1: 'SetLinkFunction', 2: 'U2InactivityTimeout', 3: 'VendorTest', 4: 'PortCapability', 5: 'PortConfiguration',
           6: 'PortConfigResponse'}


def decode_hdr(h):
    dw0, dw1, dw2 = h & 0xFFFFFFFF, (h >> 32) & 0xFFFFFFFF, (h >> 64) & 0xFFFFFFFF
    typ = dw0 & 0x1F
    addr = dw0 >> 25
    route = (dw0 >> 5) & 0xFFFFF
    if typ == 0x00:
        sub = (dw0 >> 5) & 0xF
        return f'LMP {LMP_SUB.get(sub, sub)} dw0={dw0:08x} dw1={dw1:08x} dw2={dw2:08x}'
    if typ == 0x04:
        sub = dw1 & 0xF
        return (f'TP  {TP_SUB.get(sub, sub):8s} addr={addr} route={route:x} ept={(dw1 >> 8) & 0xF} dir={(dw1 >> 7) & 1} '
                f'rty={(dw1 >> 6) & 1} nump={(dw1 >> 16) & 0x1F} seq={(dw1 >> 21) & 0x1F} dw2={dw2:08x}')
    if typ == 0x08:
        return (f'DP  addr={addr} route={route:x} seq={dw1 & 0x1F} eob={(dw1 >> 6) & 1} dir={(dw1 >> 7) & 1} '
                f'ept={(dw1 >> 8) & 0xF} setup={(dw1 >> 15) & 1} len={dw1 >> 16} dw2={dw2:08x}')
    if typ == 0x1F:     # Usb3Device EP1 IN state (ring mode, top.v)
        st = dw2 << 32 | dw1
        return (f'    state seq_in={st & 0x1F} limit={(st >> 5) & 0x1F} nsent={(st >> 10) & 0x1F} ack={(st >> 15) & 0xF} '
                f'ready={(st >> 19) & 0xFFFF:016b} cfg={(st >> 35) & 1} stop={(st >> 36) & 1} flow={(st >> 37) & 1}')
    if typ == 0x0C:
        return f'ITP {dw0:08x}'
    return f'type {typ:02x} {dw0:08x} {dw1:08x} {dw2:08x}'


def symbols(words, d, k, valid=None):
    out = []
    for w in words:
        if valid and not w[valid]:
            continue
        for b in range(4):
            out.append(((w[d] >> 8 * b) & 0xFF, (w[k] >> b) & 1))
    return out


def mask_of(l):
    return sum(((l >> (15 - i)) & 1) << i for i in range(8))


def recover(syms, need=12):
    """Find the scrambler state at the start of the first run of `need` data symbols that are
    scrambled zeros; returns (index, lfsr) or None."""
    run = 0
    for i, (v, k) in enumerate(syms):
        run = run + 1 if not k else 0
        if run == need:
            s0 = i - need + 1
            target = [syms[s0 + t][0] for t in range(need)]
            for l in range(1, 1 << 16):
                x, ok = l, True
                for t in range(need):
                    if mask_of(x) != target[t]:
                        ok = False
                        break
                    x = lfsr_adv8(x)
                if ok:
                    return s0, l
            run = 0
    return None


def descramble(syms):
    r = recover(syms)
    out = []
    if r is None:
        return [(v, k, None) for v, k in syms]
    s0, l = r
    for i, (v, k) in enumerate(syms):
        if i < s0:
            out.append((v, k, None))
            continue
        if k and v == 0x3C:
            out.append((v, k, v))
            continue
        if k and v == 0xBC:
            l = 0xFFFF
            out.append((v, k, v))
            continue
        out.append((v, k, v ^ mask_of(l) if not k else v))
        l = lfsr_adv8(l)
    return out


def fmt_stream(ds):
    """Group descrambled symbols into lines at K-symbol framing boundaries; idle zeros collapsed."""
    lines, cur, idle = [], [], 0
    for v, k, d in ds:
        if k:
            if idle:
                cur.append(f'.{idle}'); idle = 0
            name = K_NAMES.get(v, f'K{v:02x}')
            if name in ('SHP', 'SDP', 'SLC', 'COM') and cur and not cur[-1] in ('SHP', 'SDP', 'SLC', 'COM'):
                lines.append(' '.join(cur)); cur = []
            cur.append(name)
        else:
            if d == 0:
                idle += 1
                continue
            if idle:
                cur.append(f'.{idle}'); idle = 0
            cur.append('??' if d is None else f'{d:02x}')
    if idle:
        cur.append(f'.{idle}')
    if cur:
        lines.append(' '.join(cur))
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-o', '--out')
    ap.add_argument('-i', '--input', help='decode a saved trace instead of reading the board')
    ap.add_argument('--raw', action='store_true')
    ap.add_argument('--hdr', action='store_true', help='header packet log instead of the word trace')
    ap.add_argument('--arm', type=int, choices=[0, 1, 2, 3], help='re-arm the trace (and the header log) with trigger mode '
                    '0 = after the first SETUP, 1 = U0 -> Recovery, 2 = bad DPP, 3 = Usb3Device debug event (header log as a ring, stops 64 after), then exit')
    a = ap.parse_args()
    if a.arm is not None:
        j = sp.open_jtag(Args())
        off = find_off(j)
        v = (1 << (L2 - 1)) | (((1 << 30) | (a.arm << 28)) << (L2 - 32))
        j.dr(L2 + off, v << off)
        print(f'trace re-armed, mode {a.arm}')
        return
    if a.hdr:
        log = read_hlog(sp.open_jtag(Args()))
        t0 = log[0][1] if log else 0
        for d, ts, h in log:
            print(f"{((ts - t0) & 0xFFFFFF) / 125:10.2f} us  {'TX' if d else 'RX'}  {decode_hdr(h)}")
        return
    if a.input:
        words = json.load(open(a.input))
    else:
        words = read_trace(sp.open_jtag(Args()))
        if a.out:
            json.dump(words, open(a.out, 'w'))
    if a.raw:
        for n, w in enumerate(words):
            rx = ' '.join(('K' if w['rx_k'] >> b & 1 else ' ') + f"{(w['rx_d'] >> 8 * b) & 0xFF:02x}" for b in range(4))
            tx = ' '.join(('K' if w['tx_k'] >> b & 1 else ' ') + f"{(w['tx_d'] >> 8 * b) & 0xFF:02x}" for b in range(4))
            print(f"{n:5d} rx[v={w['rx_v']} st={w['rx_st']}] {rx}   tx {tx}")
        return
    for name, d, k, v in (('RX', 'rx_d', 'rx_k', 'rx_v'), ('TX', 'tx_d', 'tx_k', None)):
        print(f'==== {name}')
        for line in fmt_stream(descramble(symbols(words, d, k, v))):
            print('  ' + line)


if __name__ == '__main__':
    main()
