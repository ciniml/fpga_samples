#!/usr/bin/env python3
# Test cards for ethernet_hub75 (udpvideosend format, waits for each ack).
#   testcards.py [width] [height] [seconds per card] [loops]
# Cards, in turn:
#   1 panel  - each 64x64 panel its own colour, a white frame, its number
#              (1..6, row major) and an arrow in its top-left corner
#   2 bars   - colour bars (top) and a 32-step grey ramp (bottom)
#   3 grid   - 8 px grid, panel boundaries red, centre cross green
#   4 ball   - a ball bouncing over the whole display + frame counter
import socket, sys, time, math

W = int(sys.argv[1]) if len(sys.argv) > 1 else 128
H = int(sys.argv[2]) if len(sys.argv) > 2 else 192
HOLD = float(sys.argv[3]) if len(sys.argv) > 3 else 8.0
LOOPS = int(sys.argv[4]) if len(sys.argv) > 4 else 1000

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
}

def rgb565(c):
    r, g, b = c
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)

class Img:
    def __init__(self, c=(0, 0, 0)):
        self.p = [[c] * W for _ in range(H)]
    def set(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.p[y][x] = c
    def rect(self, x0, y0, w, h, c):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.set(x, y, c)
    def text(self, s, x0, y0, scale, c):
        for ch in s:
            for ry, row in enumerate(FONT[ch]):
                for rx, bit in enumerate(row):
                    if bit == "1":
                        self.rect(x0 + rx * scale, y0 + ry * scale, scale, scale, c)
            x0 += 6 * scale
    def bytes(self):
        return b"".join(rgb565(c).to_bytes(2, "little") for row in self.p for c in row)

def card_panel():
    cols = [(160, 0, 0), (0, 130, 0), (0, 0, 180), (140, 110, 0), (0, 110, 130), (130, 0, 130), (90, 90, 90), (160, 70, 0)]
    img = Img()
    n = 0
    for py in range(H // 64):
        for px in range(W // 64):
            x0, y0 = px * 64, py * 64
            img.rect(x0, y0, 64, 64, cols[n % len(cols)])
            for i in range(64):  # white frame
                img.set(x0 + i, y0, (255, 255, 255)); img.set(x0 + i, y0 + 63, (255, 255, 255))
                img.set(x0, y0 + i, (255, 255, 255)); img.set(x0 + 63, y0 + i, (255, 255, 255))
            for i in range(12):  # arrow in the top-left corner, pointing there
                img.set(x0 + 2 + i, y0 + 2, (255, 255, 0)); img.set(x0 + 2, y0 + 2 + i, (255, 255, 0))
                img.set(x0 + 2 + i, y0 + 2 + i, (255, 255, 0))
            n += 1
            img.text(str(n), x0 + 17, y0 + 11, 6, (255, 255, 255))
    return img

def card_bars():
    bars = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0), (255, 0, 255), (255, 0, 0), (0, 0, 255), (0, 0, 0)]
    img = Img()
    split = H * 2 // 3
    for y in range(split):
        for x in range(W):
            img.set(x, y, bars[x * 8 // W])
    for y in range(split, H):
        for x in range(W):
            v = (x * 32 // W) * 255 // 31
            img.set(x, y, (v, v, v))
    return img

def card_grid():
    img = Img()
    for y in range(H):
        for x in range(W):
            if x % 64 == 0 or x % 64 == 63 or y % 64 == 0 or y % 64 == 63:
                img.set(x, y, (255, 0, 0))
            elif x % 8 == 0 or y % 8 == 0:
                img.set(x, y, (70, 70, 70))
    for i in range(W):
        img.set(i, H // 2, (0, 255, 0))
    for i in range(H):
        img.set(W // 2, i, (0, 255, 0))
    return img

def card_ball(t, frame):
    img = Img((0, 0, 30))
    r = 10
    x = r + abs((t * 70) % (2 * (W - 2 * r)) - (W - 2 * r))
    y = r + abs((t * 95) % (2 * (H - 2 * r)) - (H - 2 * r))
    hue = (t * 0.3) % 1.0
    c = tuple(int(127 + 127 * math.sin(2 * math.pi * (hue + k / 3))) for k in range(3))
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dx * dx + dy * dy <= r * r:
                img.set(int(x) + dx, int(y) + dy, c)
    img.text(str(frame % 10000), 2, 2, 2, (255, 255, 255))
    return img

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("192.168.10.1", 10004))
s.settimeout(0.2)

def send(img):
    data = img.bytes()
    for off in range(0, len(data), 1024):
        s.sendto(off.to_bytes(2, "big") + data[off:off + 1024], ("192.168.10.2", 10004))
    try:
        s.recvfrom(16)
        return True
    except socket.timeout:
        return False

statics = [("panel", card_panel()), ("bars", card_bars()), ("grid", card_grid())]
for loop in range(LOOPS):
    for name, img in statics:
        print(name, "ack" if send(img) else "no ack", flush=True)
        time.sleep(HOLD)
    print("ball", flush=True)
    t0 = time.time()
    frame = 0
    while time.time() - t0 < HOLD:
        send(card_ball(time.time() - t0, frame))
        frame += 1
    print("ball frames", frame, "fps %.1f" % (frame / HOLD), flush=True)
