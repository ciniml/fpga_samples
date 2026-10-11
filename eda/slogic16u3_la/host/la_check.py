#!/usr/bin/env python3
"""Check a real-input capture (la_stream -o PREFIX, 8 channels per group) of the Tang Primer 25K pattern
source (eda/la_pattern_gen): group A = an 8-bit counter, group B = the same counter in Gray code.

    la_check.py PREFIX [--rate MS/s] [--pattern MHz] [--ext]

Internal clock (--rate, --pattern): every change of the value must be +1 and each value must last
about rate / pattern samples. Edge clock (--ext, sampled on the pattern clock): every sample must be
the previous one + 1.
"""
import argparse, os
import numpy as np


def gray_decode(g):
    b = g.copy()
    s = g >> 1
    while s.any():
        b ^= s
        s >>= 1
    return b


def check(name, v, a):
    if len(v) < 2:
        print(f'{name}: {len(v)} samples')
        return
    v = v.astype(np.int64)
    if a.ext:
        d = (v[1:] - v[:-1]) & 0xFF
        bad = np.count_nonzero(d != 1)
        print(f'{name}: {len(v)} samples on the clock, steps != +1: {bad}'
              + (f' (first at {np.argmax(d != 1)}: {v[np.argmax(d != 1)]:02x} -> {v[np.argmax(d != 1) + 1]:02x})' if bad else ''))
        return
    ch = np.flatnonzero(v[1:] != v[:-1]) + 1          # indices where the value changes
    steps = (v[ch] - v[ch - 1]) & 0xFF
    bad = np.count_nonzero(steps != 1)
    runs = np.diff(ch)
    exp = a.rate / a.pattern
    hist = {int(k): int(n) for k, n in zip(*np.unique(runs, return_counts=True))}
    print(f'{name}: {len(v)} samples, {len(ch)} changes, steps != +1: {bad}'
          + (f' (first at sample {ch[np.argmax(steps != 1)]}: {v[ch[np.argmax(steps != 1)] - 1]:02x} -> {v[ch[np.argmax(steps != 1)]]:02x})' if bad else ''))
    print(f'    run lengths (expected {exp:g}): {dict(list(hist.items())[:12])}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('prefix')
    ap.add_argument('--rate', type=float, default=100.0, help='sample rate in MS/s (internal clock)')
    ap.add_argument('--pattern', type=float, default=25.0, help='pattern rate in MHz')
    ap.add_argument('--ext', action='store_true', help='sampled on the pattern clock')
    ap.add_argument('--max', type=int, default=200_000_000, help='samples to look at')
    a = ap.parse_args()
    for g, name in ((0, 'A (counter)'), (1, 'B (Gray)')):
        fn = f'{a.prefix}_{"ab"[g]}.bin'
        if not os.path.exists(fn):
            continue
        v = np.fromfile(fn, dtype=np.uint8, count=a.max)[:-8]   # (the last word may be padding)
        if g == 1:
            v = gray_decode(v)
        check(name, v, a)


if __name__ == '__main__':
    main()
