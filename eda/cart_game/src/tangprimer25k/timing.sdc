// cart_game: 50 MHz crystal -> PLLA 100 / 200 MHz (GameCart / QspiRom, derived by the tools)
//            50 MHz -> pll_usb 60 MHz -> pll_hs960 960 / 480 MHz -> CLKDIV /8: os_pclk 120 MHz, clk60 60 MHz (USB)
// The USB clocks meet the cartridge clocks only in the two ByteAfifos (gray pointers over 2 flip-flops).
create_clock -name clk_in  -period 20 -waveform {0 10} [get_ports {clk_in}]
create_clock -name pll_60m -period 16.6667 -waveform {0 8.3333} [get_nets {pll_60m}]
create_clock -name os_f960 -period 1.0417 -waveform {0 0.5208} [get_nets {os_f960}]
create_clock -name os_f480 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f480}]
create_clock -name os_pclk -period 8.3333 -waveform {0 4.1667} [get_pins {u_phy/u_clkdiv_p/CLKOUT}]
create_clock -name clk60   -period 16.6667 -waveform {0 8.3333} [get_nets {clk60}]
set_clock_groups -asynchronous -group [get_clocks {os_f960 os_f480 os_pclk clk60}]
// (as eda/usb_device timing_sl.sdc)
set_false_path -from [get_clocks {os_pclk}] -to [get_clocks {os_f960 os_f480}]
set_clock_uncertainty -setup -from [get_clocks {clk60}] -to [get_clocks {os_pclk}] 2.1
set_clock_uncertainty -setup -from [get_clocks {os_pclk}] -to [get_clocks {clk60}] 2.1
