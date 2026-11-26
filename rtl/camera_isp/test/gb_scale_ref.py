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
# the colour curve: (knot, value, slope numerator, log2 width) of the 8 segments
SEG = [(0, 0, 22, 3), (8, 22, 12, 3), (16, 34, 15, 4), (32, 49, 22, 5), (64, 71, 28, 6),
       (128, 99, 38, 7), (256, 137, 51, 8), (512, 188, 67, 9)]


def pwl(x):
    k = max(i for i in range(8) if SEG[i][0] <= x)
    x0, y0, dy, sh = SEG[k]
    return y0 + (((x - x0) * dy) >> sh)


def pix(x, y):
    return ((x * 7 + y * 13) ^ (x * y)) & 0x3FF


def clamp10(m):
    return 0x3FF if m >> 18 else (m >> 8) & 0x3FF


def frame(black, gain, mirror, flip, wr, wb, x0=256, y0=24, cfa=3):
    """-> (luma, colour, (sum R, sum G, sum B) after the black level)"""
    luma = [0] * (128 * 112)
    col = [0] * (128 * 112)
    sums = [0, 0, 0]
    ewr = ((wr * gain) >> 8) & 0xFFFF
    ewb = ((wb * gain) >> 8) & 0xFFFF
    for by in range(112):
        for bx in range(128):
            s = [0, 0, 0]
            for j in range(6):
                yy = y0 + by * 6 + j
                for i in range(6):
                    xx = x0 + bx * 6 + i
                    px, py = (xx & 1) ^ (cfa & 1), (yy & 1) ^ (cfa >> 1)
                    s[1 if px != py else (0 if px == 0 else 2)] += pix(xx, yy)
            x = 127 - bx if mirror else bx
            y = 111 - by if flip else by
            avg = ((s[0] + s[1] + s[2]) * 1821) >> 16
            luma[y * 128 + x] = pwl(clamp10(max(0, avg - black) * gain))
            a = [(s[0] * 7282) >> 16, (s[1] * 3641) >> 16, (s[2] * 7282) >> 16]
            n = [max(0, v - black) for v in a]
            for c in range(3):
                sums[c] += n[c]
            d = [clamp10(n[0] * ewr), clamp10(n[1] * gain), clamp10(n[2] * ewb)]
            h = [pwl(v) for v in d]
            col[y * 128 + x] = (h[0] >> 3) << 11 | (h[1] >> 2) << 5 | (h[2] >> 3)
    return luma, col, sums


def grey_world(sums):
    def g(n, d):
        q = (n << 8) // d
        return 1024 if q > 1024 else 128 if q < 128 else q
    return g(sums[1], sums[0]), g(sums[1], sums[2])


def main():
    got = [int(l, 16) for l in open(sys.argv[1]) if l.strip()]
    l0, c0, s0 = frame(16, 0x100, 0, 0, 0x100, 0x100)
    wr, wb = grey_world(s0)
    l1, c1, _ = frame(0, 0x180, 1, 1, wr, wb)
    print(f'white balance from frame 0: R {wr:#06x} B {wb:#06x}')
    bad = 0
    n = 128 * 112
    for i, (lw, cw) in enumerate([(l0, c0), (l1, c1)]):
        g = got[i * 2 * n:(i + 1) * 2 * n]
        dl = [a for a in range(n) if g[a] != lw[a]]
        dc = [a for a in range(n) if g[n + a] != cw[a]]
        msg = 'OK' if not dl and not dc else ''
        if dl:
            msg += f'luma {len(dl)} differ, first at {dl[0]} ({g[dl[0]]} vs {lw[dl[0]]}) '
        if dc:
            msg += f'colour {len(dc)} differ, first at {dc[0]} ({g[n + dc[0]]:04x} vs {cw[dc[0]]:04x})'
        print(f'frame {i}: {msg}')
        bad += len(dl) + len(dc)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
