# Sipeed SLogic16U3 (GW5AT-LV15MG132C1/I0)

No public schematic (dl.sipeed.com only has firmware). What is known:

| Signal | Ball | Source |
|---|---|---|
| LA CH0..CH7 | J14 J13 N14 P14 N13 P13 N12 P12 | litex-boards `platforms/sipeed_slogic16u3.py` |
| LA CH8..CH15 | N11 P11 N10 P10 N9 P9 N8 P8 | same (bank 1, LVCMOS33) |
| UART TX / RX | F14 / E14 | same (D09 / D08 dual-purpose) |
| JTAG TCK/TMS/TDI/TDO | G2 / G3 / J3 / J2 | package (bank 4 dual-purpose, no JTAGSEL_N) |
| SPI flash CCLK/MCS_N/MOSI/MISO/D02/D03 | L14 / L13 / M13 / K14 / K13 / M14 | package |
| USB 3 | SerDes Q0 (4 lanes, REFCLK0/1) — lane unknown | |

- On-board JTAG + UART connector: JST SH1.0 8-pin, assumed to match the Tang Primer 20K / Mega 138K core boards
  (pin 1..8 = 5V0, TMS, TDO, TCK, TDI, RX, TX, GND, per Sipeed's Q&A page; not verified on SLogic16U3).
  Where its RX/TX lands on the FPGA is unknown (F14/E14 candidates).
- Package pin list: `~/gowin/<ver>/IDE/data/device/GW5AT-15A/MBGA132.json`.
- IDCODE 0x0001681B. Factory flow (sipeed/slogic16u3-tools): app image at flash 0x0, DFU (golden) image at 0x800000, eFuse AES key written and locked.
- The part takes at most 42 user ports including the 4 JTAG pads when GW_JTAG is used; RECONFIG_N cannot be GPIO.
- Pin investigation: `../../slogic16u3_probe`.
