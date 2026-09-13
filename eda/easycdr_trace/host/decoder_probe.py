#!/usr/bin/env python3
"""Probe the EasyCDR IP's 8b10b decoder with raw symbol injection.

Setup: Tang Primer 25K alone, USB-C cable from pmod0 (self-test TX, lane L1)
to pmod2 (RX, lane L0), serial-bridge on the 25K UART. The 'J' command loads
up to 64 raw 10-bit symbols into the self-test transmitter and loops them;
'R' 1 makes the capture store every received word as
{align, err, dout[9], K, data[7:0]}. See doc/decoder_probe.md.
"""
import argparse, json, sys, time, urllib.request
from collections import Counter

# ---------------------------------------------------------------- 8b10b tables
# 5b/6b: D.x -> (RD- form, RD+ form) as 'abcdei' strings
T6 = {0:("100111","011000"),1:("011101","100010"),2:("101101","010010"),3:("110001","110001"),
      4:("110101","001010"),5:("101001","101001"),6:("011001","011001"),7:("111000","000111"),
      8:("111001","000110"),9:("100101","100101"),10:("010101","010101"),11:("110100","110100"),
      12:("001101","001101"),13:("101100","101100"),14:("011100","011100"),15:("010111","101000"),
      16:("011011","100100"),17:("100011","100011"),18:("010011","010011"),19:("110010","110010"),
      20:("001011","001011"),21:("101010","101010"),22:("011010","011010"),23:("111010","000101"),
      24:("110011","001100"),25:("100110","100110"),26:("010110","010110"),27:("110110","001001"),
      28:("001110","001110"),29:("101110","010001"),30:("011110","100001"),31:("101011","010100")}
K6 = ("001111","110000")                                     # K28
# 3b/4b: D.x.y -> (RD- form, RD+ form) as 'fghj'
T4 = {0:("1011","0100"),1:("1001","1001"),2:("0101","0101"),3:("1100","0011"),
      4:("1101","0010"),5:("1010","1010"),6:("0110","0110"),7:("1110","0001")}
A7 = ("0111","1000")
# K28.y 3b/4b indexed by the RD *after* the 6b (K28 6b always flips RD):
# index 1 = initial RD- (001111 ...), index 0 = initial RD+ (110000 ...)
K4 = {0:("1011","0100"),1:("0110","1001"),2:("1010","0101"),3:("1100","0011"),
      4:("1101","0010"),5:("0101","1010"),6:("1001","0110"),7:("0111","1000")}
KX7 = {23:("111010","000101"),27:("110110","001001"),29:("101110","010001"),30:("011110","100001")}

def disp(bits): return bits.count("1") - bits.count("0")

def encode(x, y, rd, k=False, force_a7=None, force_rd_form=None):
    """Return (bits 'abcdeifghj', rd_after). rd = -1 or +1 (running disparity before).
    force_rd_form: use the opposite RD form (valid code, disparity violation)."""
    sel = 0 if rd < 0 else 1
    rdf = rd
    if force_rd_form is not None:
        sel = force_rd_form; rdf = -1 if sel == 0 else 1     # pretend the RD matched the forced form
    if k and x == 28:
        six = K6[sel]
    elif k and x in KX7 and y == 7:
        six = KX7[x][sel]
    elif k:
        raise ValueError("no such K code")
    else:
        six = T6[x][sel]
    rd2 = rdf if disp(six) == 0 else -rdf
    sel2 = 0 if rd2 < 0 else 1
    if k and x == 28: four = K4[y][sel2]
    elif k:           four = A7[sel2]
    else:
        use_a7 = force_a7 if force_a7 is not None else (y == 7 and ((rd2 < 0 and x in (17,18,20)) or (rd2 > 0 and x in (11,13,14))))
        four = A7[sel2] if use_a7 else T4[y][sel2]
    bits = six + four
    rd3 = rd_after(bits, rd)          # actual line disparity (a forced form violates RD)
    return bits, rd3

def rd_after(bits, rd):
    """running disparity after an arbitrary 10-bit group (by actual disparity)"""
    d = disp(bits)
    return rd if d == 0 else (1 if d > 0 else -1)

def to_int(bits):                      # bit 0 = 'a' = first on the wire
    return sum((int(b) << i) for i, b in enumerate(bits))
def to_bits(v): return "".join(str((v >> i) & 1) for i in range(10))

def name(k, x, y): return f"{'K' if k else 'D'}{x}.{y}"

# ---------------------------------------------------------------- transport
def api(url, body, to=8000):
    req = urllib.request.Request(url + "/api/xfer", data=json.dumps(body).encode(), headers={"content-type": "application/json"})
    return json.loads(urllib.request.urlopen(req, timeout=to / 1000 + 5).read())
def flush(url): urllib.request.urlopen(urllib.request.Request(url + "/api/flush", data=b"{}", headers={"content-type": "application/json"})).read()

class Probe:
    def __init__(self, url, entries=1 << 14):
        self.url, self.entries = url, entries
    def cmd(self, wr, rd, to=2000):
        flush(self.url); return api(self.url, {"write": wr, "read": rd, "timeout_ms": to}, to)["data"]
    def inject(self, syms, mode=2):
        assert 0 < len(syms) <= 64
        b = [0x4A, mode, len(syms)]
        for s in syms: b += [s & 0xff, (s >> 8) & 3]
        r = self.cmd(b, 1); assert r == [0x4A], f"J reply {r}"
    def inject_stop(self):
        r = self.cmd([0x4A, 0, 0], 1); assert r == [0x4A], f"J stop reply {r}"
    def raw_mode(self, on):
        r = self.cmd([0x52, 1 if on else 0], 1); assert r == [0x52], f"R reply {r}"
    def diag(self):
        d = self.cmd([0x4C], 14)
        u16 = lambda i: d[i] | (d[i+1] << 8)
        return {"status": d[0], "commas": u16(2), "records": u16(4), "errors": u16(6), "ovf": u16(8), "desc": u16(10), "data": u16(12)}
    def capture(self):
        r = self.cmd([0x53], 1, 8000)                                  # 'S' -> 'K'
        assert r == [0x4B], f"S reply {r}"
        raw = []
        api(self.url, {"write": [0x44], "read": 0})                    # 'D'
        while len(raw) < self.entries * 2:
            rr = api(self.url, {"write": [], "read": min(4096, self.entries * 2 - len(raw)), "timeout_ms": 20000}, 20000)
            raw += rr["data"]
            if rr["timeout"]: break
        words = []
        for i in range(len(raw) // 2):
            hi, lo = raw[2*i], raw[2*i+1]
            words.append({"k": hi & 1, "b9": (hi >> 1) & 1, "err": (hi >> 2) & 1, "align": (hi >> 3) & 1, "data": lo})
        return words

# ---------------------------------------------------------------- test helpers
def build(seq, rd=-1):
    """seq: list of entries. Entry = (k, x, y) or dict(k,x,y,rd_form=0/1,a7=bool) or ('raw', bits, label).
    Returns (symbol ints, labels, expected list of (k, byte) or None). RD tracked by actual disparity."""
    syms, labels, exp = [], [], []
    for e in seq:
        if isinstance(e, tuple) and e[0] == "raw":
            bits, lab = e[1], e[2]; syms.append(to_int(bits)); labels.append(lab); exp.append(None); rd = rd_after(bits, rd); continue
        if isinstance(e, tuple): k, x, y = e; opts = {}
        else: k, x, y = e["k"], e["x"], e["y"]; opts = e
        bits, rd = encode(x, y, rd, k, opts.get("a7"), opts.get("rd_form"))
        syms.append(to_int(bits)); labels.append(name(k, x, y) + ("*" if opts else "")); exp.append((1 if k else 0, (y << 5) | x))
    return syms, labels, exp, rd

FLIP = (False, 3, 0)      # D3.0: 6b neutral, 4b +/-2 -> flips the running disparity (D0.0 does not)

def balanced_frame(payload, rd=-1):
    """payload followed by K28.5; pad with D3.0 if needed so the loop returns to the starting RD."""
    seq = list(payload) + [(True, 28, 5)]
    syms, labels, exp, rd_end = build(seq, rd)
    if rd_end != rd:
        seq = list(payload) + [FLIP, (True, 28, 5)]
        syms, labels, exp, rd_end = build(seq, rd)
    assert rd_end == rd, "frame not RD-balanced"
    return syms, labels, exp

def analyse(words, n, labels, exp, show=True):
    """Find the periodic pattern (period n) by locating the K28.5 label position and tabulate per position."""
    k_pos = [i for i, l in enumerate(labels) if l.startswith("K28.5")]
    per = [Counter() for _ in range(n)]
    total_err = sum(w["err"] for w in words); total_align0 = sum(1 - w["align"] for w in words)
    # phase: first word that is K28.5 (k=1, data=0xBC) with err=0
    start = next((i for i, w in enumerate(words) if w["k"] and w["data"] == 0xBC), None)
    if start is None:
        print(f"    no K28.5 found in capture: err={total_err} align0={total_align0} first words: {words[:4]}")
        return None
    phase = (start - k_pos[0]) % n if k_pos else start % n
    for i in range(start, len(words)):
        p = (i - phase) % n
        w = words[i]; per[p][(w["k"], w["data"], w["b9"], w["err"], w["align"])] += 1
    rows = []
    for p in range(n):
        top = per[p].most_common(2)
        (k, d, b9, err, al), cnt = top[0]
        e = exp[p]; ok = "" if e is None else ("ok" if (k, d) == e else "MISMATCH")
        rows.append((p, labels[p], k, d, b9, err, al, cnt, sum(per[p].values()), ok, top[1] if len(top) > 1 else None))
    if show:
        print(f"    {'pos':>3} {'sent':<10} {'K':>1} {'data':>4} {'b9':>2} {'err':>3} {'al':>2} {'count/total':>12}  note")
        for p, lab, k, d, b9, err, al, cnt, tot, ok, alt in rows:
            alt_s = f"  alt {alt[0]}x{alt[1]}" if alt else ""
            print(f"    {p:>3} {lab:<10} {k:>1} 0x{d:02x} {b9:>2} {err:>3} {al:>2} {cnt:>5}/{tot:<6} {ok}{alt_s}")
        print(f"    capture: {len(words)} words, err total {total_err}, align=0 words {total_align0}")
    return rows

def run_test(pr, title, syms, labels, exp, settle=0.05):
    print(f"\n=== {title} ({len(syms)} symbols)")
    pr.inject(syms, 2); time.sleep(settle)
    pr.diag(); time.sleep(0.05); d = pr.diag()
    print(f"    'L' in 50ms: status 0x{d['status']:02x} commas {d['commas']} errors {d['errors']}")
    words = pr.capture()
    return analyse(words, len(syms), labels, exp)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8081")
    ap.add_argument("--tests", default="0,1,2,3,4,5,6,7")
    a = ap.parse_args()
    pr = Probe(a.url); tests = set(a.tests.split(","))
    pr.raw_mode(True)
    D = lambda x, y: (False, x, y)
    payload15 = [D(i, 0) for i in range(15)]

    if "0" in tests:
        print("\n=== T0 core stream, raw capture (injector off)")
        pr.inject_stop(); time.sleep(0.05); d = pr.diag(); time.sleep(0.05); d = pr.diag()
        print(f"    'L': status 0x{d['status']:02x} commas {d['commas']} records {d['records']} errors {d['errors']}")
        w = pr.capture()
        print(f"    words {len(w)}: K {sum(x['k'] for x in w)}, b9=1 {sum(x['b9'] for x in w)}, err {sum(x['err'] for x in w)}, align0 {sum(1-x['align'] for x in w)}")
        print("    b9 by symbol (k,data):", Counter((x['k'], x['data']) for x in w if x['b9']).most_common(8))
    if "1" in tests:
        s, l, e = balanced_frame(payload15)
        rows = run_test(pr, "T1 baseline: D0.0..D14.0 + K28.5, correct running disparity", s, l, e)
        if rows:
            print("    b9 vs symbol disparity / RD:")
            rd = -1
            for (p, lab, k, d, b9, err, al, *_), sym in zip(rows, s):
                bits = to_bits(sym); print(f"      {lab:<8} {bits} disp {disp(bits):+d} rd_before {rd:+d} rd_after {rd_after(bits, rd):+d}  b9={b9}"); rd = rd_after(bits, rd)
    if "2" in tests:
        for x, why in ((0, "D0.0: 6b 100111/011000 = +2/-2, wrong form = real RD violation"),
                       (7, "D7.0: both forms neutral (111000/000111), wrong form = no RD violation (control)")):
            seq = [D(i, 1) for i in range(15)]
            seq[5] = {"k": False, "x": x, "y": 1, "rd_form": 1}     # sent in its RD+ form while RD is -
            s, l, e, rd_end = build(seq, -1)
            while rd_end != -1: seq.append(FLIP); s, l, e, rd_end = build(seq, -1)
            s, l, e, rd_end = build(seq + [(True, 28, 5)], -1)
            if rd_end != -1: s, l, e, rd_end = build(seq + [FLIP, (True, 28, 5)], -1)
            run_test(pr, f"T2 {why}", s, l, e)
    if "3" in tests:
        bad = [("raw", "0000000000", "all0"), ("raw", "1111111111", "all1"), ("raw", "0000001011", "6b=000000"),
               ("raw", "1111110100", "6b=111111"), ("raw", "1001110000", "4b=0000"), ("raw", "0110001111", "4b=1111")]
        seq = []
        for i, b in enumerate(bad):
            seq += [D(i, 1), b, D(i + 8, 1)]
        s, l, e, rd_end = build(seq, -1)
        # close the loop RD-neutral: add D symbols until back to -1, then K28.5
        while rd_end != -1:
            seq.append(FLIP); s, l, e, rd_end = build(seq, -1)
        s, l, e, rd_end = build(seq + [(True, 28, 5)], -1)
        if rd_end != -1: s, l, e, rd_end = build(seq + [FLIP, (True, 28, 5)], -1)
        run_test(pr, "T3 invalid code groups (each between valid D symbols)", s, l, e)
    if "4" in tests:
        ks = [(28, y) for y in range(8)] + [(23, 7), (27, 7), (29, 7), (30, 7)]
        seq = []
        for x, y in ks: seq += [(True, x, y), D(x, 1)]          # each K followed by a D (comma-like Ks kept apart by data)
        s, l, e, rd_end = build(seq, -1)
        while rd_end != -1: seq.append(FLIP); s, l, e, rd_end = build(seq, -1)
        run_test(pr, "T4 all 12 K codes (RD form as running disparity dictates)", s, l, e)
        seq2 = []
        for x, y in ks: seq2 += [{"k": True, "x": x, "y": y, "rd_form": 1}, D(x, 1)]   # forced RD+ form regardless of RD
        s, l, e, rd_end = build(seq2, -1)
        while rd_end != -1: seq2.append(FLIP); s, l, e, rd_end = build(seq2, -1)
        run_test(pr, "T4b all 12 K codes forced to their RD+ form", s, l, e)
    if "5" in tests:
        seq = [D(17, 7), D(3, 7), {"k": False, "x": 3, "y": 7, "a7": True}, D(11, 7), {"k": False, "x": 11, "y": 7, "a7": False}, D(20, 7)]
        s, l, e, rd_end = build(seq, -1)
        while rd_end != -1: seq.append(FLIP); s, l, e, rd_end = build(seq, -1)
        s, l, e, rd_end = build(seq + [(True, 28, 5)], -1)
        if rd_end != -1: s, l, e, rd_end = build(seq + [FLIP, (True, 28, 5)], -1)
        run_test(pr, "T5 D.x.7 alternate (A7) forms: mandated, forced on D3.7, forced off D11.7", s, l, e)
    if "6" in tests:
        s0, l0, e0 = balanced_frame(payload15)
        stream = "".join(to_bits(x) for x in s0)
        for shift in (1, 3, 5, 9):
            rot = stream[shift:] + stream[:shift]
            s = [to_int(rot[i*10:(i+1)*10]) for i in range(len(s0))]
            print(f"\n=== T6 same bit stream rotated by {shift} bits (comma moves inside the symbol boundary)")
            pr.inject(s, 2); t0 = time.time(); pr.diag(); hist = []
            while time.time() - t0 < 3.0:
                time.sleep(0.05); d = pr.diag()
                hist.append((round(time.time() - t0, 2), (d['status'] >> 1) & 1, d['commas'], d['errors']))
                if d['commas'] > 1000 and d['errors'] == 0 and len(hist) > 2: break
            print("    (t, align, commas/50ms, errors/50ms):", hist[:3], "...", hist[-2:])
            w = pr.capture()
            print(f"    after {hist[-1][0]}s: words {len(w)}: K28.5 seen {sum(1 for x in w if x['k'] and x['data']==0xBC)}, err {sum(x['err'] for x in w)}, align0 {sum(1-x['align'] for x in w)}")
            analyse(w, len(s0), l0, e0, show=(shift == 1))
            pr.inject_stop(); time.sleep(0.3)      # back to the core stream (original phase) before the next shift
            d = pr.diag(); time.sleep(0.05); d = pr.diag()
            print(f"    core stream restored: align={(d['status']>>1)&1} commas {d['commas']} errors {d['errors']}")
    if "7" in tests:
        seq = [D(i, i % 8) for i in range(32)]
        s, l, e, rd_end = build(seq, -1)
        while rd_end != -1: seq.append(FLIP); s, l, e, rd_end = build(seq, -1)
        s, l, e, rd_end = build(seq + [(True, 28, 5)], -1)
        if rd_end != -1: s, l, e, rd_end = build(seq + [FLIP, (True, 28, 5)], -1)
        rows = run_test(pr, "T7 bit 9 survey over 32 D symbols", s, l, e)
        if rows:
            rd = -1
            for (p, lab, k, d, b9, err, al, *_), sym in zip(rows, s):
                bits = to_bits(sym); print(f"      {lab:<8} {bits} disp {disp(bits):+d} rd_before {rd:+d}  b9={b9}"); rd = rd_after(bits, rd)
    pr.inject_stop(); pr.raw_mode(False)
    print("\ndone (injector stopped, raw mode off)")

if __name__ == "__main__":
    main()
