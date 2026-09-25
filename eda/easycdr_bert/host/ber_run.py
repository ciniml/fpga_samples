#!/usr/bin/env python3
"""BER measurement over the serial bridge (rate variants, no browser).

Clears the counters, waits --dwell seconds, snapshots and prints bits /
errors / unlocks / BER and the lock status; --prbs selects the pattern
(0 PRBS7 .. 4 PRBS31), --repeat repeats the measurement.

  ber_run.py [--url http://127.0.0.1:8081] [--dwell 10] [--prbs 4] [--repeat 1] [--rate-gbps 1.0]
"""
import argparse, json, time, urllib.request

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
    def ctrl(self): return self.r(0) & 0xE3
    def clear(self): self.w(0, self.ctrl() | 0x04)
    def snap(self):
        self.w(0, self.ctrl() | 0x08)
        d = self.burst(0x10, 24)
        le = lambda o, n: int.from_bytes(bytes(d[o:o + n]), "little")
        return le(0, 8), le(8, 8), le(16, 4), le(20, 4)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8081")
    ap.add_argument("--dwell", type=float, default=10.0)
    ap.add_argument("--prbs", type=int, default=4, help="0 PRBS7 1 PRBS9 2 PRBS15 3 PRBS23 4 PRBS31")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--rate-gbps", type=float, default=1.0, help="only for the expected-bits sanity column")
    a = ap.parse_args()
    b = Bert(a.url)
    ident = bytes(api(a.url, {"write": [0x49], "read": 5}))
    print(f"ident {ident!r}")
    b.w(2, a.prbs); b.w(3, a.prbs)
    time.sleep(0.3)
    st = b.r(8)
    print(f"STATUS=0x{st:02x} locked={st & 1} rx_activity={(st >> 1) & 1} link_ok={(st >> 2) & 1}")
    for n in range(a.repeat):
        b.clear()
        t0 = time.time(); time.sleep(a.dwell)
        bits, errs, unl, tmr = b.snap(); dt = time.time() - t0
        ber = errs / bits if bits else float("nan")
        bound = 3.0 / bits if bits and errs == 0 else ber
        st = b.r(8)
        print(f"[{n}] {dt:5.1f}s bits={bits:>14,d} ({bits / dt / 1e9:.3f} Gbps, expect {a.rate_gbps:.3f}) "
              f"errs={errs:,d} unlocks={unl} BER={ber:.2e} (95% upper {bound:.1e}) locked={st & 1}")

if __name__ == "__main__":
    main()
