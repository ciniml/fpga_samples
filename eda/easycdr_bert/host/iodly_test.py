#!/usr/bin/env python3
"""Standalone IODELAY test (BERT build with IODLY_TEST=1).

A 500MHz tone (period 2ns = 16 TX-DPS steps of 125ps) is looped back through
an IODELAY and sampled by a fixed-phase flip-flop. ext_status = ones per 255
samples. Sweeping the TX PLL phase (ext_ctrl[2] pulses, direction ext_ctrl[1])
traces the tone: ~255 while the sampling instant is inside the high half,
~0 in the low half, intermediate at the edges. The edge position (in DPS
steps) is the observable; IODELAY steps must shift it (80 steps = 1ns = 8 DPS
steps; 12.5ps = 0.1 DPS step, resolved by the ones-count interpolation).
"""
import argparse, json, time, urllib.request

def api(url, body, to=30):
    req = urllib.request.Request(url + "/api/xfer", data=json.dumps(body).encode(),
                                 headers={"content-type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=to) as r:
        return json.load(r)["data"]

class Dev:
    def __init__(self, url): self.url, self.c30, self.c31 = url, 0, 0
    def w(self, ad, d):
        r = api(self.url, {"write": [0x57, ad, d & 0xff], "read": 1}); assert r == [0x6B], f"W {ad:02x} -> {r}"
    def r(self, ad): return api(self.url, {"write": [0x52, ad], "read": 1})[0]
    def ctrl(self, **kw):
        bits = {"freeze": 1, "psdir": 2, "pspulse": 4, "sdtap": 8, "value": 16}
        for k, v in kw.items():
            if k == "dly": self.c31 = (self.c31 & 0x80) | (v & 0x7f)
            else: self.c30 = (self.c30 & ~bits[k]) | (bits[k] if v else 0)
        self.w(0x30, self.c30); self.w(0x31, self.c31)
    def dps(self, n, forward=True):
        self.ctrl(psdir=forward)
        for _ in range(abs(n)): self.ctrl(pspulse=True); self.ctrl(pspulse=False)
    def ones(self, n=3):
        time.sleep(0.01); return sum(self.r(0x32) for _ in range(n)) / n
    def pulse_value(self, n):
        for _ in range(n): self.ctrl(value=True); self.ctrl(value=False)

def profile(d, steps=32):
    """ones-count vs DPS step (forward), then return to the start"""
    prof = []
    for i in range(steps):
        prof.append(d.ones())
        d.dps(1)
    d.dps(steps, forward=False)
    return prof

def rising_edge(prof):
    """position (fractional DPS steps) of the low->high crossing at 127.5"""
    n = len(prof)
    for i in range(n):
        a, b = prof[i], prof[(i + 1) % n]
        if a < 127.5 <= b:
            return i + (127.5 - a) / (b - a)
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8081")
    ap.add_argument("--mode", choices=["static", "dyn", "adapt"], required=True)
    a = ap.parse_args()
    d = Dev(a.url)
    print("ident:", bytes(api(a.url, {"write": [0x49], "read": 5})[:4]))
    d.ctrl(freeze=True)
    def show(label):
        p = profile(d)
        e = rising_edge(p)
        print(f"  {label:<40} edge at DPS {e if e is None else round(e, 2)}   profile {[int(x) for x in p]}")
        return e
    e0 = show("initial")
    if a.mode == "static":
        show("again (repeatability)")
        return
    if a.mode == "adapt":
        print("adaptive IODELAY: SDTAP=0 load, then SDTAP=1 + VALUE rising edge with a new target DLYSTEP")
        d.ctrl(sdtap=False, dly=0); time.sleep(0.02); show("SDTAP=0 DLYSTEP=0 loaded")
        for target in (40, 80, 0):
            d.ctrl(sdtap=True); d.ctrl(dly=target); time.sleep(0.01)
            d.ctrl(value=False); d.ctrl(value=True); time.sleep(0.05)      # rising edge starts the adaptation
            show(f"SDTAP=1 target {target}, after VALUE rising (expect edge +{target*12.5/125:.1f} mod 16)")
            time.sleep(0.5); show(f"  ... 0.5s later")
            d.ctrl(value=False)
        d.ctrl(sdtap=False, dly=0)
        return
    print("dynamic IODELAY: SDTAP=0 load DLYSTEP")
    for v in (0, 20, 40, 80):
        d.ctrl(sdtap=False, dly=v); time.sleep(0.02)
        show(f"SDTAP=0 DLYSTEP={v} (expect +{v*12.5/125:.1f} DPS mod 16)")
    print("dynamic IODELAY: SDTAP=1 + VALUE pulses, DLYSTEP as step")
    for step in (1, 8):
        d.ctrl(sdtap=False, dly=step); time.sleep(0.02); d.ctrl(sdtap=True)
        for n in (10, 40):
            d.pulse_value(n if n == 10 else 30)
            show(f"DLYSTEP={step} after {n} pulses (expect +{n*step*12.5/125:.1f} DPS)")
    d.ctrl(sdtap=False, dly=0)

if __name__ == "__main__":
    main()
