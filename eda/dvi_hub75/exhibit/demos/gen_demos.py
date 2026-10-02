#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
"""Gentle 128x128 demo loops for the HUB75 panels.

Dark backgrounds, soft light, slow motion; every animation is periodic in
the loop length, so each file loops without a seam.

  python3 gen_demos.py [--out DIR] [--seconds 30] [--preview] [name ...]

Writes <name>.mkv (FFV1, lossless, 59.94 fps, no audio) for prepare.sh
(`./prepare.sh --fps 60000/1001 demos/*.mkv`), and with --preview
<name>_preview.png (4 frames, x3).
names: aurora fireflies lava ripples sunset title
"""
import argparse
import pathlib
import subprocess

import numpy as np

S = 128
FPS_NUM, FPS_DEN = 60000, 1001
Y, X = np.mgrid[0:S, 0:S].astype(np.float32) / S          # 0..1, y down
TAU = 2 * np.pi


def col(r, g, b):
    return np.array([r, g, b], np.float32) / 255.0


def mix(a, b, t):
    t = t[..., None]
    return a * (1 - t) + b * t


def tonemap(img):
    """Soft highlight roll-off instead of hard clipping."""
    return np.clip(img / (1.0 + 0.35 * img), 0, 1)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ---------------------------------------------------------------- aurora
def aurora_setup(rng):
    stars = [(rng.integers(0, S), rng.integers(0, int(S * 0.6)), rng.uniform(0, 1), rng.integers(1, 4))
             for _ in range(45)]
    hill = 0.86 + 0.035 * np.sin(TAU * (X[0] * 1.7 + 0.2)) + 0.02 * np.sin(TAU * (X[0] * 4.3 + 0.7))
    return dict(stars=stars, hill=hill)


def aurora(p, st):
    img = mix(col(6, 10, 34), col(18, 28, 62), Y)
    for k, (c, amp, base) in enumerate([(col(70, 255, 150), 0.75, 0.42),
                                         (col(40, 210, 220), 0.55, 0.34),
                                         (col(170, 100, 255), 0.40, 0.27)]):
        line = (base + 0.10 * np.sin(TAU * (X * 1.2 + p + k * 0.31))
                + 0.04 * np.sin(TAU * (X * 3.0 - 2 * p + k * 0.77)))
        d = line - Y                                         # > 0 above the lower edge
        curtain = np.where(d > 0, np.exp(-d / 0.16), np.exp(-(d / 0.025) ** 2))
        rays = 0.65 + 0.35 * np.sin(TAU * (X * 9 + 0.3 * np.sin(TAU * (p + k * 0.2)) + k * 0.13))
        breathe = 0.75 + 0.25 * np.sin(TAU * (p * (k + 1) + k * 0.4))
        img = img + (curtain * rays * breathe * amp)[..., None] * c
    for (sx, sy, ph, m) in st["stars"]:
        img[sy, sx] += 0.35 * (0.55 + 0.45 * np.sin(TAU * (m * p + ph)))
    img[Y > st["hill"][None, :]] = col(2, 4, 8)            # dark hills
    return img


# ------------------------------------------------------------- fireflies
def fireflies_setup(rng):
    n = 28
    return dict(
        c=rng.uniform(0.1, 0.9, (n, 2)), a=rng.uniform(0.04, 0.16, (n, 2)),
        m=rng.integers(1, 3, (n, 2)), ph=rng.uniform(0, 1, (n, 2)),
        bm=rng.integers(1, 4, n), bph=rng.uniform(0, 1, n),
        size=rng.uniform(1.6, 3.2, n),
        hue=rng.uniform(0, 1, n))


def fireflies(p, st):
    img = mix(col(4, 16, 22), col(10, 34, 26), Y)
    warm, green = col(255, 215, 110), col(190, 255, 120)
    for i in range(len(st["size"])):
        x = st["c"][i, 0] + st["a"][i, 0] * np.sin(TAU * (st["m"][i, 0] * p + st["ph"][i, 0]))
        y = st["c"][i, 1] + st["a"][i, 1] * np.sin(TAU * (st["m"][i, 1] * p + st["ph"][i, 1]))
        b = (0.5 + 0.5 * np.sin(TAU * (st["bm"][i] * p + st["bph"][i]))) ** 2
        r2 = ((X - x) ** 2 + (Y - y) ** 2) * S * S
        s = st["size"][i]
        glow = 0.9 * np.exp(-r2 / (2 * s * s)) + 0.25 * np.exp(-r2 / (2 * (3 * s) ** 2))
        c = warm * (1 - st["hue"][i]) + green * st["hue"][i]
        img = img + (glow * b)[..., None] * c
    return img


# ------------------------------------------------------------------ lava
def lava_setup(rng):
    n = 7
    return dict(x=rng.uniform(0.2, 0.8, n), ax=rng.uniform(0.05, 0.15, n), mx=rng.integers(1, 3, n),
                my=rng.integers(1, 3, n), ph=rng.uniform(0, 1, n), r=rng.uniform(0.09, 0.15, n))


def lava(p, st):
    bg = mix(col(30, 6, 46), col(80, 22, 44), Y)
    f = np.zeros((S, S), np.float32)
    for i in range(len(st["r"])):
        x = st["x"][i] + st["ax"][i] * np.sin(TAU * (st["mx"][i] * p + st["ph"][i]))
        y = 0.5 + 0.38 * np.sin(TAU * (st["my"][i] * p + st["ph"][i] * 1.7))
        f += st["r"][i] ** 2 / ((X - x) ** 2 + (Y - y) ** 2 + 1e-4)
    m = smoothstep(0.85, 1.25, f)
    rim = np.exp(-((f - 1.05) / 0.12) ** 2) * 0.35
    blob = mix(col(255, 150, 60), col(240, 70, 120), Y) * 0.85
    img = mix(bg, blob, m) + rim[..., None] * col(255, 200, 150)
    return img


# --------------------------------------------------------------- ripples
def ripples_setup(rng, seconds):
    n = 26
    return dict(t=np.sort(rng.uniform(0, seconds, n)), x=rng.uniform(0.1, 0.9, n), y=rng.uniform(0.1, 0.9, n),
                seconds=seconds)


def ripples(p, st):
    T = st["seconds"]
    t = p * T
    img = mix(col(6, 30, 46), col(10, 48, 60), Y)
    light = np.zeros((S, S), np.float32)
    for i in range(len(st["t"])):
        age = (t - st["t"][i]) % T
        if age > 5.0:
            continue
        r = 0.02 + 0.075 * age
        d = np.sqrt((X - st["x"][i]) ** 2 + (Y - st["y"][i]) ** 2)
        ring = np.exp(-((d - r) / 0.012) ** 2) + 0.5 * np.exp(-((d - r * 0.72) / 0.010) ** 2)
        light += ring * np.exp(-age / 1.4) * 0.9
        if age < 0.25:                                        # the drop itself
            light += np.exp(-(d / 0.02) ** 2) * (1 - age / 0.25)
    shimmer = 0.04 * np.sin(TAU * (X * 3 + Y * 2 + p * 2)) * np.sin(TAU * (Y * 4 - p * 3))
    return img + (light + shimmer)[..., None] * col(150, 230, 255)


# ---------------------------------------------------------------- sunset
def sunset_setup(rng):
    # per sea row: glint phase, speed (whole cycles per loop), dash frequency
    return dict(ph=rng.uniform(0, 1, S), m=rng.integers(1, 4, S), f=rng.uniform(2.0, 5.0, S),
                dir=rng.choice([-1, 1], S))


def sunset(p, st):
    hz = 0.58
    sky = mix(col(36, 22, 80), col(250, 130, 90), np.clip(Y / hz, 0, 1) ** 1.6) * 0.85
    sx, sy, sr = 0.5, 0.40 + 0.015 * np.sin(TAU * p), 0.085
    d = np.sqrt((X - sx) ** 2 + (Y - sy) ** 2)
    sun = smoothstep(sr + 0.01, sr - 0.01, d)[..., None] * col(255, 205, 130) * 0.9
    glow = (np.exp(-(d / 0.16) ** 2) * 0.35)[..., None] * col(255, 150, 90)
    img = sky + sun + glow
    # sea: darker gradient, sun path made of moving wave glints
    sea_t = np.clip((Y - hz) / (1 - hz), 0, 1)
    sea = mix(col(70, 40, 80), col(12, 14, 40), sea_t)
    # sun path: short horizontal dashes per row drifting sideways and
    # twinkling, wider towards the viewer
    ph, m, f, dr = (st[k][:, None] for k in ("ph", "m", "f", "dir"))
    dash = 0.5 + 0.5 * np.sin(TAU * (f * (X - sx) / (0.15 + 0.5 * sea_t) + dr * m * p + ph))
    twinkle = 0.5 + 0.5 * np.sin(TAU * (m * p + ph * 2))
    path = np.exp(-((X - sx) / (0.04 + 0.16 * sea_t)) ** 2)
    glint = (dash ** 4) * twinkle * path * (0.95 - 0.4 * sea_t)
    swell = 0.05 * (0.5 + 0.5 * np.sin(TAU * (Y * 18 / (0.25 + sea_t) - 2 * p)))
    sea = sea + (glint + swell)[..., None] * col(255, 170, 110)
    return np.where((Y > hz)[..., None], sea, img)


# ----------------------------------------------------------------- title
def title_setup(rng):
    from PIL import Image, ImageDraw, ImageFont
    font = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    msgs = [["HDMI", "↓", "HUB75"], ["Tang Primer", "25K"], ["128 × 128", "LED"], ["FPGA", "DVI / HDMI", "receiver"]]
    cards = []
    for lines in msgs:
        im = Image.new("L", (S, S), 0)
        dr = ImageDraw.Draw(im)
        sizes = []
        for ln in lines:
            size = 26
            while size > 8:
                f = ImageFont.truetype(font, size)
                w = dr.textlength(ln, font=f)
                if w <= 116:
                    break
                size -= 1
            sizes.append((ln, f, w, size))
        total = sum(s * 1.15 for (_, _, _, s) in sizes)
        y = (S - total) / 2
        for (ln, f, w, size) in sizes:
            dr.text(((S - w) / 2, y), ln, font=f, fill=255)
            y += size * 1.15
        cards.append(np.asarray(im, np.float32) / 255.0)
    return dict(cards=cards)


def title(p, st):
    n = len(st["cards"])
    hue = TAU * p
    bg = (mix(col(20, 14, 50), col(10, 40, 60), (0.5 + 0.5 * np.sin(TAU * (X + Y) * 0.7 + hue)))
          * (0.85 + 0.15 * np.sin(TAU * (Y * 2 - p)))[..., None])
    seg = p * n
    i = int(seg) % n
    a = np.sin(np.pi * (seg - int(seg))) ** 2                # fade in / out within each card
    tint = mix(col(255, 210, 160)[None, None, :] * np.ones((S, S, 1)), col(160, 220, 255)[None, None, :] * np.ones((S, S, 1)), Y)
    return bg + (st["cards"][i] * a * 0.85)[..., None] * tint


DEMOS = {
    "aurora": (aurora, aurora_setup),
    "fireflies": (fireflies, fireflies_setup),
    "lava": (lava, lava_setup),
    "ripples": (ripples, ripples_setup),
    "sunset": (sunset, sunset_setup),
    "title": (title, title_setup),
}


def render(name, seconds, out, preview):
    fn, setup = DEMOS[name]
    rng = np.random.default_rng(sum(map(ord, name)))      # fixed per demo
    st = setup(rng, seconds) if name == "ripples" else setup(rng)
    n = round(seconds * FPS_NUM / FPS_DEN)
    path = out / f"{name}.mkv"
    ff = subprocess.Popen(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24",
                           "-s", f"{S}x{S}", "-r", f"{FPS_NUM}/{FPS_DEN}", "-i", "-", "-c:v", "ffv1", str(path)],
                          stdin=subprocess.PIPE)
    shots = []
    for k in range(n):
        p = k / n
        img = (tonemap(fn(p, st)) * 255 + 0.5).astype(np.uint8)
        ff.stdin.write(img.tobytes())
        if preview and (k - n // 8) % (n // 4) == 0 and len(shots) < 4:
            shots.append(img)
    ff.stdin.close()
    ff.wait()
    if preview:
        from PIL import Image
        strip = np.concatenate([np.pad(s, ((2, 2), (2, 2), (0, 0)), constant_values=255) for s in shots], axis=1)
        Image.fromarray(strip).resize((strip.shape[1] * 3, strip.shape[0] * 3), Image.NEAREST).save(out / f"{name}_preview.png")
    print(f"[gen_demos] {path} ({n} frames)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=".")
    ap.add_argument("--seconds", type=float, default=30)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("names", nargs="*", default=list(DEMOS))
    a = ap.parse_args()
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    for name in a.names:
        render(name, a.seconds, out, a.preview)


if __name__ == "__main__":
    main()
