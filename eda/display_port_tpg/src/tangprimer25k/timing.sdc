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
