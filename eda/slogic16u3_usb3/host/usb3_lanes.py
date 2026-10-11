#!/usr/bin/env python3
"""SLogic16U3 USB 3.0 lane probe: per-lane SerDes status over JTAG ER1 (read-only, 256 bits).

    usb3_lanes.py            one snapshot
    usb3_lanes.py -w         a line per second with the signal_detect / cdr_lock edge rates
"""
import argparse, os, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'slogic16u3_probe', 'host'))
import slogic_probe as sp  # noqa: E402

MAGIC = 0x5B30
BITS = ['sd', 'cdr', 'klock', 'align', 'pll', 'ready']


class Args:
    sim = None
    cable = 'dap'
    serial = None
    freq = 1e6
    any_device = False


def read(j):
    j.ir(0x42)
    raw = j.dr(256 + 8)
    for off in range(8):
        v = raw >> off
        if v & 0xFFFF == MAGIC:
            break
    else:
        raise SystemExit(f'magic not found (0x{raw & 0xFFFFFF:06x}): is the usb3 lane probe loaded?')
    lanes = []
    for n in range(4):
        f = (v >> (16 + 48 * n)) & ((1 << 48) - 1)
        lanes.append({'now': f & 0x3F, 'seen': (f >> 6) & 0x3F, 'sd_n': (f >> 16) & 0xFFFF, 'cdr_n': (f >> 32) & 0xFFFF})
    return {'lanes': lanes, 'up': (v >> 224) & 0xFFFFFFFF}


def flags(x):
    return ' '.join(b if x >> i & 1 else '-' * len(b) for i, b in enumerate(BITS))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-w', '--watch', action='store_true')
    ap.add_argument('-i', '--interval', type=float, default=1.0)
    a = ap.parse_args()
    j = sp.open_jtag(Args())
    prev = None
    try:
        while True:
            s = read(j)
            if not a.watch:
                for n, l in enumerate(s['lanes']):
                    print(f"ln{n}: now [{flags(l['now'])}] seen [{flags(l['seen'])}] sd_edges={l['sd_n']} cdr_edges={l['cdr_n']}")
                break
            if prev:
                d = [((l['sd_n'] - p['sd_n']) & 0xFFFF, (l['cdr_n'] - p['cdr_n']) & 0xFFFF) for l, p in zip(s['lanes'], prev['lanes'])]
                print(time.strftime('%H:%M:%S'), '  '.join(
                    f"ln{n} sd+{d[n][0]:5d} cdr+{d[n][1]:5d} [{flags(l['now'])}]" for n, l in enumerate(s['lanes'])), flush=True)
            prev = s
            time.sleep(a.interval)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
