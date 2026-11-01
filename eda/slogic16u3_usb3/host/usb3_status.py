#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
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
    raw = j.dr(496 + 8)
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
        'com': f(384, 16), 'dec_err': f(400, 16), 'disp_err': f(416, 16), 'dbg': f(432, 16), 'nrdy': f(448, 16), 'ovf': f(464, 16), 'bl_max': f(480, 13),
        # Tang Console build: SerDes lane debug in the spare bits
        'cmu_ok': f(79, 1), 'rx_lock': f(78, 1), 'lane_rstn': f(71, 1), 'lane_stat': f(69, 2) | (f(61, 3) << 2) | (f(55, 1) << 5),
    }


def fmt(s):
    return (f"{st(s['state']):12s} max={st(s['st_max']):10s} u0={s['in_u0']} link_cfg={s['link_cfg']} dev_cfg={s['dev_cfg']} "
            f"addr={s['addr']:3d} pd=P{s['pd']} txEI={s['tx_eidle']} detRx={s['tx_detrx']} rxEI={s['rx_eidle']} "
            f"rxSt={s['rx_status']} | u0#={s['u0']} hp={s['hp']} rst={s['resets']} dppErr={s['dpp_err']} "
            f"lfps={s['lfps']} trans={s['trans']} bytes={s['bytes']}")


def main():
    global OSC_HZ
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-w', '--watch', action='store_true')
    ap.add_argument('-i', '--interval', type=float, default=0.1)
    ap.add_argument('--cable', choices=['dap', 'ftdi'], default='dap', help='JTAG cable: dap (rust-dap, SLogic16U3) or ftdi (Sipeed USB debugger, Tang Console)')
    ap.add_argument('--osc-hz', type=float, default=OSC_HZ, help='clock of the status block (SLogic: ~51.66 MHz oscillator, Console: 50 MHz sys_clk)')
    ap.add_argument('--upar', action='store_true', help='decode the Tang Console UPAR diagnostic build (TAG=upar)')
    ap.add_argument('--two', action='store_true', help='decode the Tang Console two-lane cable self-test build (LANE=2ln FORCE_TX=1)')
    ap.add_argument('--det', action='store_true', help='decode the Tang Console receiver-detect test build (FORCE_DET=1)')
    ap.add_argument('--lfps', action='store_true', help='decode the Tang Console LFPS diagnostic build (LFPS_DIAG=1)')
    ap.add_argument('--serial', help='probe serial number when several are connected (lsusb -v / pyusb)')
    a = ap.parse_args()
    ap_serial = a.serial
    Args.cable = a.cable
    Args.serial = a.serial
    Args.any_device = a.cable == 'ftdi'   # the Console is a GW5AT-60
    OSC_HZ = a.osc_hz
    j = sp.open_jtag(Args())
    s = read(j)
    print(f"uptime {s['up']:.1f} s  ref_lock={s['ref_lock']} phy_resetn={s['phy_resetn']} prst={s['prst']} "
          f"pclk={s['pclk'] / 1e6:.3f} MHz power_present={s['power_present']} phy_status#={s['physt']} "
          f"usb2 pads(dx+,dx-,t+,t-,c+,c-)={''.join(str(s['pads'] >> i & 1) for i in range(6))}")
    print('seen:', ' '.join(st(i) for i in range(32) if s['seen'] >> i & 1))
    print('trace (old -> new):', ' > '.join(st(x) for x in reversed(s['trace'])))
    print(fmt(s))
    print(f"rx: COM={s['com']} decode_err={s['dec_err']} disparity_err={s['disp_err']} | device debug events={s['dbg']} | EP1 IN NRDY={s['nrdy']} LA-FIFO model overflows={s['ovf']} max backlog={s['bl_max']} words")
    print(f"lane (Console build): rx_term={s['rx_term']} qpll_ok={s['cmu_ok']} pma_rx_lock={s['rx_lock']} rstn={s['lane_rstn']} stat[5:0]=0x{s['lane_stat']:02x} astat[5:0]=0x{s['pads']:02x}")
    if a.upar:
        b, l, v = s['bytes'], s['lfps'], s['vreg']
        print(f"upar diag: life_clk={(b & 0xFFFF) * 16 * OSC_HZ / (1 << 18) / 1e6:.3f} MHz drp_clk={(b >> 16) * 16 * OSC_HZ / (1 << 18) / 1e6:.3f} MHz "
              f"phy port2: wren#={s['dpp_err'] & 0xFF} rden#={s['dpp_err'] >> 8} ready#={l & 0xFF} rdvld#={l >> 8} ready={v >> 14 & 1} | "
              f"master: wren#={v & 0xFF} ready={v >> 15 & 1}")
    if a.two:
        v = s['vreg']
        print(f"lane 3 (port 2P): pma_rx_lock={v >> 9 & 1} rx_eidle={v >> 8 & 1} stat[3:0]=0x{v >> 10 & 0xF:x} COM={s['hp']} decode_err={s['u0']} phy_status#={s['resets']}")
    if a.det:
        v = s['vreg']
        print(f"detect test: attempts={s['u0']} answers={s['hp']} detected={s['resets']} state={v >> 10 & 3} rxdet_result={v >> 9 & 1} detrx={v >> 8 & 1}")
    if a.lfps:
        print(f"lfps diag (pclk cycles seen, saturating): PHY RxElecIdle low={s['bytes'] & 0xFFFF} quad rxelecidle_o high={s['bytes'] >> 16} sigdet_duty/1024={s['com']} astat0={s['dec_err']} astat5={s['disp_err']}")
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
