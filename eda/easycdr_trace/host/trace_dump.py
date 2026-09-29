#!/usr/bin/env python3
"""EasyCDR trace-link phase 2 host tool.

Arms the capture buffer, waits for it to fill, dumps it (UART, serial_bridge
or USB, see trace_transport.py) and verifies that the payload is the
expected consecutive-counter stream.

Usage: trace_dump.py [-p PORT | --usb | --url URL] [-b BAUD] [-o FILE]
"""
import argparse
import sys
import trace_transport as tt

BUF_SIZE = 16384

def main():
    ap = argparse.ArgumentParser()
    tt.add_args(ap, default="serial")
    ap.add_argument("-o", "--output", help="save raw dump to file")
    args = ap.parse_args()
    T = tt.from_args(args)
    T.flush()

    print("arming capture ('S')...")
    r = T.xfer({"write": [0x53], "read": 1, "timeout_ms": 5000})
    if r["data"] != [0x4B]:
        sys.exit(f"no 'K' ack (got {bytes(r['data'])!r}) - is the link locked?")
    print("capture complete ('K' received)")

    print(f"dumping {BUF_SIZE} bytes ('D')...")
    r = T.xfer({"write": [0x44], "read": BUF_SIZE, "timeout_ms": 20000})
    data = bytes(r["data"])
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
