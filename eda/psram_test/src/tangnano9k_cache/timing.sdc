// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
create_clock -name clock -period 37.037 -waveform {0 18.518} [get_ports {clock}]
create_generated_clock -name pclk   -source [get_ports {clock}] -multiply_by 3 [get_pins {pll/rpll_inst/CLKOUT}]
create_generated_clock -name pclk_p -source [get_ports {clock}] -multiply_by 3 -phase 90 [get_pins {pll/rpll_inst/CLKOUTP}]
set_clock_groups -asynchronous -group [get_clocks {clock}] -group [get_clocks {pclk pclk_p}]
create_clock -name rmii_txclk -period 20.000 -waveform {0 10.000} [get_ports {rmii_txclk}]
set_clock_groups -asynchronous -group [get_clocks {rmii_txclk}] -group [get_clocks {clock pclk pclk_p}]
