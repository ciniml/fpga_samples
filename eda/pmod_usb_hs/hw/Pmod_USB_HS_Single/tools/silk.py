#!/usr/bin/env python3
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Back silkscreen: logo, board name / revision / date / author and the pinout
(as on the other boards: logo + name / Rev / date / "Kenta Ida (@ciniml)").
apply(board, logo) is called by gen_pcb.py; run stand-alone to redo the silk of
the board in place (removes every B.SilkS text and LOGO1 first, copper untouched)."""
import os
import pcbnew

OX, OY = 100.0, 80.0       # board origin (gen_pcb.py)
REV, DATE = 'Rev.A', '2026-10-20'
LOGO = (17.6, 11.6)         # logo centre; seen from the back it is on the left, the title to its right
TITLE = ('Pmod USB HS\nSingle ' + REV + '\n' + DATE + '\nKenta Ida (@ciniml)', 14.0, 9.0)
TITLE_SIZE = 0.8
NOTES = [  # (text, x, y, size) - x is the text centre, board coordinates from the top
    ('1 DX+ 2 D+ 3 TRM+ 4 PU', 11.43, 15.9, 0.8),
    ('7 DX- 8 VREF 9 TRM- 10 VBUS', 11.43, 17.1, 0.8),
    ('usb_phy_gowin_sl CMP1=1', 11.43, 18.3, 0.8),
]


def P(x, y):
    return pcbnew.VECTOR2I(pcbnew.FromMM(OX + x), pcbnew.FromMM(OY + y))


def text(board, s, x, y, size, left=False):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(s)
    t.SetLayer(pcbnew.B_SilkS)
    t.SetTextSize(pcbnew.VECTOR2I(pcbnew.FromMM(size), pcbnew.FromMM(size)))
    t.SetTextThickness(pcbnew.FromMM(0.12 if size < 0.9 else 0.15))
    t.SetMirrored(True)
    if left:   # left as read from the back = towards -x on the board
        t.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_LEFT)
        t.SetVertJustify(pcbnew.GR_TEXT_V_ALIGN_TOP)
    t.SetPosition(P(x, y))
    board.Add(t)


def apply(board, fp):
    """fp: the logo footprint (pcbnew.FootprintLoad(<Local/local.pretty>, 'logo'))."""
    for f in list(board.GetFootprints()):
        if f.GetReference() == 'LOGO1':
            board.Remove(f)
    for d in list(board.GetDrawings()):
        if d.GetLayer() == pcbnew.B_SilkS and isinstance(d, pcbnew.PCB_TEXT):
            board.Remove(d)
    for s, x, y, size in NOTES:
        text(board, s, x, y, size)
    text(board, *TITLE, TITLE_SIZE, left=True)
    fp.SetFPID(pcbnew.LIB_ID('local', 'logo'))
    fp.SetReference('LOGO1')
    fp.SetAttributes(fp.GetAttributes() | pcbnew.FP_BOARD_ONLY | pcbnew.FP_EXCLUDE_FROM_BOM
                     | pcbnew.FP_EXCLUDE_FROM_POS_FILES)
    board.Add(fp)
    fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
    fp.SetOrientationDegrees(180)
    fp.SetPosition(P(*LOGO))


def load_logo(prj):
    return pcbnew.FootprintLoad(os.path.join(prj, 'Local', 'local.pretty'), 'logo')


if __name__ == '__main__':
    prj = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    path = os.path.join(prj, 'Pmod_USB_HS_Single.kicad_pcb')
    logo = load_logo(prj)
    crlf = b'\r\n' in open(path, 'rb').read(4096)    # keep the line endings of the KiCad GUI save
    board = pcbnew.LoadBoard(path)
    apply(board, logo)
    board.Save(path)
    if crlf:
        data = open(path, 'rb').read()
        open(path, 'wb').write(data.replace(b'\r\n', b'\n').replace(b'\n', b'\r\n'))
    print('silk: done')
