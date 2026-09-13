// Nano9K TX-only, 742.5Mbps variant: 27MHz input, 371.25MHz serializer, 74.25MHz parallel clock.
create_clock -name clk_in -period 37.037 -waveform {0 18.518} [get_ports {clk_in}]
create_clock -name txclk_ser -period 2.6936 -waveform {0 1.3468} [get_nets {txclk_ser}]
create_generated_clock -name txclk_par -source [get_ports {clk_in}] -master_clock clk_in -divide_by 20 -multiply_by 55 [get_nets {txclk_par}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {txclk_ser txclk_par}]
set_false_path -from [get_clocks {txclk_par}] -to [get_clocks {clk_in}]
