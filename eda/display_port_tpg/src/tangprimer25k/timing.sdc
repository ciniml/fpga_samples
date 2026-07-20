// timing.sdc
// Copyright 2026 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

// Board reference clock (50 MHz).
create_clock -name clock -period 20 -waveform {0 10} [get_ports {clock}]

// PLL outputs. Targets are nominal — adjust if gowin_pll/gowin_pll_27 are
// reconfigured. clock_byte (162 MHz) feeds the entire DP pipeline +
// OSER10 PCLK; clock_serial (810 MHz) is OSER10's FCLK and is consumed
// only inside the OSER10 primitive.
//
//   clock_27     : 27 MHz  → AUX subsystem
//   clock_byte   : 162 MHz → main link byte clock (PCLK)
//   clock_serial : 810 MHz → OSER10 FCLK (DDR → 1.62 Gbps lane bit rate)
create_generated_clock -name clock_27     -source [get_ports {clock}] -divide_by 50 -multiply_by 27 [get_pins {pll_27/PLLA_inst/CLKOUT0}]
create_generated_clock -name clock_byte   -source [get_pins {pll_27/PLLA_inst/CLKOUT0}] -divide_by 1 -multiply_by 6 [get_pins {pll_dp/PLLA_inst/CLKOUT0}]
create_generated_clock -name clock_serial -source [get_pins {pll_27/PLLA_inst/CLKOUT0}] -divide_by 1 -multiply_by 30 [get_pins {pll_dp/PLLA_inst/CLKOUT1}]

// The CPU/AUX subsystem (clock_27) talks to the main-link datapath
// (clock_byte) only through the synchronizers inside dp_source_top;
// treat the domains as asynchronous.
set_clock_groups -asynchronous -group [get_clocks {clock_27}] -group [get_clocks {clock_byte clock_serial}]

// The video-configuration synchronizer outputs are strictly static
// while the link is running: the firmware programs them before setting
// the enable bits and never changes them afterwards. Exclude them from
// link-clock timing.
set_false_path -from [get_pins {dp_source/sync_htotal/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_vtotal/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_hstart/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_vstart/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_hwidth/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_vheight/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_hsw_hsp/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_vsw_vsp/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_mvid/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_nvid/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_misc/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_tu_active/sync*/Q}]
// (sync_lane_count is optimized away — lane_count is unused until
// multi-lane support — so it must not appear here.)
set_false_path -from [get_pins {dp_source/sync_ef/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_altseed/sync*/Q}]
// Quasi-static line-accounting registers (written before video_enable);
// consumers are the registered-constant pipeline in video_framer.
set_false_path -from [get_pins {dp_source/sync_line_symbols/sync*/Q}]
set_false_path -from [get_pins {dp_source/sync_active_window/sync*/Q}]
// lane_count feeds the quasi-static four_lane_r re-register only (set
// during training, before video).
set_false_path -from [get_pins {dp_source/sync_lane_count/sync*/Q}]
// The following are LEVEL signals that transition exactly once at
// bring-up in CONTINUOUS_BYTE_TICK mode (byte_tick == enable, the
// scrambler valid == enable delayed) and every consumer tolerates a
// ragged +-1-cycle transition: the framer parks at slot 0 while
// disabled, the pixel FIFOs are held cleared until video_enable, and
// pre-training encoder output is meaningless. Cutting them removes
// their huge fanout cones from the 162 MHz closure.
set_false_path -from [get_pins {dp_source/main_link/u_lane0/enable_r_s0/Q}]
set_false_path -from [get_pins {dp_source/main_link/u_lane0/four_lane_r_s0/Q}]
set_false_path -from [get_pins {dp_source/four_lane_r_s0/Q}]
set_false_path -from [get_pins {dp_source/v_enable_lr_s0/Q}]
set_false_path -from [get_pins {dp_source/main_link/u_lane0/u_sc/o_valid_s0/Q}]
