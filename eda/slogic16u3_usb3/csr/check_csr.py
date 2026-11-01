#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Compare gw5at15_csr.py with Gowin's toml -> CSR tool for a set of settings (byte for byte, with the
register group names). Needs the Gowin IDE (GOWIN_IDE, default ~/gowin/1.9.12.03/IDE); the toml is the
IP's src/slogic16u3/usb3_ln0/serdes_tmp.toml with lane 0 keys changed.

usage: check_csr.py [-k]      (-k: keep the generated files in csr/check/)
"""
import os
import re
import subprocess
import sys
import tempfile

import gw5at15_csr as g

HERE = os.path.dirname(os.path.abspath(__file__))
IDE = os.environ.get('GOWIN_IDE', os.path.expanduser('~/gowin/1.9.12.03/IDE'))
TOOL = os.path.join(IDE, 'bin/serdes_toml_to_csr.dist/serdes_toml_to_csr_15k.bin')
TOML = os.path.join(HERE, '../src/slogic16u3/usb3_ln0/serdes_tmp.toml')
PLAIN = os.path.join(HERE, '../src/slogic16u3/usb3_ln0/serdes.csr')

# (Gowin toml keys of [q0.ln0], gw5at15_csr Lane fields)
CASES = [
    ({}, {}),
    ({'encode_mode': '"8b10b"'}, {'encode_8b10b': 1}),
    ({'decode_mode': '"8b10b"'}, {'decode_8b10b': 1}),
    ({'word_align_enable': 'true'}, {'word_align': 1}),
    ({'ctc_enable': 'true'}, {'ctc': 1}),
    ({'ctc_enable': 'true', 'decode_mode': '"8b10b"', 'encode_mode': '"8b10b"', 'word_align_enable': 'true'},
     {'ctc': 1, 'decode_8b10b': 1, 'encode_8b10b': 1, 'word_align': 1}),
    ({'rx_pol_invert': 'true'}, {'rx_pol_invert': 1}),
    ({'tx_pol_invert': 'true'}, {'tx_pol_invert': 1}),
    ({'sr_sd_thsel': '0'}, {'sr_sd_thsel': 0}),
    ({'sr_sd_thsel': '5'}, {'sr_sd_thsel': 5}),
    ({'rxsd_use_dlogic': 'true'}, {'rxsd_use_dlogic': 1}),
    ({'locked_from_fabric': 'true'}, {'locked_from_fabric': 1}),
    ({'locked_from_fabric': 'true', 'rxsd_use_dlogic': 'true'}, {'locked_from_fabric': 1, 'rxsd_use_dlogic': 1}),
    ({'rx_coupling': '"DC"'}, {'rx_coupling_dc': 1}),
    ({'eq_manual': 'true'}, {'eq_manual': 1}),
    ({'eq_manual': 'true', 'dr_rx_att': '3', 'dr_rx_boost': '4', 'dr_rx_att_boost': '1'},
     {'eq_manual': 1, 'rx_att': 3, 'rx_boost': 4, 'rx_att_boost': 1}),
    ({'eq_manual': 'true', 'rx_coupling': '"DC"'}, {'eq_manual': 1, 'rx_coupling_dc': 1}),
    ({'ffe_manual': 'true'}, {'ffe_manual': 1}),
    ({'ffe_manual': 'true', 'txlev': '10', 'ffe_c1': '8', 'ffe_cm': '5'},
     {'ffe_manual': 1, 'txlev': 10, 'ffe_c1': 8, 'ffe_cm': 5}),
]


def set_keys(text, keys):
    a = text.index('[q0.ln0]')
    b = text.index('[q0.ln1]')
    sec = text[a:b]
    for k, v in keys.items():
        sec, n = re.subn(rf'^{re.escape(k)} = .*$', f'{k} = {v}', sec, flags=re.M)
        assert n == 1, k
    return text[:a] + sec + text[b:]


def main():
    keep = '-k' in sys.argv
    out = os.path.join(HERE, 'check') if keep else tempfile.mkdtemp()
    os.makedirs(out, exist_ok=True)
    base = open(TOML).read()
    ok = True
    # the build's CSR (without names) is the base list
    if g.text(g.build(g.Lane())) != open(PLAIN).read():
        print('FAIL base != src/slogic16u3/usb3_ln0/serdes.csr')
        ok = False
    for n, (keys, fields) in enumerate(CASES):
        t = os.path.join(out, f'c{n}.toml')
        c = os.path.join(out, f'c{n}.csr')
        open(t, 'w').write(set_keys(base, keys))
        subprocess.run([TOOL, '--comment', '-o', c, t], capture_output=True)
        ref = open(c).read()
        got = g.text(g.build(g.parse_kv(f'{k}={v}' for k, v in fields.items())), comment=True)
        same = ref == got
        ok &= same
        print(f'{"ok  " if same else "FAIL"} {keys or "(base)"}')
        if not same and keep:
            open(os.path.join(out, f'c{n}_ours.csr'), 'w').write(got)
    print('all match' if ok else 'MISMATCH')
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
