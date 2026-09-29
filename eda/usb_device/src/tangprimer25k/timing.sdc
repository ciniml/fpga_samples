// USB device: 50MHz crystal -> pll_usb 60 MHz -> pll_usb_os 480 MHz x 4 phases -> CLKDIV /4 = os_pclk 120 MHz, /8 = clk60 60 MHz
create_clock -name clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]
create_clock -name pll_60m -period 16.6667 -waveform {0 8.3333} [get_nets {pll_60m}]
create_clock -name os_f0   -period 2.0833 -waveform {0 1.0417} [get_nets {os_f0}]
create_clock -name os_f90  -period 2.0833 -waveform {0 1.0417} [get_nets {os_f90}]
create_clock -name os_f180 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f180}]
create_clock -name os_f270 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f270}]
// the two divided clocks are synchronous (same CLKDIV source, edges coincide): no false paths between them
create_generated_clock -name os_pclk -source [get_ports {clk_in}] -master_clock clk_in -divide_by 5 -multiply_by 12 [get_nets {os_pclk}]
create_generated_clock -name clk60   -source [get_ports {clk_in}] -master_clock clk_in -divide_by 5 -multiply_by 6  [get_nets {clk60}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {os_f0 os_f90 os_f180 os_f270 os_pclk clk60}]
set_false_path -from [get_clocks {clk60 os_pclk}] -to [get_clocks {clk_in}]
// primitive RESET pins (asynchronous, driven from the os_pclk reset synchroniser): no recovery check against the 480 MHz phases
set_false_path -from [get_clocks {os_pclk}] -to [get_clocks {os_f0 os_f90 os_f180 os_f270}]
report_timing -setup -max_paths 60 -max_common_paths 2 -from_clock [get_clocks {os_pclk}] -to_clock [get_clocks {os_pclk}]
report_timing -setup -max_paths 30 -max_common_paths 2 -from_clock [get_clocks {clk60}] -to_clock [get_clocks {os_pclk}]
report_timing -setup -max_paths 30 -max_common_paths 2 -from_clock [get_clocks {os_pclk}] -to_clock [get_clocks {clk60}]
