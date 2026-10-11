// TRACE=1: the EasyCDR trace link clocks (pll_trace500 from pclk: 500 MHz OSER10 FCLK, CLKDIV /5 = 100 MHz).
// The trace front end samples on pclk and hands records to the link clock through its asynchronous FIFO.
create_clock -name tr_f500 -period 2 -waveform {0 1} [get_nets {tr_f500}]
create_clock -name tr_clk -period 10 -waveform {0 5} [get_nets {tr_clk}]
set_clock_groups -asynchronous -group [get_clocks {pclk}] -group [get_clocks {tr_f500 tr_clk}]
set_false_path -from [get_clocks {tr_clk}] -to [get_clocks {tr_f500}]
