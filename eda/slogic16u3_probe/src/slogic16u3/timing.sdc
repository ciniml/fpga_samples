create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
create_clock -name osc -period 19.0 -waveform {0 9.5} [get_nets {osc}]
set_clock_groups -asynchronous -group [get_clocks {tck}] -group [get_clocks {osc}]
# SerDes probe (SERDES=1, SERDES_IP): the lane clocks into the fabric (125 MHz expected with a 125 MHz reference)
create_clock -name sd_refclk -period 8 [get_nets {c_refclk}]
create_clock -name sd_txclk -period 8 [get_nets {c_txclk}]
create_clock -name sd_rxclk -period 8 [get_nets {c_rxclk}]
set_clock_groups -asynchronous -group [get_clocks {sd_refclk}] -group [get_clocks {sd_txclk}] -group [get_clocks {sd_rxclk}] -group [get_clocks {osc}] -group [get_clocks {tck}]
