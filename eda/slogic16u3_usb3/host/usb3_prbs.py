#!/usr/bin/env python3
"""EP1 IN throughput / integrity test of the SLogic16U3 USB 3.0 device: switches EP1 IN to the PRBS15
source (vendor request 0x02, register value 0x0001), reads for a while and checks every byte against the
PRBS15 sequence (x^15 + x^14 + 1, 8 bits per byte, first bit in bit 0; the byte stream repeats
every 32767 bytes, so the check is a compare against a tiled table once the phase is found).

    usb3_prbs.py [-s SECONDS] [-b BLOCK]
"""
import argparse, time
import usb.core


def prbs15_table():
    s = 0x7FFF
    bits = []
    for _ in range(32767 * 8):
        b = ((s >> 14) ^ (s >> 13)) & 1
        bits.append(b)
        s = ((s << 1) | b) & 0x7FFF
    out = bytearray(32767)
    for i in range(32767):
        v = 0
        for k in range(8):
            v |= bits[i * 8 + k] << k
        out[i] = v
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-s', '--seconds', type=float, default=5.0)
    ap.add_argument('-b', '--block', type=int, default=1 << 20, help='bytes per read request')
    a = ap.parse_args()
    tab = prbs15_table()
    tab2 = tab * ((a.block // len(tab)) + 3)
    dev = usb.core.find(idVendor=0x1209, idProduct=0x0001)
    if dev is None:
        raise SystemExit('device not found')
    dev.set_configuration()
    dev.ctrl_transfer(0x40, 0x02, 0x0000, 0, b'')        # loopback mode, then drain what is left
    try:
        while True:
            dev.read(0x81, 1 << 16, timeout=50)
    except usb.core.USBError:
        pass
    dev.ctrl_transfer(0x40, 0x02, 0x0001, 0, b'')        # PRBS mode (restarts the sequence)
    total, errs, phase = 0, 0, None
    t0 = time.time()
    first_err = None
    while time.time() - t0 < a.seconds:
        d = bytes(dev.read(0x81, a.block, timeout=2000))
        if phase is None:
            # (the sequence is cyclic: search across the wrap; the first bytes after the mode switch
            # may be left over from before it, so up to 8 are skipped)
            for skip in range(8):
                phase = (tab + tab[:64]).find(d[skip:skip + 32])
                if phase >= 0:
                    break
            if phase < 0:
                raise SystemExit(f'PRBS phase not found in the first bytes: {d[:16].hex()}')
            d = d[skip:]
        ref = tab2[phase:phase + len(d)]
        if d != ref:
            n = sum(1 for x, y in zip(d, ref) if x != y)
            errs += n
            if first_err is None:
                i = next(i for i in range(len(d)) if d[i] != ref[i])
                first_err = (total + i, d[i:i + 8].hex(), ref[i:i + 8].hex())
            phase = (tab + tab[:64]).find(d[-32:])   # re-sync after an error
            phase = (phase + 32) % len(tab) if phase >= 0 else 0
        else:
            phase = (phase + len(d)) % len(tab)
        total += len(d)
    dt = time.time() - t0
    dev.ctrl_transfer(0x40, 0x02, 0x0000, 0, b'')
    print(f'{total / 1e6:.1f} MB in {dt:.2f} s = {total / dt / 1e6:.1f} MB/s, byte errors {errs}'
          + (f', first at {first_err[0]}: got {first_err[1]} exp {first_err[2]}' if first_err else ''))


if __name__ == '__main__':
    main()
