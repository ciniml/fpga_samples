// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
create_clock -name rmii_txclk -period 20.000 -waveform {0 10.000} [get_ports {rmii_txclk}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_ext/reset_seq*/SET}]
set_false_path -from [get_pins {reset_button_0_s1/Q}] -to [get_pins {reset_seq_ext/reset_seq*/D}]
create_clock -name clock -period 37.037 -waveform {0 18.518} [get_ports {clock}]
// PSRAM domain: rPLL 27MHz x3 = 81MHz and its +90 degree copy for CK
create_generated_clock -name pclk   -source [get_ports {clock}] -multiply_by 2 [get_pins {pll/rpll_inst/CLKOUT}]
create_generated_clock -name pclk_p -source [get_ports {clock}] -multiply_by 2 -phase 90 [get_pins {pll/rpll_inst/CLKOUTP}]
// asynchronous to the RMII clock; the cache crosses with toggle synchronizers
set_clock_groups -asynchronous -group [get_clocks {rmii_txclk}] -group [get_clocks {clock pclk pclk_p}]
