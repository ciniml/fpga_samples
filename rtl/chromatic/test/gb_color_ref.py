#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Reference model of GbColorQuant (gb_color_quant.veryl): a 128x112 RGB565 frame -> GBC tiles with
4 palettes x 4 colours for every tile row.

    python3 gb_color_ref.py gen  col_in.hex IMAGE...      # test frames (RGB565, one per line)
    python3 gb_color_ref.py check col_in.hex col_out.hex  # RAM bank 0 0x0100-0x11BF per frame
    python3 gb_color_ref.py show  out.png IMAGE...        # original next to the GBC picture

For every tile row (16 tiles):
  1. tile means (8-bit channels from RGB565 as r5 << 3 | r5 >> 2 ...), and the luma range of each
     tile, luma = (r + 2 g + b) >> 2
  2. 4 groups by k-means on the tile means (L1 distance; first centre the tile of the highest mean
     luma, then each the tile farthest from the centres so far; 3 updates; ties to the lowest index),
     groups renumbered by the centre's r + 2 g + b, darkest first (stable)
  3. for every pixel: i = min(3, ((Y - ymin) * (12288 // max(1, ymax - ymin)) + bayer * 256 + 128) >> 12)
     with the group's luma range; colour i of the group's palette = the mean of its pixels with that
     i, or grey ymin + (ymax - ymin) * i // 3 when none (an empty group is black)
RAM bank 0 (offsets): 0x0100 + tile * 16 + row * 2 the tiles (colour index i: plane 0 = bit 0),
0x0F00 + tile the BG attribute (0x08 | (ty & 1) << 2 | group), 0x1000 + ty * 32 + group * 8 + i * 2
the palettes (RGB555, little endian).
"""
import sys

W, H = 128, 112
BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
RAM_LO, RAM_HI = 0x0100, 0x11C0


def rgb8(v):
    r5, g6, b5 = v >> 11, (v >> 5) & 0x3F, v & 0x1F
    return ((r5 << 3) | (r5 >> 2), (g6 << 2) | (g6 >> 4), (b5 << 3) | (b5 >> 2))


def l1(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def quant(fb):
    ram = bytearray(0x2000)
    pix = [rgb8(v) for v in fb]
    for ty in range(14):
        tiles = [[pix[(ty * 8 + y) * W + tx * 8 + x] for y in range(8) for x in range(8)] for tx in range(16)]
        tm, tmin, tmax = [], [], []
        for t in tiles:
            tm.append([sum(p[c] for p in t) >> 6 for c in range(3)])
            ys = [(p[0] + 2 * p[1] + p[2]) >> 2 for p in t]
            tmin.append(min(ys))
            tmax.append(max(ys))
        luma = [(m[0] + 2 * m[1] + m[2]) >> 2 for m in tm]
        cen = [tm[max(range(16), key=lambda i: luma[i])][:]]
        while len(cen) < 4:
            cen.append(tm[max(range(16), key=lambda i: min(l1(tm[i], c) for c in cen))][:])
        for _ in range(3):
            grp = [min(range(4), key=lambda k: l1(tm[i], cen[k])) for i in range(16)]
            for k in range(4):
                mem = [tm[i] for i in range(16) if grp[i] == k]
                if mem:
                    cen[k] = [sum(m[c] for m in mem) // len(mem) for c in range(3)]
        grp = [min(range(4), key=lambda k: l1(tm[i], cen[k])) for i in range(16)]
        order = sorted(range(4), key=lambda k: cen[k][0] + 2 * cen[k][1] + cen[k][2])
        rank = [0] * 4
        for j, k in enumerate(order):
            rank[k] = j
        grp = [rank[g] for g in grp]
        ymin, ymax = [], []
        for g in range(4):
            mem = [i for i in range(16) if grp[i] == g]
            ymin.append(min(tmin[i] for i in mem) if mem else 0)
            ymax.append(max(tmax[i] for i in mem) if mem else 0)
        scale = [12288 // max(1, ymax[g] - ymin[g]) for g in range(4)]
        acc = [[[0, 0, 0, 0] for _ in range(4)] for _ in range(4)]
        for tx in range(16):
            g = grp[tx]
            t = ty * 16 + tx
            for y in range(8):
                lo = hi = 0
                for x in range(8):
                    p = tiles[tx][y * 8 + x]
                    Y = (p[0] + 2 * p[1] + p[2]) >> 2
                    i = min(3, ((Y - ymin[g]) * scale[g] + BAYER[(y & 3) * 4 + (x & 3)] * 256 + 128) >> 12)
                    a = acc[g][i]
                    a[0] += p[0]
                    a[1] += p[1]
                    a[2] += p[2]
                    a[3] += 1
                    lo = (lo << 1) | (i & 1)
                    hi = (hi << 1) | (i >> 1)
                ram[0x100 + t * 16 + y * 2] = lo
                ram[0x100 + t * 16 + y * 2 + 1] = hi
            ram[0xF00 + t] = 0x08 | (ty & 1) << 2 | g
        for g in range(4):
            for i in range(4):
                a = acc[g][i]
                if a[3]:
                    c = [a[0] // a[3], a[1] // a[3], a[2] // a[3]]
                else:
                    lv = ymin[g] + (ymax[g] - ymin[g]) * i // 3
                    c = [lv, lv, lv]
                v = (c[0] >> 3) | (c[1] >> 3) << 5 | (c[2] >> 3) << 10
                o = 0x1000 + ty * 32 + g * 8 + i * 2
                ram[o] = v & 0xFF
                ram[o + 1] = v >> 8
    return ram


def render(ram):
    from PIL import Image
    out = Image.new('RGB', (W, H))
    for t in range(224):
        ty, tx = divmod(t, 16)
        g = ram[0xF00 + t] & 3
        for y in range(8):
            lo, hi = ram[0x100 + t * 16 + y * 2], ram[0x100 + t * 16 + y * 2 + 1]
            for x in range(8):
                i = ((lo >> (7 - x)) & 1) | ((hi >> (7 - x)) & 1) << 1
                o = 0x1000 + ty * 32 + g * 8 + i * 2
                v = ram[o] | ram[o + 1] << 8
                c = [(v >> s) & 0x1F for s in (0, 5, 10)]
                out.putpixel((tx * 8 + x, ty * 8 + y), tuple((k << 3) | (k >> 2) for k in c))
    return out


def load(path):
    from PIL import Image
    im = Image.open(path).convert('RGB')
    w, h = im.size
    cw = min(w, h * 8 // 7)
    ch = cw * 7 // 8
    im = im.crop(((w - cw) // 2, (h - ch) // 2, (w + cw) // 2, (h + ch) // 2)).resize((W, H), Image.LANCZOS)
    return im, [(r >> 3) << 11 | (g >> 2) << 5 | (b >> 3) for r, g, b in im.getdata()]


def synthetic():
    """Frames without image files: ramps, flat areas (empty groups, empty bins), noise."""
    import random
    rnd = random.Random(7)
    f1 = [((x >> 2) << 11) | ((y >> 1) << 5) | ((x + y) >> 3 & 0x1F) for y in range(H) for x in range(W)]
    f2 = [0x7BEF if (x // 8 + y // 8) & 1 else 0x7BEF for y in range(H) for x in range(W)]
    f3 = [rnd.randrange(65536) for _ in range(W * H)]
    return [f1, f2, f3]


def main():
    cmd = sys.argv[1]
    if cmd == 'gen':
        frames = synthetic() + [load(p)[1] for p in sys.argv[3:]]
        with open(sys.argv[2], 'w') as f:
            f.write(f'{len(frames):04x}\n')
            for fb in frames:
                for v in fb:
                    f.write(f'{v:04x}\n')
    elif cmd == 'check':
        vals = [int(l, 16) for l in open(sys.argv[2]) if l.strip()]
        n = vals[0]
        frames = [vals[1 + i * W * H:1 + (i + 1) * W * H] for i in range(n)]
        got = [int(l, 16) for l in open(sys.argv[3]) if l.strip()]
        bad = 0
        for i, fb in enumerate(frames):
            want = quant(fb)[RAM_LO:RAM_HI]
            g = got[i * len(want):(i + 1) * len(want)]
            used = lambda a: not (0xFE0 <= RAM_LO + a < 0x1000)   # the gap between attributes and palettes
            diff = [a for a in range(len(want)) if used(a) and (a >= len(g) or g[a] != want[a])]
            print(f'frame {i}: ' + ('OK' if not diff else f'{len(diff)} bytes differ, first at {RAM_LO + diff[0]:#06x}'))
            bad += len(diff)
        sys.exit(1 if bad else 0)
    elif cmd == 'check1':
        # tb_gb_camera's colour shot: the first frame only
        vals = [int(l, 16) for l in open(sys.argv[2]) if l.strip()]
        want = quant(vals[1:1 + W * H])[RAM_LO:RAM_HI]
        g = [int(l, 16) for l in open(sys.argv[3]) if l.strip()]
        diff = [a for a in range(len(want)) if not (0xFE0 <= RAM_LO + a < 0x1000) and (a >= len(g) or g[a] != want[a])]
        print('colour shot: ' + ('OK' if not diff else f'{len(diff)} bytes differ, first at {RAM_LO + diff[0]:#06x}'))
        sys.exit(1 if diff else 0)
    elif cmd == 'show':
        from PIL import Image
        rows = []
        for p in sys.argv[3:]:
            im, fb = load(p)
            q = render(quant(fb))
            pair = Image.new('RGB', (W * 2 + 4, H), (255, 0, 0))
            pair.paste(im, (0, 0))
            pair.paste(q, (W + 4, 0))
            rows.append(pair)
        big = Image.new('RGB', (rows[0].width, (H + 4) * len(rows)), (255, 0, 0))
        for i, r in enumerate(rows):
            big.paste(r, (0, i * (H + 4)))
        big.resize((big.width * 3, big.height * 3), Image.NEAREST).save(sys.argv[2])


if __name__ == '__main__':
    main()
