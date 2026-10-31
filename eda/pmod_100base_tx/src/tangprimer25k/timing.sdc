// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// 50 MHz crystal -> pll_eth100 250 MHz (IDES4 FCLK) -> CLKDIV /2 = pclk 125 MHz (all logic)
create_clock -name clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]
create_clock -name fclk -period 4 -waveform {0 2} [get_nets {u_phy/fclk}]
create_generated_clock -name pclk -source [get_ports {clk_in}] -master_clock clk_in -multiply_by 5 -divide_by 2 [get_nets {u_phy/pclk}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {fclk pclk}]
// primitive RESET pins of the IDES4 (driven from the pclk reset synchroniser)
set_false_path -from [get_clocks {pclk}] -to [get_clocks {fclk}]
report_timing -setup -max_paths 30 -max_common_paths 2 -from_clock [get_clocks {pclk}] -to_clock [get_clocks {pclk}]
