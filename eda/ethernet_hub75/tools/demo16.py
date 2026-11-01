#!/usr/bin/env python3
# Demo for the 16-panel build (256x256, 4 x 4) when only the top-left 2 x 3
# panels are connected (J4 J5 / J8 J9 / J12 J13): two scenes in turn, both
# sent as full 256x256 frames (udpvideosend format, offsets in 2-byte units,
# waits for each ack).
#   demo16.py [seconds per scene] [fps] [seconds of the GMT comparison]
# Scenes:
#   16 panels - the whole 256x256: every panel numbered 1..16, a rainbow
#               sweep and a ball crossing all of it (only panels 1 2 / 5 6 /
#               9 10 are seen, the ball leaves and comes back)
#   6 panels  - only the top-left 128x192: plasma, a white frame around
#               the area and a ball bouncing inside it; the rest is black
#   fps       - frames sent as fast as the acks come back (one per panel
#               frame): measured frame rate, frame counter and a marker
#               that moves one step per frame
#   gmt       - GMT vs fabric corner turn of the 16-panel build (LUT, FF,
#               system clock Fmax; numbers from the README)
# The last two scenes use the top-left 128x192 only.
import math, socket, sys, time
import numpy as np

W, H = 256, 256          # frame sent (PANEL_COLS=4 PANEL_ROWS=4)
VW, VH = 128, 192        # the area of the connected panels
HOLD = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
FPS = float(sys.argv[2]) if len(sys.argv) > 2 else 60.0
HOLD_CMP = float(sys.argv[3]) if len(sys.argv) > 3 else 25.0  # to be read

FONT = {  # 5x7
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    "=": ["00000", "00000", "11111", "00000", "11111", "00000", "00000"],
    " ": ["00000"] * 7,
}


def text(img, s, x0, y0, scale, c):
    for ch in s:
        for ry, row in enumerate(FONT[ch]):
            for rx, bit in enumerate(row):
                if bit == "1":
                    img[y0 + ry * scale:y0 + (ry + 1) * scale, x0 + rx * scale:x0 + (rx + 1) * scale] = c
        x0 += 6 * scale


def hsv(h):
    """hue array (0..1) -> RGB float arrays 0..1 (full saturation / value)"""
    k = lambda n: (n + h * 6) % 6
    f = lambda n: 1 - np.clip(np.minimum(k(n), 4 - k(n)), 0, 1)
    return f(5), f(3), f(1)


YY, XX = np.mgrid[0:H, 0:W].astype(np.float32)

# ---- scene 1: the whole 256x256 ----
def panels_background():
    img = np.zeros((H, W, 3), np.uint8)
    n = 0
    for py in range(4):
        for px in range(4):
            x0, y0 = px * 64, py * 64
            r, g, b = hsv(np.array(n / 16.0))
            img[y0:y0 + 64, x0:x0 + 64] = (int(r * 70), int(g * 70), int(b * 70))
            img[y0, x0:x0 + 64] = img[y0 + 63, x0:x0 + 64] = 200
            img[y0:y0 + 64, x0] = img[y0:y0 + 64, x0 + 63] = 200
            n += 1
            s = str(n)
            text(img, s, x0 + 32 - len(s) * 12 + 2, y0 + 18, 4, (255, 255, 255))
    text(img, "16 PANELS", 5, 4, 1, (255, 255, 0))
    text(img, "256X256", 64 + 11, 4, 1, (255, 255, 0))
    return img


BG16 = panels_background()


def scene16(t, st):
    img = BG16.copy()
    # rainbow band sweeping diagonally over the whole frame
    d = (XX + YY - t * 160) % 512
    band = (d < 24)
    r, g, b = hsv((XX - YY) / 512.0 + t * 0.1)
    for i, ch in enumerate((r, g, b)):
        img[..., i] = np.where(band, (ch * 255).astype(np.uint8), img[..., i])
    # ball bouncing over the full 256x256
    rad = 22
    bx = rad + abs((t * 90) % (2 * (W - 2 * rad)) - (W - 2 * rad))
    by = rad + abs((t * 67) % (2 * (H - 2 * rad)) - (H - 2 * rad))
    m = (XX - bx) ** 2 + (YY - by) ** 2 <= rad * rad
    img[m] = (255, 255, 255)
    return img


# ---- scene 2: only the top-left 128x192 ----
VY, VX = np.mgrid[0:VH, 0:VW].astype(np.float32)


def scene6(t, st):
    img = np.zeros((H, W, 3), np.uint8)
    v = (np.sin(VX / 11 + t * 1.3) + np.sin(VY / 17 - t * 0.9)
         + np.sin((VX + VY) / 23 + t * 0.7) + np.sin(np.hypot(VX - 64, VY - 96) / 9 - t * 2.0))
    r, g, b = hsv(v / 8 + t * 0.05)
    area = np.stack([r, g, b], -1) * 150
    rad = 14
    bx = rad + abs((t * 70) % (2 * (VW - 2 * rad)) - (VW - 2 * rad))
    by = rad + abs((t * 95) % (2 * (VH - 2 * rad)) - (VH - 2 * rad))
    area[(VX - bx) ** 2 + (VY - by) ** 2 <= rad * rad] = 255
    img[:VH, :VW] = area.astype(np.uint8)
    img[0:2, :VW] = img[VH - 2:VH, :VW] = 255
    img[:VH, 0:2] = img[:VH, VW - 2:VW] = 255
    img[3:14, 3:61] = 0
    text(img, "6 PANELS", 5, 5, 1, (255, 255, 0))
    img[3:14, 67:115] = 0
    text(img, "128X192", 69, 5, 1, (255, 255, 0))
    return img


# ---- scene 3: frame rate (128x192) ----
def scene_fps(t, st):
    img = np.zeros((H, W, 3), np.uint8)
    n = st["frames"]
    text(img, "FRAME RATE", 4, 4, 2, (255, 255, 0))
    text(img, "%3d" % round(st["fps"]), 4, 26, 6, (255, 255, 255))
    text(img, "FPS", 4 + 18 * 6 + 2 - 18, 26 + 44, 1, (255, 255, 255))
    text(img, "FRAME", 4, 86, 1, (150, 150, 150))
    text(img, "%07d" % n, 4, 96, 2, (0, 255, 120))
    text(img, "1 STEP / FRAME", 4, 118, 1, (150, 150, 150))
    # marker: one cell per frame along a 16 x 6 grid of 8x8 cells (96 frames a lap)
    y0 = 130
    img[y0:y0 + 48, 0:VW] = 30
    k = n % 96
    for j in range(8):  # trail
        c = (k - j) % 96
        x, y = (c % 16) * 8, y0 + (c // 16) * 8
        v = 255 - j * 30
        img[y:y + 7, x:x + 7] = (v, v // 3, 0) if j else (255, 255, 255)
    text(img, "VIDEO = PANEL REFRESH", 2, 182, 1, (120, 120, 255))
    return img


# ---- scene 4: GMT vs fabric corner turn (16-panel build, 6-bit, README) ----
CMP = [  # name, GMT, fabric, unit
    ("LUT", 7256, 8215),
    ("FF", 4938, 6122),
]
FMAX = (125.2, 116.8, 125.1)  # system clock: GMT place option 2, fabric option 2 (misses 125), fabric option 1


def scene_gmt(t, st):
    img = np.zeros((H, W, 3), np.uint8)
    grow = min(1.0, t / 1.5)
    green, orange = (0, 230, 90), (255, 130, 0)
    text(img, "GMT/SOFT", 4, 3, 2, (255, 255, 0))
    text(img, "16 PANELS 6 BIT", 4, 20, 1, (150, 150, 150))
    img[30:37, 4:11] = green
    text(img, "GMT", 14, 30, 1, green)
    img[30:37, 46:53] = orange
    text(img, "SOFT", 56, 30, 1, orange)
    y = 44
    for name, g, f in CMP:
        text(img, name, 4, y, 2, (255, 255, 255))
        for i, (v, c) in enumerate(((g, green), (f, orange))):
            yy = y + 18 + i * 12
            w = int(grow * v / 8300 * 82)
            img[yy:yy + 9, 4:4 + w] = c
            text(img, str(v), 90, yy + 1, 1, c)
        text(img, "SOFT %+d" % (f - g), 50, y + 4, 1, (255, 80, 80))
        y += 46
    text(img, "SYS FMAX MHZ", 4, y, 1, (255, 255, 255))
    text(img, "GMT  %.1f" % FMAX[0], 4, y + 11, 1, green)
    text(img, "OK", 76, y + 11, 1, green)
    text(img, "SOFT %.1f" % FMAX[1], 4, y + 21, 1, orange)
    text(img, "NG", 76, y + 21, 1, (255, 80, 80))
    text(img, "SOFT %.1f OPT1" % FMAX[2], 4, y + 31, 1, orange)
    text(img, "TARGET 125.0", 4, y + 43, 1, (150, 150, 150))
    return img


def rgb565_bytes(img):
    r = img[..., 0].astype(np.uint16) >> 3
    g = img[..., 1].astype(np.uint16) >> 2
    b = img[..., 2].astype(np.uint16) >> 3
    return ((r << 11) | (g << 5) | b).astype("<u2").tobytes()


s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("192.168.10.1", 10004))
s.settimeout(0.2)


def send(data):
    unit = 2 if len(data) > 65536 else 1
    for off in range(0, len(data), 1024):
        s.sendto((off // unit).to_bytes(2, "big") + data[off:off + 1024], ("192.168.10.2", 10004))


def wait_ack():
    try:
        s.recvfrom(16)
        return True
    except socket.timeout:
        return False


scenes = [  # name, scene, frames paced at FPS (else as fast as the acks), seconds
    ("16 panels (256x256)", scene16, True, HOLD),
    ("6 panels (128x192)", scene6, True, HOLD),
    ("frame rate", scene_fps, False, HOLD),
    ("GMT vs soft", scene_gmt, True, HOLD_CMP),
]
st = {"fps": 0.0, "frames": 0}
stamps = []
while True:
    for name, fn, paced, hold in scenes:
        t0 = time.time()
        frames = acks = 0
        nxt = t0
        stamps.clear()
        data = rgb565_bytes(fn(0.0, st))
        while time.time() - t0 < hold:
            send(data)
            frames += 1
            st["frames"] += 1
            # the next frame is drawn while the panel finishes its frame
            # (render + send in one panel frame would miss every other flip)
            data = rgb565_bytes(fn(time.time() - t0, st))
            acks += wait_ack()
            now = time.time()
            stamps.append(now)
            while stamps[0] < now - 1.0:
                stamps.pop(0)
            st["fps"] = len(stamps) / min(1.0, max(1e-3, now - t0))
            if paced:
                nxt += 1.0 / FPS
                time.sleep(max(0.0, nxt - time.time()))
        print("%-20s %d frames (%.1f fps), %d acks" % (name, frames, frames / hold, acks), flush=True)
