# DVI receiver — Tang Primer 25K (Gowin GW5A)

Vendor wrapper for the Veryl-side `dvi_in` core (`rtl/dvi_in/`).
Verified on hardware (2026-08): bit-perfect 720p60 capture from a Tang
Nano 9K running `eda/dvi_out_tpg` — stable word lock, zero decode
errors, and frame-CRC-identical capture of a static test pattern.

## Files

| File              | Role                                                                |
|-------------------|---------------------------------------------------------------------|
| `iser10_lane.sv`  | Single data lane: `IODELAY → IDES10` (post-IBUF), mirror of `oser10_lane`. |
| `dvi_in_phy.sv`   | Replicates `iser10_lane` ×3, wires CALIB / DLYSTEP from `dvi_in`.   |
| `top.sv`          | IBUFs, recovery PLL, reset, sampling phase, CRC checkers, LED/debug. |

The Veryl RTL (`rtl/dvi_in/dvi_in.sv`) must be built first
(`cd rtl/dvi_in && veryl build`).

## Hardware setup

- **Source**: Tang Nano 9K running `eda/dvi_out_tpg` (720p60,
  F_pixel = 74.25 MHz), HDMI cable from its on-board connector. No
  EDID/HPD emulation needed — the source transmits unconditionally.
- **Sink**: Tang Primer 25K with a **Sipeed Pmod DVI on PMOD0** (the
  slot containing F5/G5).

Pin mapping (see `pins.cst`; N pins are placed automatically):

| Lane | Pmod pins (P/N) | FPGA pins | Notes                     |
|------|-----------------|-----------|---------------------------|
| CLK  | pmod0_4 / 10    | H5 / J5   | GCLKT_2/TPLL_T_IN0, PLL only |
| D0   | pmod0_3 / 9     | H8 / H7   | alignment reference lane  |
| D1   | pmod0_2 / 8     | G7 / G8   |                           |
| D2   | pmod0_1 / 7     | F5 / G5   |                           |

**PMOD0 (bank 1) is the only workable slot**, for two silicon reasons
found the hard way:

1. On-chip 100 Ω differential termination (`DIFF_RESISTOR=ON`) is not
   available in banks 2/6 (tool error CT1166). PMOD2 lanes (bank 6) run
   unterminated and suffer pattern-dependent ISI bit errors; PMOD1 has
   the same problem plus the next one.
2. A pad whose IBUF output fans out to the recovery PLL cannot also
   drive the IODELAY/IDES10 chain — that lane's deserializer stays
   silent. Hence the clock pair feeds the PLL only, and `dvi_in` aligns
   on data-lane-0 control symbols (DVI 1.0 §3.3.2) instead of a
   deserialized clock-lane pattern.

## Clocking

The cable CLK pair is buffered once (`TLVDS_IBUF` in `top.sv`) and
drives the recovery PLL (`ip/gowin_pll_dvi`, hand-derived PLLA wrapper):

| Signal | Frequency  | Source                              |
|--------|------------|-------------------------------------|
| `pclk` | 74.25 MHz  | PLLA CLKOUT0 (VCO 1113.75 MHz / 15) |
| `fclk` | 371.25 MHz | PLLA CLKOUT1 (VCO 1113.75 MHz / 3)  |

Both outputs divide the same VCO so the IDES10 PCLK/FCLK phase relation
holds. For a different source resolution, recompute `MDIV/ODIV0/ODIV1`
in `gowin_pll_dvi.v` (keep `CLKOUT1 = 5 × CLKOUT0`) and update
`create_clock` in `timing.sdc`.

## Sampling phase

Effective DLYSTEP = 56 (`DELAY_TAP_INIT` 24 + fixed offset 32 in
`top.sv`). A button-swept eye map on PMOD0 (line-CRC error rate vs
offset) showed clean spots at DLYSTEP 56 / 152 / 248 — a ~96-tap period
matching one bit time (1.35 ns), i.e. ~14 ps per tap. 56 is the
earliest clean spot (delay lines add jitter, so prefer minimal delay).
The phase is slot-dependent: re-sweep after moving the module (the
button-step experiment code is preserved in git history).

Automatic phase calibration was tried and rejected: minimum-error-count
ranks noise at good phases, and eye-centring settles on high-delay taps
whose extra jitter outweighs the phase gain.

## Status / debug outputs

| Pin | Signal |
|-----|--------|
| B2  | `led_locked` — word lock |
| C2  | `led_decode_err` — any decode error in the last ~0.1 s |
| PMOD1 pin1 (A11) | frame-CRC mismatch (~110 µs per bad frame; needs a **static** source, e.g. `dvi_out_tpg` with `BOUNCE_LOGO(0)`) |
| PMOD1 pin2 (E11) | line-CRC mismatch vs previous frame (~3.4 µs per bad line) |
| PMOD1 pin3 (K11) | recovered DE |
| PMOD1 pin4 (L5)  | recovered VSYNC |

The CRC taps compare against the *previous* frame, so an animated
source (logo bounce enabled) legitimately fires them every frame.

## Robustness notes

`dvi_in` carries two hardening measures against corrupted blanking
symbols (needed on unterminated slots, harmless on PMOD0):

- DE is a 3-word majority over lane 0's "not a control symbol", so an
  isolated corrupted symbol can neither fake DE nor punch a hole in
  active video.
- HSYNC/VSYNC/CTL update only from words that decode as genuine control
  symbols and agree with a neighbouring word (a single bit error turns
  CTRL_01 into CTRL_11, i.e. a false VSYNC; found on the 1080p loopback).

## HDMI sources

`dvi_in` also copes with sources that send HDMI although the EDID is
DVI-only: a lane-0 data run that follows a data-island preamble (CTL3..0
= 0101) is not video, and a run that follows the video preamble (0001)
*and* opens with the video guard band loses those 2 words. A notebook PC
seen on hardware keeps CTL0 = 1 through the whole blanking but sends no
guard bands: that stays plain DVI (no pixels dropped).

## UART (diagnostics and phase tuning)

`eda/dvi_loopback`'s checker (`loop_check`, `EXT_CHECK=1`) and reporter
(`loop_report`) run here too: USB-UART C3 (TX) / B3 (RX), 115200 8N1,
host script `eda/dvi_loopback/host/loopctl.py`. Same line format and
commands as the loopback (see its README), with these differences:

- F = frames, B = frame-CRC mismatches against the previous frame (a
  static screen gives 0; a taskbar clock bumps it once a minute),
  N = DE pixels in the last frame (720p: 921600)
- X = EDID bytes read by the source, Y = {HPD, 23'b0, DDC offset}
- Z0-Z2 = 0 (no pixel reference)
- `w` / `v` / `x` / `e`: raw words around a control symbol / a run start
  / a blanking word with lane 1 or 2 not a control symbol / a lane 1-2
  decode error

Build variants: `make CTLE=OFF|LOW|MEDIUM|HIGH` (default HIGH) and
`make RATE=1080P` (1920x1080p60: 148.5 MHz recovery PLL from
eda/dvi_loopback, 1080p EDID, timing_1080p.sdc).

The frame check is loop_check's pixel sum compared with the previous
frame (the former CRC32 over 24 bits per clock did not close at
148.5 MHz); the per-line CRC debug block is gone.

Result with a notebook PC (HDMI cable, Pmod DVI on pmod0, 2026-09-27):
it reads the EDID and sends 720p60. Error-free phase window (4-tap
steps): CTLE OFF 0x30..0x5C, HIGH / MEDIUM 0x20..0x58 (half a bit).
The default offset 0x3C gives 0 decode errors and no CRC change except
the clock over 8000 frames.

1080p60 (`RATE=1080P`, same PC and cable): the error-free window is only
about 2 coarse steps wide (e.g. 0x2C..0x30, repeating every 0x34 taps)
and lane 2 (R) samples ~7 taps early: with a shared phase every frame
still had a few wrong R pixels without any decode error. Offset 0x30
with lane trims B -1 / G +3 / R -7 (the RATE=1080P defaults) gives 7440
frames with 0 decode errors, 0 lock losses, 2073600 DE pixels per frame
and frame changes only at the clock's minute ticks.

## HDMI/DVI side channel (DDC / EDID / HPD)

For sources that need a sink (PCs, HDMI products), `rtl/ddc_edid` runs on
the 50 MHz board clock (E2), independent of the cable clock:

| Signal | Pin | Notes |
|---|---|---|
| `ddc_sda` | B11 (pmod2_3) | open drain via `IOBUF` |
| `ddc_scl` | C11 (pmod2_4) | input only (no clock stretching) |
| `hpd` | D11 (pmod2_2) | 3.3 V output (HDMI HPD high is >= 2.0 V); ~1 kohm series |
| CEC | G11 (pmod2_1) | reserved, not used |
| `button_replug` | H10 (S1) | drops HPD for 200 ms so the source re-reads the EDID |

Pin names follow `eda/targets/tangprimer25k/pmod_ports.csv`; wire the
Pmod DVI's side-channel pads to them. **DDC is pulled up to 5 V by the
source: put a level shifter (e.g. PCA9306) or clamp between the Pmod and
B11/C11.** There is no +5V sense line, so HPD rises 200 ms after the
side channel leaves reset.

The EDID (DVI-only, 1280x720@60 as the only timing) makes the source
send plain DVI at the rate the recovery PLL is built for; see
`rtl/ddc_edid/README.md`.

## Open work

- Route the recovered video somewhere useful (HDMI re-out on a second
  Pmod DVI, frame capture to memory, ethernet_video, …).
- Widen the `dvi_in` tap interface beyond 5 bits so the full 8-bit
  DLYSTEP range is reachable without the fixed offset in `top.sv`.
