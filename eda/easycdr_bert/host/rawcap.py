#!/usr/bin/env python3
"""Capture 32 raw OSIDES32 words (32 samples each) from the own-CDR BERT
build and analyse the sample time-ordering against PRBS7.

For every hypothesis about the order of the 8 samples within one FCLK
period (a permutation applied to each group of 8 bits) and every phase
offset, the samples are decimated by 4 and checked against the PRBS7
recurrence b[n] = b[n-7] ^ b[n-6]. The right ordering gives ~100 % match
at the eye-centre phases and ~50 % at the edge phases.
"""
import argparse, itertools, json, urllib.request

def api(url, body):
    req = urllib.request.Request(url + "/api/xfer", data=json.dumps(body).encode(),
                                 headers={"content-type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["data"]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8081")
    ap.add_argument("--dump", action="store_true", help="print the raw words")
    a = ap.parse_args()
    w = lambda ad, d: api(a.url, {"write": [0x57, ad, d], "read": 1})
    w(0x31, 0x80); w(0x31, 0x00)                      # arm capture (ext_ctrl[15] rising)
    raw = api(a.url, {"write": [0x42, 0x80, 128], "read": 128})
    words = [int.from_bytes(bytes(raw[4*i:4*i+4]), "little") for i in range(32)]
    samples = []
    for wd in words:
        samples += [(wd >> k) & 1 for k in range(32)]       # index k = assumed time order
    if a.dump:
        for i, wd in enumerate(words):
            print(f"{i:2d} {wd:032b}"[::1])
    trans = sum(samples[i] ^ samples[i-1] for i in range(1, len(samples)))
    print(f"{len(samples)} samples, {trans} transitions (PRBS7 @4x expects ~{len(samples)//8})")

    def score(seq):
        # decimate by 4 at each phase, check PRBS7 recurrence
        res = []
        for p in range(4):
            b = seq[p::4]
            ok = sum(1 for n in range(7, len(b)) if b[n] == (b[n-7] ^ b[n-6]))
            res.append(ok / max(1, len(b) - 7))
        return res

    print("assumed order (Q[k] = k-th in time):", ["%.2f" % v for v in score(samples)])
    # hypotheses: permutations of the 8 positions inside each 8-sample group
    best = []
    for perm in itertools.permutations(range(8)):
        seq = []
        for g in range(0, len(samples), 8):
            grp = samples[g:g+8]
            seq += [grp[perm[j]] for j in range(8)]
        sc = score(seq)
        best.append((max(sc), perm, sc))
    best.sort(reverse=True)
    print("top orderings (max phase score, permutation within 8-sample group, per-phase scores):")
    for m, perm, sc in best[:8]:
        print(f"  {m:.3f}  {perm}  {['%.2f' % v for v in sc]}")

if __name__ == "__main__":
    main()
