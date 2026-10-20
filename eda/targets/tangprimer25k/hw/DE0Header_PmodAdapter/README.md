# DE0Header_PmodAdapter (Rev.A, 2026-10-20)

Adapter that stacks on the Tang Primer 25K Dock's 40-pin DE0-compatible
header (**J3** in the Dock schematic) and
breaks it out to four Pmod host sockets plus two small headers. The FPGA's
true-LVDS pairs are routed as coupled differential pairs.

- Board: 91.44 x 45 mm, 2 layers, 1.6 mm, chamfered corners
- Generated: `tools/gen_sch.py` / `tools/gen_pcb.py` (pin map in `tools/pinmap.py`)
- Fab outputs: `tools/build.sh` (ERC/DRC/parity check, Gerber zip, BOM/CPL for JLC in `fab/jlc/`)
- LCSC order list for 5 boards: `python3 tools/lcsc_order.py 5` -> `fab/lcsc/`
- FPGA pin list: `eda/targets/tangprimer25k/de0header_adapter_pmod_ports.csv` (format as `pmod_ports.csv`)

## Dock header facts (source: Sipeed Tang_Primer_25K_Dock schematic + iBOM)

- 2x20 male 2.54 mm, odd pins on the inner row (towards the Dock), even pins on the outer row.
- Pin 11 = +5V, pin 12 = GND. **No 3.3 V pin** -> on-board AMS1117-3.3 from +5V.
- The other 38 pins are FPGA I/O. Each header pair (2k-1, 2k) is a GW5A-25 IOxxA/IOxxB
  pair (true LVDS P on the even pin) except 17/18 (A1/E1) and 19/20 (D1/E3), which
  are not a pair and are routed single-ended.

## Slot map (Pmod pin -> ball)

Pmod pin n (top row) = pair P, pin n+6 (bottom row) = pair N, so every Pmod column
(1/7, 2/8, 3/9, 4/10) is one differential pair, as on the Dock's own Pmods.

| Slot | 1 | 2 | 3 | 4 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|
| PMOD A (pmod3) | K1 | L2 | J4 | G2 | K2 | L1 | K4 | G1 |
| PMOD B (pmod4) | L4 | B2 | F2 | E1* | L3 | C2 | F1 | A1* |
| PMOD C (pmod5) | J1 | G4 | H1 | K7 | J2 | H4 | H2 | J7 |
| PMOD D (pmod6) | L7 | L10 | L9 | J8 | L8 | K10 | K9 | K8 |

\* single-ended (E1/A1 are not a pair). EXT1 (2x2): 1 D1, 2 3V3, 3 E3, 4 GND.
EXT2 (2x3): 1 F7 (P), 2 F6 (N), 3 J11 (P), 4 J10 (N), 5 GND, 6 3V3.

## Notes

- Pairs: netclass Link 0.1661 / 0.127 mm over the solid B.Cu GND (about 100 ohm differential);
  single-ended 0.2 mm. Pair skew inside a pair is the 1.15 mm side step at each end only.
- Bank 2 has no on-chip 100 ohm termination (DIFF_RESISTOR); terminate LVDS inputs on the module or use SE.
- B2 / C2 also drive LEDs on the Dock (pmod4 pin 2/8): expect extra load on those two.
- 3V3 per Pmod is from the AMS1117 (about 0.8 A total budget, minus the Dock's own 5 V load).
- **Mounting holes H1 / H2** (2.7 mm, M2.5, non-plated, ISO 7380 button-head keepout): at the same place
  relative to the header as the Dock's own holes on both sides of J3 (Dock iBOM J9 / J11: 4.865 mm
  outside pin 1 and pin 39/40, 1.575 mm from the odd row towards the even row; 57.99 mm apart).
  Fix the board with two M2.5 female-female standoffs of about **11 mm** (8.5 mm socket J1 + the
  2.5 mm plastic base of the Dock's header; measure the actual gap first) and M2.5 screws from both
  sides. The board still overhangs the Dock's top edge (it overlaps the Dock only near the header)
  and has no support at its far edge: do not lever the Pmod modules against it.

## Parts (LCSC, stock checked 2026-10-20)

J1 C5124634 (2x20 female 8.5 mm), J2-J5 C22373932 (2x6 right-angle female),
J6 C66690, J7 C65114, U1 C6186 AMS1117-3.3, C1 C15850 10u, C2 C45783 22u,
C3-C6 C1525 100n (out of stock at LCSC; the LCSC list orders C60474 instead).
