#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
"""Generate an EDID and emit it as a Veryl ROM module plus a raw binary
for inspection.

Default: DVI-only EDID 1.3 (base block only). No CEA-861 extension and
therefore no HDMI VSDB: per HDMI 1.4 section 8.3.3 a source seeing this
EDID must fall back to DVI (no data islands, RGB 8bpc).

--hdmi: base block + CEA-861 extension (256 bytes) so that the source
switches to HDMI and sends audio in data islands (rtl/hdmi_rx):
  Video Data Block      the VIC of the mode (native)
  Audio Data Block      2ch LPCM, 32 / 44.1 / 48 kHz, 16 / 20 / 24 bit
  Speaker Allocation    FL / FR
  HDMI VSDB             OUI 00-0C-03, physical address 1.0.0.0
  Video Capability      QS = 1 (RGB quantization range selectable)
No YCbCr support is declared, so the source sends RGB.

The only listed timing is the preferred DTD - 1280x720@60 (VIC 4) or, with
--mode 1080p, 1920x1080@60 (VIC 16) - because the capture PLL is built for
one pixel clock. Established and standard timings are left empty on purpose.

  python3 gen_edid.py [--mode 720p|1080p] [--hdmi] [--name "FPGA DVI RX"] [--bin edid.bin]
"""
import argparse
import pathlib

# 1280x720@60 (CEA-861 VIC 4)
T720P60 = dict(pclk_khz=74250, hact=1280, hfp=110, hsync=40, hbp=220,
               vact=720, vfp=5, vsync=5, vbp=20, hpol=1, vpol=1)
# 1920x1080@60 (CEA-861 VIC 16)
T1080P60 = dict(pclk_khz=148500, hact=1920, hfp=88, hsync=44, hbp=148,
                vact=1080, vfp=4, vsync=5, vbp=36, hpol=1, vpol=1)
VICS = {"720p": 4, "1080p": 16}
MODES = {
    # timing, image size (mm), range limits: V min/max Hz, H min/max kHz, max pixel clock / 10 MHz
    "720p":  (T720P60, (800, 450), (59, 61, 44, 46, 8)),
    "1080p": (T1080P60, (800, 450), (59, 61, 66, 68, 15)),
}


def mfg_id(s):
    # Three 5-bit letters, 'A' = 1. "FPG" is not a PNP-registered ID; it
    # only identifies this test sink.
    v = 0
    for c in s:
        v = (v << 5) | (ord(c) - ord("A") + 1)
    return [(v >> 8) & 0xFF, v & 0xFF]


def dtd(t, h_mm, v_mm):
    hblank = t["hfp"] + t["hsync"] + t["hbp"]
    vblank = t["vfp"] + t["vsync"] + t["vbp"]
    pc = t["pclk_khz"] // 10
    flags = 0x18 | (t["vpol"] << 2) | (t["hpol"] << 1)  # digital separate sync
    return [
        pc & 0xFF, pc >> 8,
        t["hact"] & 0xFF, hblank & 0xFF, ((t["hact"] >> 8) << 4) | (hblank >> 8),
        t["vact"] & 0xFF, vblank & 0xFF, ((t["vact"] >> 8) << 4) | (vblank >> 8),
        t["hfp"] & 0xFF, t["hsync"] & 0xFF,
        ((t["vfp"] & 0xF) << 4) | (t["vsync"] & 0xF),
        ((t["hfp"] >> 8) << 6) | ((t["hsync"] >> 8) << 4)
        | ((t["vfp"] >> 4) << 2) | (t["vsync"] >> 4),
        h_mm & 0xFF, v_mm & 0xFF, ((h_mm >> 8) << 4) | (v_mm >> 8),
        0, 0, flags,
    ]


def text_desc(tag, s):
    b = s.encode("ascii")[:13]
    if len(b) < 13:
        b += b"\n" + b" " * (12 - len(b))
    return [0, 0, 0, tag, 0] + list(b)


def cea_block(mode):
    """CEA-861 extension (revision 3), data blocks only, no DTD."""
    blocks = []
    blocks += [0x40 | 1, 0x80 | VICS[mode]]             # Video Data Block, native VIC
    blocks += [0x20 | 3, 0x09, 0x07, 0x07]              # Audio: LPCM 2ch, 32/44.1/48k, 16/20/24 bit
    blocks += [0x80 | 3, 0x01, 0x00, 0x00]              # Speaker Allocation: FL/FR
    blocks += [0x60 | 5, 0x03, 0x0C, 0x00, 0x10, 0x00]  # HDMI VSDB, physical address 1.0.0.0
    blocks += [0xE0 | 2, 0x00, 0x40]                    # Video Capability: QS = 1
    c = [0x02, 0x03, 4 + len(blocks),
         0x40 | 0x01]                                   # basic audio, 1 native DTD
    c += blocks
    c += [0x00] * (127 - len(c))
    assert len(c) == 127
    c += [(-sum(c)) & 0xFF]
    return c


def build(name, mode="720p", hdmi=False):
    timing, (h_mm, v_mm), (vmin, vmax, hmin, hmax, pmax) = MODES[mode]
    e = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
    e += mfg_id("FPG")
    e += [0x01, 0x00]                  # product code
    e += [0, 0, 0, 0]                  # serial (see text descriptor)
    e += [0, 2026 - 1990]              # week unspecified, year 2026
    e += [0x01, 0x03]                  # EDID 1.3
    e += [0x80]                        # digital input
    e += [80, 45]                      # 80 x 45 cm (16:9)
    e += [120]                         # gamma 2.2
    e += [0x0E]                        # RGB colour, sRGB, preferred timing in DTD 1
    # sRGB chromaticity
    e += [0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54]
    e += [0x00, 0x00, 0x00]            # no established timings
    e += [0x01, 0x01] * 8              # no standard timings
    e += dtd(timing, h_mm, v_mm)
    # Monitor range limits around the single timing
    e += [0, 0, 0, 0xFD, 0, vmin, vmax, hmin, hmax, pmax, 0x00,
          0x0A, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20]
    e += text_desc(0xFC, name)         # monitor name
    e += [0, 0, 0, 0x10, 0] + [0] * 13  # dummy descriptor
    e += [0x01 if hdmi else 0x00]      # extension blocks
    assert len(e) == 127, len(e)
    e += [(-sum(e)) & 0xFF]
    assert sum(e) & 0xFF == 0
    if hdmi:
        e += cea_block(mode)
        assert len(e) == 256 and sum(e[128:]) & 0xFF == 0
    return e


VERYL_HEAD = """\
// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file {fname}
 * @brief EDID contents (generated by gen_edid.py - do not edit).
 *
 * {desc}
 * {rom_desc}
 */

pub module {module} (
    i_addr: input  logic<8>,
    o_data: output logic<8>,
) {{
    always_comb {{
        case i_addr{addr_sel} {{
"""

VERYL_TAIL = """\
            default: o_data = 8'h00;
        }
    }
}
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="FPGA DVI RX")
    ap.add_argument("--mode", choices=sorted(MODES), default="720p")
    ap.add_argument("--module", help="module name (default edid_rom / edid_rom_1080p)")
    ap.add_argument("--out", help="output .veryl (default <module>.veryl next to this script)")
    ap.add_argument("--hdmi", action="store_true", help="add the CEA-861 extension (HDMI + audio)")
    ap.add_argument("--bin")
    a = ap.parse_args()
    e = build(a.name, a.mode, a.hdmi)
    default = "edid_rom" if a.mode == "720p" else f"edid_rom_{a.mode}"
    module = a.module or (default.replace("edid_rom", "edid_rom_hdmi") if a.hdmi else default)
    out = a.out or str(pathlib.Path(__file__).with_name(module + ".veryl"))
    t = MODES[a.mode][0]
    if a.hdmi:
        desc = (f'HDMI EDID 1.3 + CEA-861 (2ch LPCM audio), "{a.name}", preferred '
                f'{t["hact"]}x{t["vact"]}@60, checksums 0x{e[127]:02X} / 0x{e[255]:02X}.')
        rom_desc, addr_sel, w = "Combinational 256-byte ROM (base block + extension).", "", 8
    else:
        desc = (f'DVI-only EDID 1.3, "{a.name}", preferred {t["hact"]}x{t["vact"]}@60, '
                f'checksum 0x{e[-1]:02X}.')
        rom_desc, addr_sel, w = "Combinational 128-byte ROM; offsets 128-255 mirror the base block.", "[6:0]", 7
    lines = [VERYL_HEAD.format(desc=desc, fname=pathlib.Path(out).name, module=module,
                               rom_desc=rom_desc, addr_sel=addr_sel)]
    for i, b in enumerate(e):
        lines.append(f"            {w}'h{i:02X}  : o_data = 8'h{b:02X};\n")
    lines.append(VERYL_TAIL)
    pathlib.Path(out).write_text("".join(lines))
    if a.bin:
        pathlib.Path(a.bin).write_bytes(bytes(e))
    for i in range(0, len(e), 16):
        print(" ".join(f"{b:02X}" for b in e[i:i + 16]))


if __name__ == "__main__":
    main()
