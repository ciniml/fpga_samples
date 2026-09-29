// USB device bring-up: 50MHz crystal -> PLL 240MHz (FCLK) / 60MHz (PCLK)
create_clock -name clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]
create_clock -name pclk_60m  -period 16.6667 -waveform {0 8.3333} [get_nets {pclk_60m}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {pclk_60m}]
// HS oversampler / transmitter: 480 MHz x 4 phases (u_pll_os, fed by the 60 MHz PLL output), PCLK = /4 = 120 MHz
create_clock -name os_f0   -period 2.0833 -waveform {0 1.0417} [get_nets {os_f0}]
create_clock -name os_f90  -period 2.0833 -waveform {0 1.0417} [get_nets {os_f90}]
create_clock -name os_f180 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f180}]
create_clock -name os_f270 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f270}]
create_generated_clock -name os_pclk -source [get_ports {clk_in}] -master_clock clk_in -divide_by 5 -multiply_by 12 [get_nets {os_pclk}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {os_f0 os_f90 os_f180 os_f270 os_pclk}]
// PCLK <-> 60 MHz: gray-pointer async FIFO and 2FF synchronisers (usb_hs_os32)
set_false_path -from [get_clocks {os_pclk}] -to [get_clocks {pclk_60m}]
set_false_path -from [get_clocks {pclk_60m}] -to [get_clocks {os_pclk}]
