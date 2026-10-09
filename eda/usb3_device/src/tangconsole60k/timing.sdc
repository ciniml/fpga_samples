create_clock -name sys_clk -period 20 -waveform {0 10} [get_ports {sys_clk}]
create_clock -name usr_clk_in -period 8 -waveform {0 4} [get_ports {usr_clk_in}]
set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {usr_clk_in}]
