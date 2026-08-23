#!/usr/bin/env python3
"""EasyCDR trace-link phase 3 host tool.

Arms the capture, dumps the 9-bit entry buffer and decodes the timestamped
trace records:

  [K28.1][ts 7:0][ts 15:8][ts 23:16][data 7:0][data 15:8]

Timestamps count 100MHz link-clock cycles (10ns). data[7:0] is the demo
counter, data[8] is the raw UART RX line.
"""
import argparse
import sys
import serial

ENTRIES = 16384
K28_1 = 0x3C
K28_2 = 0x5C

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("-n", "--show", type=int, default=20,
                    help="number of records to print")
    ap.add_argument("-o", "--output", help="save decoded records to CSV")
    args = ap.parse_args()

    with serial.Serial(args.port, args.baud, timeout=10) as ser:
        ser.reset_input_buffer()
        print("arming capture ('S')... (fills in ~7ms of link time)")
        ser.write(b"S")
        ack = ser.read(1)
        if ack != b"K":
            sys.exit(f"no 'K' ack (got {ack!r}) - is the link locked?")
        print("capture complete, dumping...")
        ser.write(b"D")
        raw = ser.read(ENTRIES * 2)
        if len(raw) != ENTRIES * 2:
            sys.exit(f"short read: {len(raw)}/{ENTRIES*2} bytes")

    entries = [(raw[2*i] & 1, raw[2*i+1]) for i in range(ENTRIES)]

    records = []
    overflows = 0
    junk = 0
    i = 0
    while i < len(entries):
        k, b = entries[i]
        if k and b == K28_2:
            overflows += 1
            i += 1
        elif k and b == K28_1 and i + 5 < len(entries):
            body = entries[i+1:i+6]
            if any(kk for kk, _ in body):
                junk += 1
                i += 1
                continue
            ts = body[0][1] | body[1][1] << 8 | body[2][1] << 16
            data = body[3][1] | body[4][1] << 8
            records.append((ts, data))
            i += 6
        else:
            junk += 1   # partial record at the start of the buffer etc.
            i += 1

    print(f"{len(records)} records, {overflows} overflow markers, "
          f"{junk} skipped entries")
    prev_ts = None
    for ts, data in records[:args.show]:
        dt = "" if prev_ts is None else f" (+{((ts - prev_ts) & 0xFFFFFF)*10}ns)"
        print(f"  ts={ts*10:>10}ns{dt:>16}  counter=0x{data & 0xFF:02x}  "
              f"uart_rx={data >> 8 & 1}")
        prev_ts = ts

    if args.output:
        with open(args.output, "w") as f:
            f.write("timestamp_ns,counter,uart_rx\n")
            for ts, data in records:
                f.write(f"{ts*10},{data & 0xFF},{data >> 8 & 1}\n")
        print(f"saved {len(records)} records to {args.output}")

if __name__ == "__main__":
    main()
