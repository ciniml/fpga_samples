// SLogic16U3 USB 3.0 lane probe: only the internal oscillator (~52 MHz) clocks fabric logic
create_clock -name osc -period 19.0 -waveform {0 9.5} [get_nets {osc}]
create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {osc}] -group [get_clocks {tck}]
