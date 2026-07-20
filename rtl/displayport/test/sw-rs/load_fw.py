#!/usr/bin/env python3
"""UART firmware loader for the DisplayPort source bring-up design.

Talks to the serial bootloader (stream_memory_access) inside
aux_ch_subsystem. Protocol, all bytes over the 115200 8N1 UART:

    5A A5 5B  A8  <addr LSB-first x4>  <len-1>  <data...>   write
    5A A5 5B  A9  <addr LSB-first x4>  <len-1>              read (replies len bytes)

The CPU is held in reset by writing 01 to address FFFF_FFFF, the ROM
image is written to 8000_0000, and the CPU is released to boot the new
firmware. Read-back is not implemented on the hardware side (a second
ROM read port would break BSRAM inference), so there is no verify pass
— the read command is parsed but replies with zeros.

Usage:
    ./load_fw.py bootrom-rs-board.bin [--port /dev/ttyUSB1] [--monitor]
"""

import argparse
import sys
import time

import serial

MAGIC = bytes([0x5A, 0xA5, 0x5B])
CMD_WRITE = 0xA8
CMD_READ = 0xA9
ROM_BASE = 0x8000_0000
RESET_REG = 0xFFFF_FFFF
CHUNK = 256


def cmd_write(ser: serial.Serial, addr: int, data: bytes) -> None:
    assert 1 <= len(data) <= 256
    frame = (
        MAGIC
        + bytes([CMD_WRITE])
        + addr.to_bytes(4, "little")
        + bytes([len(data) - 1])
        + data
    )
    ser.write(frame)


def cmd_read(ser: serial.Serial, addr: int, length: int) -> bytes:
    assert 1 <= length <= 256
    ser.reset_input_buffer()
    ser.write(MAGIC + bytes([CMD_READ]) + addr.to_bytes(4, "little") + bytes([length - 1]))
    data = ser.read(length)
    if len(data) != length:
        raise RuntimeError(
            f"read at 0x{addr:08X}: expected {length} bytes, got {len(data)}"
        )
    return data


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("image", help="firmware binary (e.g. bootrom-rs-board.bin)")
    ap.add_argument("--port", default="/dev/ttyUSB1", help="serial port")
    ap.add_argument("--baud", type=int, default=115_200)
    ap.add_argument(
        "--monitor", action="store_true", help="print UART console output after boot"
    )
    args = ap.parse_args()

    with open(args.image, "rb") as f:
        image = f.read()
    if not image:
        print("empty image", file=sys.stderr)
        return 1
    print(f"image: {args.image} ({len(image)} bytes)")

    ser = serial.Serial(args.port, args.baud, timeout=2)

    # Hold the CPU in reset; the loader now owns the UART TX.
    cmd_write(ser, RESET_REG, b"\x01")
    time.sleep(0.05)
    ser.reset_input_buffer()

    for off in range(0, len(image), CHUNK):
        chunk = image[off : off + CHUNK]
        cmd_write(ser, ROM_BASE + off, chunk)
        print(f"\rwrite {off + len(chunk)}/{len(image)}", end="", flush=True)
    print()

    # Release the CPU: it boots from the freshly written ROM.
    cmd_write(ser, RESET_REG, b"\x00")
    print("CPU released, booting new firmware")

    if args.monitor:
        print("--- console (Ctrl-C to quit) ---")
        try:
            while True:
                data = ser.read(1)
                if data:
                    sys.stdout.write(data.decode("utf-8", errors="replace"))
                    sys.stdout.flush()
        except KeyboardInterrupt:
            pass
    ser.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
