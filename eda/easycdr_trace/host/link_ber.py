#!/usr/bin/env python3
"""8b10b link error rate of the 25K trace receiver (self-test loopback or Nano9K TX).

Polls the 'L' link diagnostics every --interval seconds for --seconds and sums
the 8b10b decode errors; the number of received symbols is taken from the
line rate (--rate-gbps / 10 symbols per second), so the result is a symbol
error rate. The per-poll counters saturate at 65535, so keep the interval
short when the link is bad.

  link_ber.py [--url http://127.0.0.1:8081] [--seconds 10] [--interval 0.1] [--rate-gbps 1.0]
"""
import argparse, json, time, urllib.request

def api(url, body):
    req = urllib.request.Request(url + "/api/xfer", data=json.dumps(body).encode(),
                                 headers={"content-type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)
def flush(url):
    urllib.request.urlopen(urllib.request.Request(url + "/api/flush", data=b"{}",
                           headers={"content-type": "application/json"}, method="POST")).read()

def link_diag(url):
    d = api(url, {"write": [0x4C], "read": 14, "timeout_ms": 2000})["data"]
    if len(d) != 14: return None
    u16 = lambda i: d[i] | (d[i+1] << 8)
    return {"status": d[0], "ver": d[1], "commas": u16(2), "records": u16(4), "errors": u16(6),
            "ovf": u16(8), "desc": u16(10), "data": u16(12)}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8081")
    ap.add_argument("--seconds", type=float, default=10.0)
    ap.add_argument("--interval", type=float, default=0.1)
    ap.add_argument("--rate-gbps", type=float, default=1.0)
    a = ap.parse_args()
    flush(a.url); link_diag(a.url)          # clear the counters
    t0 = time.time(); errs = sat = polls = 0; lost = 0; st_or = 0; st_and = 0xff; noalign = 0; commas = recs = 0
    while time.time() - t0 < a.seconds:
        time.sleep(a.interval)
        lg = link_diag(a.url)
        if lg is None: lost += 1; continue
        polls += 1; errs += lg["errors"]; sat += lg["errors"] == 65535
        st_or |= lg["status"]; st_and &= lg["status"]
        noalign += not (lg["status"] & 2); commas += lg["commas"]; recs += lg["records"]
    dt = time.time() - t0
    syms = a.rate_gbps * 1e9 / 10 * dt
    ser = errs / syms
    print(f"{dt:.1f}s: {polls} polls, status always=0x{st_and:02x} ever=0x{st_or:02x} "
          f"(bit0 lock bit1 align bit3 commas), 8b10b errors={errs:,d}"
          f"{' (saturated in ' + str(sat) + ' polls)' if sat else ''}, symbols~{syms:.2e} -> "
          f"symbol error rate {ser:.2e}" + (f" (95% upper {3/syms:.1e})" if errs == 0 else "") +
          (f", {lost} lost replies" if lost else "") +
          f"; align lost in {noalign}/{polls} polls, commas {commas:,d} records {recs:,d} (16-bit saturating sums)")

if __name__ == "__main__":
    main()
