create_clock -name clk_fpga -period 29.802 [get_ports {CLK_FPGA}]
create_clock -name clk24 -period 41.667 [get_ports {CLK_24MHz}]
set_clock_groups -asynchronous -group [get_clocks {clk_fpga}] -group [get_clocks {clk24}]
