#!/usr/bin/env python3
"""Back silkscreen: pinout / notes, logo and board name / revision / date / author
(as on the other boards: logo + name / Rev / date / "Kenta Ida (@ciniml)").
apply(board) is called by gen_pcb.py; run stand-alone to redo the silk of the
routed board in place (removes every B.SilkS text and LOGO1 first, copper untouched;
tools/drc.sh refills the zones)."""
import os
import sys
import pcbnew

OX, OY = 100.0, 100.0      # board origin (gen_pcb.py)
L = 52.0
REV, DATE = 'Rev.A', '2026-10-19'
NOTES = [  # (text, x, y, size) - x is the text centre, board coordinates from the top
    ('1/7 A 2/8 B 3/9 PWM 4/10 TX', 18.5, 2.0, 0.8),
    ('J2 HR911105A, U1 TPD4E02B04', 18.5, 3.8, 0.8),
    ('PoE: no PSE behind this board;', 18.5, 15.0, 0.8),
    ('isolation by magnetics', 18.5, 16.6, 0.8),
    ('TCT/RCT: AC GND only, no 3V3', 18.5, 18.6, 0.8),
]
LOGO = (26.4, 9.4)          # logo centre; the title block reads to its right seen from the back
TITLE = ('Pmod 100BASE-TX\nMagJack ' + REV + '\n' + DATE + '\nKenta Ida (@ciniml)', 22.6, 6.85)
TITLE_SIZE = 0.9            # 1.0 mm would run into the Pmod header pads


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
    """fp: the logo footprint (pcbnew.FootprintLoad(<lib>, 'logo'), loaded before LoadBoard)."""
    for f in list(board.GetFootprints()):
        if f.GetReference() == 'LOGO1':
            board.Remove(f)
    for d in list(board.GetDrawings()):
        if d.GetLayer() == pcbnew.B_SilkS and isinstance(d, pcbnew.PCB_TEXT):
            board.Remove(d)
    for s, x, y, size in NOTES:
        text(board, s, x, y, size)
    text(board, *TITLE, TITLE_SIZE, left=True)
    fp.SetFPID(pcbnew.LIB_ID('pmod_100base_tx', 'logo'))
    fp.SetReference('LOGO1')
    fp.SetAttributes(fp.GetAttributes() | pcbnew.FP_BOARD_ONLY | pcbnew.FP_EXCLUDE_FROM_BOM
                     | pcbnew.FP_EXCLUDE_FROM_POS_FILES)
    board.Add(fp)
    fp.Flip(fp.GetPosition(), pcbnew.FLIP_DIRECTION_LEFT_RIGHT)
    fp.SetOrientationDegrees(180)
    fp.SetPosition(P(*LOGO))


if __name__ == '__main__':
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sys.path.insert(0, os.path.join(here, 'tools'))
    from design import NAME
    path = os.path.join(here, NAME + '.kicad_pcb')
    logo = pcbnew.FootprintLoad(os.path.join(here, 'lib', 'pmod_100base_tx.pretty'), 'logo')
    board = pcbnew.LoadBoard(path)
    apply(board, logo)
    board.Save(path)
    print('silk: done')
