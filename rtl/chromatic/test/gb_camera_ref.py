#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Reference model of GbCamera (gb_camera.veryl) for tb_gb_camera.

    python3 gb_camera_ref.py gen   cam_in.hex      # test cases: frame + registers
    python3 gb_camera_ref.py check cam_in.hex cam_out.hex

The integer pipeline of the RTL, which follows SameBoy's Core/camera.c:
gain 8.8 table, (v * gain * exposure) >> 20, edge term trunc(|4c - sum| * r / 4) with r in
quarters, thresholds ((x & 3) + (y & 3) * 4) * 3 + 6, colour 3 (darkest) .. 0.
"""
import random
import sys

W, H = 128, 112
NREG = 64  # registers per case in the file (54 used)
GAIN = [226, 234, 242, 249, 256, 262, 268, 273, 278, 288, 296, 304, 311, 317, 326, 337,
        346, 355, 362, 370, 376, 382, 388, 393, 398, 403, 407, 412, 416, 419, 423, 427]
RATIO_Q = [2, 3, 4, 5, 8, 12, 16, 20]


def shot(fb, regs):
    gq = GAIN[regs[1] & 0x1F]
    expo = (regs[2] << 8) | regs[3]
    edge = (regs[1] & 0xE0) == 0xE0
    rq = RATIO_Q[(regs[4] >> 4) & 7]
    inv = (regs[4] >> 3) & 1

    def p(x, y):
        x = min(max(x, 0), W - 1)
        y = min(max(y, 0), H - 1)
        v = fb[y * W + x]
        if inv:
            v = 255 - v
        return (v * gq * expo) >> 20

    img = bytearray(0xE00)
    for ty in range(14):
        for tx in range(16):
            for r in range(8):
                lo = hi = 0
                for xi in range(8):
                    x, y = tx * 8 + xi, ty * 8 + r
                    c = p(x, y)
                    if edge:
                        d = 4 * c - p(x - 1, y) - p(x + 1, y) - p(x, y - 1) - p(x, y + 1)
                        q = (abs(d) * rq) >> 2
                        c = c - q if d < 0 else c + q
                    b = ((x & 3) + (y & 3) * 4) * 3 + 6
                    if c < regs[b]:
                        col = 3
                    elif c < regs[b + 1]:
                        col = 2
                    elif c < regs[b + 2]:
                        col = 1
                    else:
                        col = 0
                    lo = (lo << 1) | (col & 1)
                    hi = (hi << 1) | (col >> 1)
                a = (ty * 16 + tx) * 16 + r * 2
                img[a] = lo
                img[a + 1] = hi
    return img


def thresholds(lo, hi):
    """A Bayer 4x4 dither matrix between lo and hi (the way the Game Boy Camera spreads them)."""
    bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    out = []
    for i in range(16):
        f = (bayer[i] + 0.5) / 16
        for lev in range(3):
            a = lo + (hi - lo) * lev / 3
            b = lo + (hi - lo) * (lev + 1) / 3
            out.append(min(255, int(a + (b - a) * f)))
    return out


def cases():
    rnd = random.Random(1)
    grad = [((x * 2 + y) & 0xFF) for y in range(H) for x in range(W)]
    noise = [rnd.randrange(256) for _ in range(W * H)]
    blobs = [min(255, (x - 64) ** 2 // 16 + (y - 56) ** 2 // 12) for y in range(H) for x in range(W)]
    out = []
    # (frame, gain/edge 0x01, exposure, 0x04)
    for fb, r1, expo, r4, th in [
        (grad, 0x04, 0x1000, 0x00, (40, 200)),
        (noise, 0x00, 0x0800, 0x08, (20, 160)),
        (blobs, 0xE4, 0x1000, 0x20, (40, 200)),
        (noise, 0xFF, 0xFFFF, 0x78, (0, 255)),
        (grad, 0xE0, 0x0300, 0x48, (10, 90)),
        (noise, 0x1F, 0x2345, 0x50, (60, 250)),
    ]:
        regs = [0] * NREG
        regs[1], regs[2], regs[3], regs[4] = r1, expo >> 8, expo & 0xFF, r4
        regs[6:54] = thresholds(*th)
        out.append((fb, regs))
    return out


def main():
    cmd = sys.argv[1]
    if cmd == 'gen':
        with open(sys.argv[2], 'w') as f:
            for fb, regs in cases():
                for v in fb:
                    f.write(f'{v:02x}\n')
                for v in regs:
                    f.write(f'{v:02x}\n')
        return
    got = [int(l, 16) for l in open(sys.argv[3]) if l.strip()]
    bad = 0
    for i, (fb, regs) in enumerate(cases()):
        want = shot(fb, regs)
        g = got[i * 0xE00:(i + 1) * 0xE00]
        diff = [a for a in range(0xE00) if a >= len(g) or g[a] != want[a]]
        print(f'case {i}: {"OK" if not diff else f"{len(diff)} bytes differ, first at {diff[0]:#05x}"}')
        bad += len(diff)
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
