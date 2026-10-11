#!/usr/bin/env python3
"""Status of the SLogic16U3 USB 2.0 bring-up design over JTAG (ER1, read-only, 128 bits).

Uses the CMSIS-DAP / FT2232 JTAG layer of ../../slogic16u3_probe/host/slogic_probe.py.
    usb2_status.py            one line
    usb2_status.py -w         a line on every change (Ctrl-C to stop)
"""
import argparse, os, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'slogic16u3_probe', 'host'))
import slogic_probe as sp  # noqa: E402

OSC_HZ = 51.66e6   # internal oscillator, calibrated against the host clock (2026-10-11)
MAGIC = 0x5B20


class Args:
    sim = None
    cable = 'dap'
    serial = None
    freq = 1e6
    any_device = False


def read_status(j):
    j.ir(0x42)
    raw = j.dr(128 + 8)
    for off in range(8):   # TDO leads by a bit or so (as ER1 of the probe design)
        v = raw >> off
        if v & 0xFFFF == MAGIC:
            break
    else:
        raise SystemExit(f'status magic not found (0x{raw & 0xFFFFFF:06x}): is the usb2 bitstream loaded?')
    b = lambda i: (v >> i) & 1
    return {
        'run': b(16), 'pll': b(17), 'sd_pll': b(18), 'sd_ready': b(19),
        'configured': b(20), 'hs': b(21), 'suspended': b(22), 'busreset_seen': b(23),
        'linestate': (v >> 24) & 3, 'rxact_seen': b(26), 'txoe_seen': b(27),
        'address': (v >> 28) & 0x7F, 'frame': (v >> 35) & 0x7FF,
        'pads': (v >> 46) & 0x3F,
        'sof': (v >> 64) & 0xFFFF, 'err': (v >> 80) & 0xFF, 'resets': (v >> 88) & 0xFF,
        'f60': ((v >> 96) & 0xFFFFF) * 16 * OSC_HZ / (1 << 22),
    }


def fmt(s):
    ls = {0: 'SE0', 1: 'J', 2: 'K', 3: 'SE1'}[s['linestate']]
    return (f"run={s['run']} pll={s['pll']} clk60={s['f60'] / 1e6:7.3f}MHz line={ls:3s} "
            f"busreset={s['busreset_seen']}({s['resets']}) rx={s['rxact_seen']} tx={s['txoe_seen']} "
            f"addr={s['address']:3d} cfg={s['configured']} susp={s['suspended']} hs={s['hs']} "
            f"frame={s['frame']:4d} sof={s['sof']:5d} err={s['err']} "
            f"pads(dx+,dx-,t+,t-,c+,c-)={''.join(str(s['pads'] >> i & 1) for i in range(6))}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-w', '--watch', action='store_true')
    ap.add_argument('-i', '--interval', type=float, default=0.2)
    a = ap.parse_args()
    j = sp.open_jtag(Args())
    last = None
    try:
        while True:
            s = read_status(j)
            line = fmt({**s, 'sof': 0, 'frame': 0} if a.watch else s)   # watch: ignore the counters for "changed"
            if not a.watch:
                print(fmt(s))
                break
            if line != last:
                print(time.strftime('%H:%M:%S'), fmt(s), flush=True)
                last = line
            time.sleep(a.interval)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
