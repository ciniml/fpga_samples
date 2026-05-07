# DVI receiver — Tang Primer 25K (Gowin GW5A)

Vendor wrapper for the Veryl-side `dvi_in` core (`rtl/dvi_in/`). Provides
the RX physical layer: differential receivers, programmable input delay,
and 1:10 deserializers for the four DVI lanes (CLK + 3 data).

## Files

| File              | Role                                                                |
|-------------------|---------------------------------------------------------------------|
| `iser10_lane.sv`  | Single lane: `TLVDS_IBUF → IODELAY → IDES10`, mirror of `oser10_lane`.|
| `dvi_in_phy.sv`   | Replicates `iser10_lane` ×4, wires CALIB / DLYSTEP from `dvi_in`.   |

The Veryl RTL (`rtl/dvi_in/dvi_in.sv`) must be built first
(`cd rtl/dvi_in && veryl build`) so the generated `dvi_in.sv` is
available to the synthesis run.

## Clocking

`dvi_in_phy` consumes two clocks generated outside this module:

| Signal   | Frequency      | Source                                                      |
|----------|----------------|-------------------------------------------------------------|
| `i_pclk` | F_pixel        | recovered from the cable CLK pair (TLVDS_IBUF + global buffer) |
| `i_fclk` | 5 × F_pixel    | rPLL with CLKIN = i_pclk, IDIV_SEL = 0, FBDIV_SEL = 4       |

`F_pixel` is whatever the upstream display sends — common values are
25.175 MHz (VGA), 65 MHz (XGA), 74.25 MHz (720p60), 148.5 MHz (1080p60).
Plan the rPLL to cover the target range; for a fixed test resolution
just set the multiplier for that one rate.

The bit rate at the pad is `10 × F_pixel`. IDES10 samples DDR at FCLK
so `FCLK = 5 × F_pixel`.

## Steps to bring up

1. **Generate the rPLL IP** for `i_fclk`:
   - Open Gowin IP Core Generator, choose `rPLL`.
   - `CLKIN = F_pixel`, `CLKOUT = 5 × F_pixel`, set `IDIV_SEL = 0`,
     `FBDIV_SEL = 4` (×5).
   - Save under `ip/rpll_fclk/`.
2. **Top-level integration** — instantiate in your board top:
   ```sv
   wire pclk_recovered;
   TLVDS_IBUF u_clk_ibuf (.O(pclk_recovered), .I(clk_p), .IB(clk_n));

   wire fclk;
   wire pll_lock;
   rpll_fclk u_rpll (.clkin(pclk_recovered), .clkout(fclk), .lock(pll_lock));

   dvi_in_phy u_phy (
       .i_pclk        (pclk_recovered),
       .i_fclk        (fclk),
       .i_reset       (!pll_lock || reset_button),
       .i_clk_p(clk_p), .i_clk_n(clk_n),
       .i_d0_p (d0_p),  .i_d0_n (d0_n),
       .i_d1_p (d1_p),  .i_d1_n (d1_n),
       .i_d2_p (d2_p),  .i_d2_n (d2_n),
       /* recovered video out */
       .o_video_data  (rgb24),
       .o_video_de    (de),
       .o_video_hsync (hs),
       .o_video_vsync (vs),
       .o_video_ctl   (),
       .o_video_valid (valid),
       .o_decode_err  (decode_err),
       .o_locked      (locked)
   );
   ```
3. **Pin constraints** — declare the four pads as `LVDS25` differential
   inputs in `pins.cst` (mirror the `ml_lane_*` LVDS_OBUF entries from
   `eda/display_port_tpg/src/tangprimer25k/pins.cst`).

## Syntax verification

The wrappers can be lint-checked outside the Gowin tool with Verilator
+ small primitive stubs (`TLVDS_IBUF`, `IODELAY`, `IDES10`). The Gowin
simlib at `~/gowin/1.9.10.01/IDE/simlib/gw5a/prim_sim.v` uses Verilog-95
`deassign` constructs that Verilator does not accept; for that reason
verify against stubs (or, for full functional sim, switch to the Gowin
GAO/iverilog flow).

## Open work

- **Closed-loop delay refinement.** `dvi_in.DELAY_CAL` currently does an
  open-loop sweep using `o_delay_load + o_delay_tap`. The wrapper also
  honours `o_delay_inc / o_delay_dec` for fine-grained adjustment after
  lock; the FSM that issues those pulses is not yet implemented in the
  core.
- **Per-lane delay calibration.** All four lanes currently share one
  delay tap. A real receiver may need per-lane skew compensation; in
  that case fan-out the delay register inside `dvi_in_phy` and add
  per-lane lock indicators.
- **Test pattern verifier.** Pair this PHY with a small frame-comparison
  block (or just route the recovered `RGB24` to an HDMI monitor on a
  second connector) to verify end-to-end on real hardware.
