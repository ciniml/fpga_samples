#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Checks out/gb_scale.hex of tb_gb_scale against IspGbScale's integer model.

    python3 gb_scale_ref.py out/gb_scale.hex
"""
import sys


def srgb(v):
    return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


GAMMA = [min(255, max(0, round(255 * srgb(i / 1023)))) for i in range(1024)]


def pix(x, y):
    return ((x * 7 + y * 13) ^ (x * y)) & 0x3FF


def frame(black, gain, mirror, flip, x0=256, y0=24):
    out = [0] * (128 * 112)
    for by in range(112):
        for bx in range(128):
            s = sum(pix(x0 + bx * 6 + i, y0 + by * 6 + j) for j in range(6) for i in range(6))
            avg = (s * 1821) >> 16
            net = max(0, avg - black)
            lin = min(1023, (net * gain) >> 8)
            x = 127 - bx if mirror else bx
            y = 111 - by if flip else by
            out[y * 128 + x] = GAMMA[lin]
    return out


def main():
    got = [int(l, 16) for l in open(sys.argv[1]) if l.strip()]
    bad = 0
    for i, want in enumerate([frame(16, 0x100, 0, 0), frame(0, 0x180, 1, 1)]):
        g = got[i * 14336:(i + 1) * 14336]
        diff = [a for a in range(14336) if g[a] != want[a]]
        print(f'frame {i}: {"OK" if not diff else f"{len(diff)} differ, first at {diff[0]} ({g[diff[0]]} vs {want[diff[0]]})"}')
        bad += len(diff)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
