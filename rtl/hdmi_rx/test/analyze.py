#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
"""In-band SNR of the delta-sigma bit stream written by tb_hdmi_audio.

The DAC updates at f_pclk / 12 (74.25 MHz pixel clock -> 6.1875 MHz); the
tone is 1 kHz. Pass: tone found at 1 kHz and 20 Hz - 20 kHz SNR >= 80 dB.
"""
import sys
import numpy as np

FM = 74.25e6 / 12
F0 = 1000.0
MIN_SNR = 80.0

y = np.loadtxt(sys.argv[1], dtype=np.int8) * 2.0 - 1.0
n = len(y)
k = np.arange(n)
a = [0.35875, 0.48829, 0.14128, 0.01168]    # 4-term Blackman-Harris
w = a[0] - a[1] * np.cos(2 * np.pi * k / n) + a[2] * np.cos(4 * np.pi * k / n) - a[3] * np.cos(6 * np.pi * k / n)
p = np.abs(np.fft.rfft((y - y.mean()) * w)) ** 2
f = np.fft.rfftfreq(n, 1 / FM)
band = (f > 20) & (f < 20000)
kb = np.argmax(np.where(band, p, 0))
sig = p[kb - 10:kb + 11].sum()
snr = 10 * np.log10(sig / (p[band].sum() - sig))
# signal level relative to a full-scale (+-1) square wave's fundamental
print(f"[analyze] {n} bits: tone {f[kb]:.1f} Hz, in-band SNR {snr:.1f} dB")
ok = abs(f[kb] - F0) < 2 * FM / n and snr >= MIN_SNR
print("[analyze] PASS" if ok else "[analyze] FAIL")
sys.exit(0 if ok else 1)
