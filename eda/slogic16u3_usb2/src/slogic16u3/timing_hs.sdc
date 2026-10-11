// SLogic16U3 USB 2.0 HS: SerDes tx_pcs_clkout 125 MHz -> pll_60m 60 MHz -> pll_hs960 960 / 480 MHz
// -> CLKDIV /8 = os_pclk 120 MHz (from 960), clk60 60 MHz (from 480): synchronous pair
create_clock -name sd_txclk -period 8 -waveform {0 4} [get_nets {sd_txclk}]
create_clock -name pll_60m -period 16.6667 -waveform {0 8.3333} [get_nets {pll_60m}]
create_clock -name os_f960 -period 1.0417 -waveform {0 0.5208} [get_nets {os_f960}]
create_clock -name os_f480 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f480}]
create_clock -name os_pclk -period 8.3333 -waveform {0 4.1667} [get_nets {u_phy/pclk}]
create_clock -name clk60   -period 16.6667 -waveform {0 8.3333} [get_nets {clk60}]
create_clock -name osc -period 19.0 -waveform {0 9.5} [get_nets {osc}]
create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {sd_txclk pll_60m}] -group [get_clocks {os_f960 os_f480 os_pclk clk60}] -group [get_clocks {osc}] -group [get_clocks {tck}]
// primitive RESET pins (asynchronous, driven from the os_pclk reset synchroniser): no recovery check against the FCLKs
set_false_path -from [get_clocks {os_pclk}] -to [get_clocks {os_f960 os_f480}]
