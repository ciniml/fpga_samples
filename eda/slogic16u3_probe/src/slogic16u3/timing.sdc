create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
create_clock -name osc -period 19.0 -waveform {0 9.5} [get_nets {osc}]
set_clock_groups -asynchronous -group [get_clocks {tck}] -group [get_clocks {osc}]
