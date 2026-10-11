// SLogic16U3 USB 2.0 (full speed): SerDes tx_pcs_clkout 125 MHz -> PLLA 60 MHz; internal oscillator ~52 MHz (JTAG status)
create_clock -name sd_txclk -period 8 -waveform {0 4} [get_nets {sd_txclk}]
create_clock -name clk60 -period 16.6667 -waveform {0 8.3333} [get_nets {clk60}]
create_clock -name osc -period 19.0 -waveform {0 9.5} [get_nets {osc}]
create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {sd_txclk}] -group [get_clocks {clk60}] -group [get_clocks {osc}] -group [get_clocks {tck}]
