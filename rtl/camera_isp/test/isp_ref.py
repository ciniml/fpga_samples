#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Bit-exact model of IspDisplay (demosaic, black, gains, gamma) against
the frames tb_isp.sv captured once the genlock was locked.

    python3 isp_ref.py OUT_DIR W H BLACK GR GG GB CFA
"""
import sys


def srgb(v):
    return 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055


GAMMA = [min(255, max(0, round(255 * srgb(i / 1023)))) for i in range(1024)]


def process(raw, W, H, black, gains, cfa):
    out = []
    for y in range(H):
        ym1 = 1 if y == 0 else y - 1
        yp1 = H - 2 if y >= H - 1 else y + 1
        rows = (raw[ym1], raw[y], raw[yp1])
        for x in range(W):
            xl = x + 1 if x == 0 else x - 1
            xr = x - 1 if x >= W - 1 else x + 1
            c = rows[1][x]
            n, s = rows[0][x], rows[2][x]
            w, e = rows[1][xl], rows[1][xr]
            crs = (n + s + w + e) >> 2
            diag = (rows[0][xl] + rows[0][xr] + rows[2][xl] + rows[2][xr]) >> 2
            hor = (w + e) >> 1
            ver = (n + s) >> 1
            px, py = (x & 1) ^ (cfa & 1), (y & 1) ^ (cfa >> 1 & 1)
            if (py, px) == (0, 0):
                rgb = (c, crs, diag)
            elif (py, px) == (0, 1):
                rgb = (hor, c, ver)
            elif (py, px) == (1, 0):
                rgb = (ver, c, hor)
            else:
                rgb = (diag, crs, c)
            o = 0
            for v, g in zip(rgb, gains):
                v = v - black if v > black else 0
                p = v * g
                v = 1023 if p >> 18 else (p >> 8) & 1023
                o = (o << 8) | GAMMA[v]
            out.append(o)
    return out


def main():
    d, W, H, black, gr, gg, gb, cfa = sys.argv[1], *map(lambda s: int(s, 0), sys.argv[2:])
    vals = [int(l) for l in open(f'{d}/raw.txt')]
    n = W * H
    frames = [vals[i:i + n] for i in range(0, len(vals) - n + 1, n)]
    blocks = {}
    cur = None
    for l in open(f'{d}/frames.txt'):
        l = l.strip()
        if l.startswith('F'):
            cur = []
            blocks.setdefault(int(l.split()[1]), []).append(cur)
        elif cur is not None:
            cur.append(int(l, 16))
    checked = bad = 0
    for f, lst in sorted(blocks.items()):
        for got in lst:
            if len(got) != n or f < 0 or f >= len(frames):
                continue          # cut short at the end of the run / not dumped yet
            raw = [frames[f][y * W:(y + 1) * W] for y in range(H)]
            exp = process(raw, W, H, black, (gr, gg, gb), cfa)
            diff = [i for i in range(n) if exp[i] != got[i]]
            checked += 1
            if diff:
                bad += 1
                i = diff[0]
                print(f'frame {f}: {len(diff)} pixels differ, first ({i % W},{i // W}) got {got[i]:06x} exp {exp[i]:06x}')
    print(f'{checked} frames checked, {bad} bad')
    sys.exit(0 if checked >= 5 and bad == 0 else 1)


if __name__ == '__main__':
    main()
