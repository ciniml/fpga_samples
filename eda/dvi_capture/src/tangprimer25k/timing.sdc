// timing.sdc — DVI receiver constraints (720p60 source).

// Cable pixel clock recovered from the DVI CLK pair (74.25 MHz).
create_clock -name dvi_pclk -period 13.468 -waveform {0 6.734} [get_ports {dvi_clk_p}]

// PLL outputs, named explicitly so exceptions below can reference them
// (the tool's auto-derived "default_gen_clk" names are not addressable
// from this file).
create_generated_clock -name pclk -source [get_ports {dvi_clk_p}] -master_clock dvi_pclk -multiply_by 1 [get_pins {pll_main/PLLA_inst/CLKOUT0}]
create_generated_clock -name fclk -source [get_ports {dvi_clk_p}] -master_clock dvi_pclk -multiply_by 5 [get_pins {pll_main/PLLA_inst/CLKOUT1}]

// IODELAY tap registers feed DLYSTEP, which sits in the serial data
// path into IDES10. The tap value is quasi-static: during calibration
// each value is held for TAP_DWELL (256) pclk cycles, and any glitch
// while it changes only perturbs samples the calibration is still
// evaluating. Not a synchronous pclk->fclk path.
// (The four lanes' tap registers are identical and get merged by
// synthesis into a single instance, so one wildcard covers them all.)
set_false_path -from [get_pins {u_phy/*/delay_tap_reg*/Q}]
set_false_path -from [get_pins {u_phy/*/dlystep*/Q}]

// Serial data path (pad -> IODELAY -> IDES10.D). Sampling alignment is
// established by the IODELAY tap sweep + word-boundary calibration, not
// by static timing, so the input data path is not a synchronous path.
set_false_path -from [get_ports {dvi_d0_p dvi_d1_p dvi_d2_p}]
// The clock-lane copy of that path (IBUF output -> IODELAY -> IDES10.D)
// is launched by the dvi_pclk clock itself. No fabric register is
// clocked by dvi_pclk directly (it only feeds the PLL and this data
// path), so a clock-to-clock exception is safe.
set_false_path -from [get_clocks {dvi_pclk}] -to [get_clocks {fclk}]

// reset_seq output is held for many cycles; its crossing into the
// IDES10 RESET (fclk domain) is not single-cycle. Mirrors the
// equivalent constraint in eda/dvi_out_tpg (OSER10 RESET).
set_false_path -from [get_pins {reset_seq_pclk/reset_seq_0_s0/Q}] -to [get_pins {u_phy/*/u_ides10/RESET}]

// dvi_in's align_shift_req is asserted for one full pclk cycle
// (= 5 fclk cycles) and followed by SHIFT_SETTLE_CYCLES of idle, so the
// IDES10 CALIB input may capture it one fclk edge late without harm.
// (set_multicycle_path on this path is ignored by the Gowin STA, so it
// is declared false instead — safe because the pulse is 5 fclk wide,
// comes from a single FF, and is followed by a settle period.)
set_false_path -from [get_pins {u_phy/u_core/o_align_shift_req*/Q}] -to [get_pins {u_phy/*/u_ides10/CALIB}]
