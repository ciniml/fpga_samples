#!/usr/bin/env python3
"""EasyCDR trace-link host tool: triggered / pre-trigger capture viewer.

Records on the link: [K28.1][ts LSB..][data LSB..]. The host FPGA stores
{K flag, byte} entries in a ring buffer and dumps them oldest-first.

Examples:
  trace_view.py -p /dev/ttyUSB2                         # immediate capture
  trace_view.py -p /dev/ttyUSB2 --trigger 0x00ff 0x0042 --post 4096
      # wait until (data & 0x00ff) == 0x42, keep 4096 entries after it
      # (the rest of the buffer holds the pre-trigger history)
"""
import argparse
import sys
import serial

K28_1 = 0x3C
K28_2 = 0x5C

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("--width", type=int, default=16, help="trace width (bits)")
    ap.add_argument("--ts-bits", type=int, default=24)
    ap.add_argument("--addr-bits", type=int, default=14, help="buffer entries = 2^n")
    ap.add_argument("--trigger", nargs=2, metavar=("MASK", "VALUE"),
                    help="trigger on (data & MASK) == VALUE (hex ok)")
    ap.add_argument("--post", type=int, default=None,
                    help="entries to keep after the trigger (default: half)")
    ap.add_argument("-n", "--show", type=int, default=20)
    ap.add_argument("-o", "--output", help="save decoded records to CSV")
    args = ap.parse_args()

    entries = 1 << args.addr_bits
    db = args.width // 8
    tb = args.ts_bits // 8

    with serial.Serial(args.port, args.baud, timeout=30) as ser:
        ser.reset_input_buffer()
        if args.trigger:
            mask = int(args.trigger[0], 0)
            value = int(args.trigger[1], 0)
            post = args.post if args.post is not None else entries // 2
            ser.write(b"T" + mask.to_bytes(db, "little") + value.to_bytes(db, "little"))
            ser.write(b"A" + post.to_bytes(2, "big"))
            print(f"armed: trigger (data & 0x{mask:0{db*2}x}) == 0x{value:0{db*2}x}, "
                  f"post={post} entries; waiting...")
        else:
            ser.write(b"S")
            print("armed: immediate capture; waiting...")
        ack = ser.read(1)
        if ack != b"K":
            sys.exit(f"no 'K' ack (got {ack!r}) - link locked? trigger reachable?")
        print("capture frozen, dumping...")
        ser.write(b"D")
        raw = ser.read(entries * 2)
        if len(raw) != entries * 2:
            sys.exit(f"short read: {len(raw)}/{entries*2} bytes")

    ents = [(raw[2*i] & 1, raw[2*i+1]) for i in range(entries)]
    rec_len = tb + db
    records, overflows, junk = [], 0, 0
    i = 0
    while i < len(ents):
        k, b = ents[i]
        if k and b == K28_2:
            overflows += 1; i += 1
        elif k and b == K28_1 and i + rec_len < len(ents) and \
                not any(kk for kk, _ in ents[i+1:i+1+rec_len]):
            body = [bb for _, bb in ents[i+1:i+1+rec_len]]
            ts = int.from_bytes(bytes(body[:tb]), "little")
            data = int.from_bytes(bytes(body[tb:]), "little")
            records.append((ts, data)); i += 1 + rec_len
        else:
            junk += 1; i += 1

    trig_idx = None
    if args.trigger:
        for n, (ts, data) in enumerate(records):
            if (data & mask) == (value & mask):
                trig_idx = n; break
    print(f"{len(records)} records, {overflows} overflow markers, {junk} skipped entries"
          + (f", first trigger match at record #{trig_idx}" if trig_idx is not None else ""))

    lo = 0 if trig_idx is None else max(0, trig_idx - args.show // 2)
    prev = None
    for n in range(lo, min(len(records), lo + args.show)):
        ts, data = records[n]
        dt = "" if prev is None else f"(+{((ts - prev) & ((1 << args.ts_bits) - 1)) * 10}ns)"
        mark = " <-- trigger" if n == trig_idx else ""
        print(f"  #{n:<5d} ts={ts*10:>11}ns {dt:>16}  data=0x{data:0{db*2}x}{mark}")
        prev = ts

    if args.output:
        with open(args.output, "w") as f:
            f.write("index,timestamp_ns,data\n")
            for n, (ts, data) in enumerate(records):
                f.write(f"{n},{ts*10},{data}\n")
        print(f"saved {len(records)} records to {args.output}")

if __name__ == "__main__":
    main()
