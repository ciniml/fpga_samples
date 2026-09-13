#!/usr/bin/env python3
"""OSIDES32 IODELAY_1 dynamic-mode experiment on the own-CDR BERT build.

Metric: "pair match" = fraction of sample pairs (2m, 2m+1) in the raw 32-sample
words that carry the same value. Sample 2m is taken on one of the 4 FCLK
phases, sample 2m+1 on the same phase delayed by IODELAY_1. If the delay is
inert both are the same instant -> match ~1.0; with a real ~UI/4 offset a
transition falls between them ~12% of the time on PRBS7 -> match ~0.9.
Per-class PRBS7 scores (decimate by 4) show which sample classes sit in the
eye (~1.0) and which on the edges (~0.5).

Builds: default (static taps) and DYN_DLY1=1 (IODELAY_1 dynamic mode; ext_ctrl
[3] = SDTAP1, [4] = VALUE1, [14:8] = DLYSTEP1).
"""
import argparse, json, time, urllib.request

def api(url, body, to=30):
    req = urllib.request.Request(url + "/api/xfer", data=json.dumps(body).encode(),
                                 headers={"content-type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=to) as r:
        return json.load(r)["data"]

class Bert:
    def __init__(self, url):
        self.url = url; self.c30 = 0; self.c31 = 0
    def w(self, ad, d):
        r = api(self.url, {"write": [0x57, ad, d & 0xff], "read": 1}); assert r == [0x6B], f"W {ad:02x} -> {r}"
    def r(self, ad):
        return api(self.url, {"write": [0x52, ad], "read": 1})[0]
    def ctrl(self, freeze=None, sdtap=None, value=None, dly=None, orst=None):
        if freeze is not None: self.c30 = (self.c30 & ~1) | (1 if freeze else 0)
        if orst is not None:   self.c30 = (self.c30 & ~32) | (32 if orst else 0)
        if sdtap is not None:  self.c30 = (self.c30 & ~8) | (8 if sdtap else 0)
        if value is not None:  self.c30 = (self.c30 & ~16) | (16 if value else 0)
        if dly is not None:    self.c31 = (self.c31 & 0x80) | (dly & 0x7f)
        self.w(0x30, self.c30); self.w(0x31, self.c31)
    def osides_reset(self):
        self.ctrl(orst=True); time.sleep(0.01); self.ctrl(orst=False); time.sleep(0.05)
    def pulse_value(self, n, start_high=False):
        """n VALUE pulses; start_high=False gives rising edges first (low->high->low)"""
        for _ in range(n):
            self.ctrl(value=not start_high); self.ctrl(value=start_high)
    def raw(self):
        self.w(0x31, self.c31 | 0x80); self.w(0x31, self.c31)          # arm capture (ext_ctrl[15] rising)
        d = api(self.url, {"write": [0x42, 0x80, 128], "read": 128})
        words = [int.from_bytes(bytes(d[4*i:4*i+4]), "little") for i in range(32)]
        s = []
        for wd in words: s += [(wd >> k) & 1 for k in range(32)]
        return s
    def status(self): return self.r(0x32)

def metrics(s):
    pairs = [(s[i], s[i+1]) for i in range(0, len(s) - 1, 2)]
    match = sum(1 for a, b in pairs if a == b) / len(pairs)
    trans = sum(s[i] ^ s[i-1] for i in range(1, len(s)))
    cls = []
    for p in range(4):
        b = s[p::4]
        ok = sum(1 for n in range(7, len(b)) if b[n] == (b[n-7] ^ b[n-6]))
        cls.append(ok / max(1, len(b) - 7))
    return match, trans, cls

def measure(bert, label, n=4):
    ms, ts, cs = [], [], [[] for _ in range(4)]
    for _ in range(n):
        m, t, c = metrics(bert.raw()); ms.append(m); ts.append(t)
        for i in range(4): cs[i].append(c[i])
    avg = lambda v: sum(v) / len(v)
    st = bert.status()
    print(f"  {label:<44} pair-match {avg(ms):.3f}  transitions {avg(ts):5.0f}  class PRBS7 {[round(avg(c),2) for c in cs]}  status 0x{st:02x} (DF={((st>>3)&1)})")
    return avg(ms), [avg(c) for c in cs]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8081")
    ap.add_argument("--mode", choices=["static", "dyn"], required=True)
    ap.add_argument("--sweep", type=int, default=0, help="dyn: number of VALUE pulses to sweep (0 = skip)")
    a = ap.parse_args()
    b = Bert(a.url)
    ident = api(a.url, {"write": [0x49], "read": 5}); print("ident:", bytes(ident[:4]), ident[4:])
    b.ctrl(freeze=True)                                  # CDR frozen: sample classes stay put
    time.sleep(0.05)
    if a.mode == "static":
        measure(b, "static build: DLY0=0 / DLY1=21 (baseline)")
        b.osides_reset(); measure(b, "static build after OSIDES32 reset pulse")
        return
    print("E7: load then OSIDES32 reset pulse")
    for d in (21, 42):
        b.ctrl(sdtap=False, dly=d); time.sleep(0.02); b.osides_reset(); measure(b, f"  SDTAP1=0 DLYSTEP1={d} + reset")
        b.ctrl(sdtap=True); time.sleep(0.02); b.osides_reset(); measure(b, f"  SDTAP1=1 DLYSTEP1={d} + reset")
        b.pulse_value(10); b.osides_reset(); measure(b, f"  +10 VALUE pulses + reset")
    # dynamic build
    print("E2: dynamic mode, SDTAP1=0 (load), DLYSTEP1 = 0 / 21 / 42 / 80")
    for d in (0, 21, 42, 80):
        b.ctrl(sdtap=False, dly=d); time.sleep(0.05); measure(b, f"  SDTAP1=0 DLYSTEP1={d}")
    print("E3: SDTAP1=1 then VALUE1 pulses (falling-edge-first and rising-edge-first)")
    for first in (False, True):
        b.ctrl(sdtap=False, dly=0); time.sleep(0.02); b.ctrl(sdtap=True); time.sleep(0.02)
        measure(b, f"  SDTAP1=1, 0 pulses ({'rising' if not first else 'falling'} first)")
        for n in (10, 20, 40):
            b.pulse_value(10 if n == 10 else 10 if n == 20 else 20, start_high=first)
            measure(b, f"  after {n} pulses")
    print("E5: SDTAP1=1 with DLYSTEP1 != 0 (DLYSTEP read as the per-pulse step size)")
    for step in (1, 4, 21):
        for first in (False, True):
            b.ctrl(sdtap=False, dly=step); time.sleep(0.02); b.ctrl(sdtap=True); time.sleep(0.02)
            tot = 0
            for n in (4, 20, 40):
                b.pulse_value(n - tot, start_high=first); tot = n
                measure(b, f"  DLYSTEP1={step:2d} after {n:2d} pulses ({'falling' if first else 'rising'} first)")
    print("E6: DLYSTEP1 set while SDTAP1=0, then one VALUE pulse (load-by-pulse)")
    for v in (21, 42):
        b.ctrl(sdtap=False, dly=v); time.sleep(0.02); b.pulse_value(1); measure(b, f"  DLYSTEP1={v} +1 pulse")
    if a.sweep:
        print(f"E4: sweep {a.sweep} pulses one at a time (pair-match / class scores vs. step)")
        b.ctrl(sdtap=False, dly=0); time.sleep(0.02); b.ctrl(sdtap=True)
        for i in range(a.sweep + 1):
            if i: b.pulse_value(1)
            m, c = measure(b, f"  step {i:3d}", n=2)

if __name__ == "__main__":
    main()
