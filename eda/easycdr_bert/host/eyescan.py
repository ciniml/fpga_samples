#!/usr/bin/env python3
"""BERT-based eye scan through serial-bridge (util/serial_bridge).

Freezes the RX CDR phase (rtl/oscdr own PHY), then steps the TX PLL
output phase (PLLA dynamic phase shift, 125ps = 1/8 UI per pulse at
VCO=1GHz) while counting PRBS errors at each point. After the scan the
phase is stepped back to where it started.

  eyescan.py [--url http://127.0.0.1:8081] [--steps 24] [--dwell 0.1] [--csv out.csv]
"""
import argparse, json, math, time, urllib.request

def api(url, body):
    req = urllib.request.Request(url + "/api/xfer", data=json.dumps(body).encode(),
                                 headers={"content-type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["data"]

class Bert:
    def __init__(self, url): self.url = url
    def w(self, a, d):
        if api(self.url, {"write": [0x57, a, d], "read": 1}) != [0x6B]: raise RuntimeError("nack")
    def r(self, a): return api(self.url, {"write": [0x52, a], "read": 1})[0]
    def burst(self, a, n): return api(self.url, {"write": [0x42, a, n], "read": n})
    def ctrl(self): return self.r(0) & 0xE3          # keep mode bits, drop self-clearing ones
    def clear(self): self.w(0, self.ctrl() | 0x04)
    def snap(self):
        self.w(0, self.ctrl() | 0x08)
        d = self.burst(0x10, 24)
        le = lambda o, n: int.from_bytes(bytes(d[o:o + n]), "little")
        return le(0, 8), le(8, 8), le(16, 4), le(20, 4)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8081")
    ap.add_argument("--steps", type=int, default=24, help="phase steps to scan (8 = 1 UI)")
    ap.add_argument("--dwell", type=float, default=0.1, help="seconds per point")
    ap.add_argument("--step-ps", type=float, default=125.0)
    ap.add_argument("--csv")
    a = ap.parse_args()
    b = Bert(a.url)
    api(a.url, {"write": [0x49], "read": 5})
    st = b.r(8)
    if not (st & 1):
        raise SystemExit(f"PRBS not locked (STATUS=0x{st:02x}); scan needs a locked link")
    ext = b.r(0x32)
    print(f"CDR lock={ext & 1} phase={(ext >> 1) & 3}; freezing RX phase, stepping TX phase "
          f"{a.steps} x {a.step_ps:.0f} ps, {a.dwell}s each")
    rows = []
    FREEZE, PSDIR_DEC, PSPULSE = 0x01, 0x02, 0x04
    def pulse(dec):
        base = FREEZE | (PSDIR_DEC if dec else 0)
        b.w(0x30, base | PSPULSE); b.w(0x30, base)
    try:
        b.w(0x30, FREEZE)                     # freeze the RX phase
        for i in range(a.steps + 1):
            if i:
                pulse(dec=False)
                time.sleep(0.005)
            b.clear()
            time.sleep(a.dwell)
            bits, errs, unl, _ = b.snap()
            ber = errs / bits if bits else float("nan")
            rows.append((i, bits, errs, unl, ber))
            bar = "#" * min(40, int(40 * (math.log10(max(ber, 1e-12)) + 12) / 12)) if bits and errs else ""
            print(f"step {i:3d} ({i * a.step_ps:7.1f} ps  {i * a.step_ps / 1000:5.3f} UI): "
                  f"bits={bits:>11,d} errs={errs:>8d} BER={ber:9.2e} {bar}")
    finally:
        for _ in range(a.steps):              # walk the phase back
            pulse(dec=True)
        b.w(0x30, 0x00)                       # unfreeze
    # eye width: longest run of error-free points
    best, cur, start, bstart = 0, 0, None, None
    for i, bits, errs, _, _ in rows:
        if bits and errs == 0:
            if cur == 0: start = i
            cur += 1
            if cur > best: best, bstart = cur, start
        else:
            cur = 0
    if best:
        print(f"widest error-free window: steps {bstart}..{bstart + best - 1} = "
              f"{best} points x {a.step_ps:.0f} ps -> eye opening >= {(best - 1) * a.step_ps:.0f} ps "
              f"({(best - 1) * a.step_ps / 1000:.2f} UI at 1Gbps)")
    if a.csv:
        with open(a.csv, "w") as f:
            f.write("step,ps,bits,errs,unlocks,ber\n")
            for i, bits, errs, unl, ber in rows:
                f.write(f"{i},{i * a.step_ps},{bits},{errs},{unl},{ber}\n")
        print("saved", a.csv)

if __name__ == "__main__":
    main()
