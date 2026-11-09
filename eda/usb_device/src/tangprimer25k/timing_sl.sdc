// USB device (Pmod USB HS Single): 50MHz crystal -> pll_usb 60 MHz -> pll_hs960 960 / 480 MHz
// -> CLKDIV /8 = os_pclk 120 MHz (from 960), clk60 60 MHz (from 480): synchronous pair
create_clock -name clk_in  -period 20 -waveform {0 10} [get_ports {clk_in}]
create_clock -name pll_60m -period 16.6667 -waveform {0 8.3333} [get_nets {pll_60m}]
create_clock -name os_f960 -period 1.0417 -waveform {0 0.5208} [get_nets {os_f960}]
create_clock -name os_f480 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f480}]
create_clock -name os_pclk -period 8.3333 -waveform {0 4.1667} [get_nets {os_pclk}]
create_clock -name clk60   -period 16.6667 -waveform {0 8.3333} [get_nets {clk60}]
set_clock_groups -asynchronous -group [get_clocks {clk_in pll_60m}] -group [get_clocks {os_f960 os_f480 os_pclk clk60}]
// primitive RESET pins (asynchronous, driven from the os_pclk reset synchroniser): no recovery check against the FCLKs
set_false_path -from [get_clocks {os_pclk}] -to [get_clocks {os_f960 os_f480}]
// The two CLKDIVs (pclk from 960 MHz, clk60 from 480 MHz) leave reset up to one 480 MHz period apart, which the
// clock model above does not know: give the crossings that much setup uncertainty, so that a path that only
// works with one of the start-up offsets cannot pass (seen as good / bad receive depending on the load).
set_clock_uncertainty -setup -from [get_clocks {clk60}] -to [get_clocks {os_pclk}] 2.1
set_clock_uncertainty -setup -from [get_clocks {os_pclk}] -to [get_clocks {clk60}] 2.1
report_timing -setup -max_paths 20 -max_common_paths 2 -from_clock [get_clocks {clk60}] -to_clock [get_clocks {os_pclk}]
report_timing -setup -max_paths 20 -max_common_paths 2 -from_clock [get_clocks {os_pclk}] -to_clock [get_clocks {clk60}]
report_timing -hold -max_paths 20 -max_common_paths 2 -from_clock [get_clocks {os_pclk}] -to_clock [get_clocks {clk60}]
report_timing -hold -max_paths 20 -max_common_paths 2 -from_clock [get_clocks {clk60}] -to_clock [get_clocks {os_pclk}]
