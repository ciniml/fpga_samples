#!/usr/bin/env python3
"""Status of the SLogic16U3 USB 3.0 device (top.v) over JTAG ER1 (read-only, 384 bits).

    usb3_status.py            one snapshot (with the last 16 LTSSM states)
    usb3_status.py -w         a line on every change of the state / counters
"""
import argparse, os, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'slogic16u3_probe', 'host'))
import slogic_probe as sp  # noqa: E402

OSC_HZ = 51.66e6
MAGIC = 0x5B31
STATES = ['PhyWait', 'Disabled', 'Inactive', 'RxDetReset', 'RxDetActive', 'RxDetQuiet', 'PollLfps', 'PollRxEq',
          'PollActive', 'PollConfig', 'PollIdle', 'U0', 'U3', 'U3Wake', 'RecActive', 'RecConfig', 'RecIdle',
          'HotRstActive', 'HotRstExit']


class Args:
    sim = None
    cable = 'dap'
    serial = None
    freq = 1e6
    any_device = False


def st(n):
    return STATES[n] if n < len(STATES) else f'?{n}'


def read(j):
    j.ir(0x42)
    raw = j.dr(680 + 8)
    for off in range(8):
        v = raw >> off
        if v & 0xFFFF == MAGIC:
            break
    else:
        raise SystemExit(f'magic not found (0x{raw & 0xFFFFFF:06x}): is the usb3 bitstream loaded?')
    f = lambda lo, w: (v >> lo) & ((1 << w) - 1)
    return {
        'ref_lock': f(16, 1), 'phy_resetn': f(17, 1), 'pads': f(18, 6),
        'pclk': f(24, 20) * 16 * OSC_HZ / (1 << 22),
        'prst': f(44, 1), 'in_u0': f(45, 1), 'link_cfg': f(46, 1), 'dev_cfg': f(47, 1),
        'rx_valid': f(48, 1), 'rx_pol': f(49, 1), 'rx_term': f(50, 1), 'tx_detrx': f(51, 1), 'tx_eidle': f(52, 1),
        'pd': f(53, 2), 'state': f(56, 5), 'st_max': f(64, 5),
        'rx_status': f(72, 3), 'phy_status': f(75, 1), 'rx_eidle': f(76, 1), 'power_present': f(77, 1),
        'addr': f(80, 7), 'trans': f(88, 8), 'vreg': f(96, 16),
        'u0': f(112, 16), 'hp': f(128, 16), 'resets': f(144, 16), 'dpp_err': f(160, 16), 'physt': f(176, 16),
        'lfps': f(192, 16), 'seen': f(208, 32), 'trace': [f(240 + 5 * i, 5) for i in range(16)],
        'bytes': f(320, 32), 'up': f(352, 32) * 65536 / OSC_HZ,
        'centry': f(384, 40), 'cidx': f(424, 6), 'cfull': f(430, 1),
        'ps': [f(480 + 24 * i, 24) for i in range(8)], 'cwp': f(674, 6),
        'com': f(432, 16), 'dec_err': f(448, 16), 'disp_err': f(464, 16),
    }


def fmt(s):
    return (f"{st(s['state']):12s} max={st(s['st_max']):10s} u0={s['in_u0']} link_cfg={s['link_cfg']} dev_cfg={s['dev_cfg']} "
            f"addr={s['addr']:3d} pd=P{s['pd']} txEI={s['tx_eidle']} detRx={s['tx_detrx']} rxEI={s['rx_eidle']} "
            f"rxSt={s['rx_status']} | u0#={s['u0']} hp={s['hp']} rst={s['resets']} dppErr={s['dpp_err']} "
            f"lfps={s['lfps']} trans={s['trans']} bytes={s['bytes']}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-w', '--watch', action='store_true')
    ap.add_argument('-i', '--interval', type=float, default=0.1)
    ap.add_argument('-c', '--capture', action='store_true', help='dump the 64-word PIPE receive capture')
    a = ap.parse_args()
    j = sp.open_jtag(Args())
    s = read(j)
    print(f"uptime {s['up']:.1f} s  ref_lock={s['ref_lock']} phy_resetn={s['phy_resetn']} prst={s['prst']} "
          f"pclk={s['pclk'] / 1e6:.3f} MHz power_present={s['power_present']} phy_status#={s['physt']} "
          f"usb2 pads(dx+,dx-,t+,t-,c+,c-)={''.join(str(s['pads'] >> i & 1) for i in range(6))}")
    print('seen:', ' '.join(st(i) for i in range(32) if s['seen'] >> i & 1))
    print('trace (old -> new):', ' > '.join(st(x) for x in reversed(s['trace'])))
    print(fmt(s))
    for name, b in (('Polling.RxEQ', 0), ('Polling.Active', 4)):
        c = s['ps'][b:b + 4]
        print(f"{name:15s} cycles={c[0]:8d} RxValid={c[1]:8d} RxElecIdle={c[2]:8d} COM={c[3]:8d}")
    print(f"rx: COM={s['com']} decode_err={s['dec_err']} disparity_err={s['disp_err']} capture_full={s['cfull']}")
    if a.capture:
        buf = {}
        t0 = time.time()
        while len(buf) < 64 and time.time() - t0 < 10:
            c = read(j)
            buf[c['cidx']] = c['centry']
        print(f"(oldest entry {c['cwp']}; listed oldest first)")
        for n in range(64):
            i = (c['cwp'] + n) % 64
            e = buf.get(i)
            if e is None:
                print(f'{n - 8:+3d} ?'); continue
            d, k, vld, rst = e & 0xFFFFFFFF, (e >> 32) & 0xF, (e >> 36) & 1, (e >> 37) & 7
            syms = ' '.join(('K' if k >> b & 1 else ' ') + f'{(d >> 8 * b) & 0xFF:02x}' for b in range(4))
            print(f'{n - 8:+3d} v={vld} st={rst} {syms}')
    if not a.watch:
        return
    last = None
    try:
        while True:
            s = read(j)
            key = fmt({**s, 'lfps': 0, 'trans': 0})
            if key != last:
                print(time.strftime('%H:%M:%S'), fmt(s), flush=True)
                last = key
            time.sleep(a.interval)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
