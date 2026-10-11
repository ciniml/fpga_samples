#!/usr/bin/env python3
"""Status of the REF=1 cross-check build (top_ref.v: Gowin's reference USB 3.0 controller) over JTAG ER1.

    usb3_ref_status.py [-w]
"""
import argparse, os, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'slogic16u3_probe', 'host'))
import slogic_probe as sp  # noqa: E402


class Args:
    sim = None
    cable = 'dap'
    serial = None
    freq = 1e6
    any_device = False


def read(j):
    j.ir(0x42)
    raw = j.dr(256 + 8)
    for off in range(8):
        v = raw >> off
        if v & 0xFFFF == 0x5B32:
            break
    else:
        raise SystemExit(f'magic not found (0x{raw & 0xFFFFFF:06x}): is the REF=1 bitstream loaded?')
    f = lambda lo, w: (v >> lo) & ((1 << w) - 1)
    b = 16
    return {'pwrpresent': f(b + 4, 1), 'rx_eidle': f(b + 5, 1), 'tx_detrx': f(b + 6, 1), 'tx_eidle': f(b + 7, 1),
            'pd': f(b + 8, 2), 'phy_resetn': f(b + 10, 1), 'attached': f(b + 11, 1),
            'cyc': f(b + 16, 32), 'valid': f(b + 48, 32), 'eidle': f(b + 80, 32), 'txon': f(b + 112, 32),
            'lfps_tx': f(b + 144, 32), 'com': f(b + 176, 32), 'physt': f(b + 208, 16), 'dec': f(b + 224, 16)}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('-w', '--watch', action='store_true')
    ap.add_argument('-i', '--interval', type=float, default=1.0)
    a = ap.parse_args()
    j = sp.open_jtag(Args())
    prev = None
    while True:
        s = read(j)
        if prev:
            d = {k: (s[k] - prev[k]) & 0xFFFFFFFF for k in ('cyc', 'valid', 'eidle', 'txon', 'lfps_tx', 'com')}
            c = d['cyc'] or 1
            print(time.strftime('%H:%M:%S'),
                  f"attached={s['attached']} pd=P{s['pd']} txEI={s['tx_eidle']} rxEI={s['rx_eidle']} | "
                  f"RxValid {100 * d['valid'] / c:5.1f}%  RxElecIdle {100 * d['eidle'] / c:5.1f}%  "
                  f"TX on {100 * d['txon'] / c:5.1f}%  LFPS tx {100 * d['lfps_tx'] / c:5.1f}%  COM {d['com']}  "
                  f"dec_err {s['dec']} phystatus {s['physt']}", flush=True)
            if not a.watch:
                break
        prev = s
        time.sleep(a.interval)


if __name__ == '__main__':
    main()
