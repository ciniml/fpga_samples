#!/usr/bin/env python3
"""Status of the SLogic16U3 logic analyzer bitstream (src/slogic16u3/top.v) over JTAG ER1 (152 bits):
the clocks (pclk 125 MHz, sample clock 100 MHz), the USB 3.0 link and the stream words sent.

    la_status.py
"""
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'slogic16u3_probe', 'host'))
import slogic_probe as sp  # noqa: E402

OSC_HZ = 51.66e6
MAGIC = 0x5B4C
L = 152


class Args:
    sim = None
    cable = 'dap'
    serial = None
    freq = 1e6
    any_device = False


def read(j):
    j.ir(0x42)
    raw = j.dr(L + 8)
    for off in range(8):
        v = raw >> off
        if v & 0xFFFF == MAGIC:
            break
    else:
        raise SystemExit(f'magic not found (0x{raw & 0xFFFFFF:06x}): is the logic analyzer bitstream loaded?')
    f = lambda lo, w: (v >> lo) & ((1 << w) - 1)
    return {
        'pclk': f(16, 20) * 16 * OSC_HZ / (1 << 22), 'sclk': f(36, 20) * 16 * OSC_HZ / (1 << 22),
        's_lock': f(59, 1), 'srst': f(60, 1), 'prst': f(61, 1), 'link_cfg': f(62, 1), 'in_u0': f(63, 1),
        'addr': f(64, 7), 'ltssm': f(72, 5), 'u0': f(80, 16), 'resets': f(96, 16),
        'dev_cfg': f(112, 1), 'capturing': f(113, 1), 'words': f(120, 32),
    }


def main():
    j = sp.open_jtag(Args())
    s = read(j)
    print(f"pclk {s['pclk'] / 1e6:.2f} MHz, sample clock {s['sclk'] / 1e6:.2f} MHz (PLL lock {s['s_lock']}, "
          f"sclk reset {s['srst']}), pclk reset {s['prst']}")
    print(f"USB: U0 {s['in_u0']} LTSSM {s['ltssm']} link cfg {s['link_cfg']} device cfg {s['dev_cfg']} "
          f"addr {s['addr']} | U0 entries {s['u0']} resets {s['resets']}")
    print(f"capturing {s['capturing']}, stream words sent {s['words']}")


if __name__ == '__main__':
    main()
