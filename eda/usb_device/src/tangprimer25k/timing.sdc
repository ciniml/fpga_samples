// USB device bring-up: 50MHz crystal -> PLL 240MHz (FCLK) / 60MHz (PCLK)
create_clock -name clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]
create_clock -name fclk_240m -period 4.1667 -waveform {0 2.0833} [get_nets {fclk_240m}]
create_clock -name pclk_60m  -period 16.6667 -waveform {0 8.3333} [get_nets {pclk_60m}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {pclk_60m fclk_240m}]
// pclk -> fclk: only the reset (rst_sr -> OSER8/IDES8 RESET) crosses; the data
// paths are inside the IDES8/OSER8 primitives (PCLK/FCLK from the same PLL)
set_false_path -from [get_clocks {pclk_60m}] -to [get_clocks {fclk_240m}]
