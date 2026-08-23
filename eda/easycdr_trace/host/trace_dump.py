#!/usr/bin/env python3
"""EasyCDR trace-link phase 2 host tool.

Arms the capture buffer, waits for it to fill, dumps it over UART and
verifies that the payload is the expected consecutive-counter stream.

Usage: trace_dump.py [-p PORT] [-b BAUD] [-o FILE]
"""
import argparse
import sys
import serial

BUF_SIZE = 16384

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--port", default="/dev/ttyUSB1")
    ap.add_argument("-b", "--baud", type=int, default=115200)
    ap.add_argument("-o", "--output", help="save raw dump to file")
    args = ap.parse_args()

    with serial.Serial(args.port, args.baud, timeout=5) as ser:
        ser.reset_input_buffer()

        print("arming capture ('S')...")
        ser.write(b"S")
        ack = ser.read(1)
        if ack != b"K":
            sys.exit(f"no 'K' ack (got {ack!r}) - is the link locked?")
        print("capture complete ('K' received)")

        print(f"dumping {BUF_SIZE} bytes ('D')...")
        ser.write(b"D")
        data = ser.read(BUF_SIZE)
        if len(data) != BUF_SIZE:
            sys.exit(f"short read: {len(data)}/{BUF_SIZE} bytes")

        if args.output:
            with open(args.output, "wb") as f:
                f.write(data)
            print(f"saved to {args.output}")

        errors = sum(
            1 for i in range(1, len(data))
            if data[i] != ((data[i - 1] + 1) & 0xFF)
        )
        print(f"first bytes: {data[:8].hex(' ')}")
        if errors == 0:
            print(f"OK: all {BUF_SIZE} bytes are consecutive - link clean")
        else:
            sys.exit(f"NG: {errors} discontinuities found")

if __name__ == "__main__":
    main()
