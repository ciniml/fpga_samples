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


def frame(black, gain, mirror, flip, x0=256, y0=24, cfa=3):
    out = [0] * 16384
    for by in range(112):
        for bx in range(128):
            s = sum(pix(x0 + bx * 6 + i, y0 + by * 6 + j) for j in range(6) for i in range(6))
            avg = (s * 1821) >> 16
            net = max(0, avg - black)
            lin = min(1023, (net * gain) >> 8)
            x = 127 - bx if mirror else bx
            y = 111 - by if flip else by
            out[y * 128 + x] = GAMMA[lin]
    # colour planes: R, G, B averages of every 48x48 tile (base RGGB, cfa bits flip x / y parity)
    for ty in range(14):
        for tx in range(16):
            s = [0, 0, 0]
            for j in range(48):
                yy = y0 + ty * 48 + j
                for i in range(48):
                    xx = x0 + tx * 48 + i
                    px, py = (xx & 1) ^ (cfa & 1), (yy & 1) ^ (cfa >> 1)
                    s[1 if px != py else (0 if px == 0 else 2)] += pix(xx, yy)
            x = 15 - tx if mirror else tx
            y = 13 - ty if flip else ty
            for c in range(3):
                a10 = (s[c] * 1821) >> (21 if c == 1 else 20)
                net = max(0, a10 - black)
                out[0x3800 + c * 0x100 + y * 16 + x] = 255 if net >= 1024 else net >> 2
    return out


def main():
    got = [int(l, 16) for l in open(sys.argv[1]) if l.strip()]
    bad = 0
    for i, want in enumerate([frame(16, 0x100, 0, 0), frame(0, 0x180, 1, 1)]):
        g = got[i * 16384:(i + 1) * 16384]
        diff = [a for a in range(16384) if g[a] != want[a]]
        print(f'frame {i}: {"OK" if not diff else f"{len(diff)} differ, first at {diff[0]} ({g[diff[0]]} vs {want[diff[0]]})"}')
        bad += len(diff)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
