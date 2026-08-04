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
  symbols.

## Open work

- Per-lane delay taps (all three lanes currently share one DLYSTEP).
- Route the recovered video somewhere useful (HDMI re-out on a second
  Pmod DVI, frame capture to memory, ethernet_video, …).
- Widen the `dvi_in` tap interface beyond 5 bits so the full 8-bit
  DLYSTEP range is reachable without the fixed offset in `top.sv`.
