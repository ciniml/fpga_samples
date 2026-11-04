// DK_LED-RXCARD_GW3A20: appended to timing.sdc by project.tcl for
// HUB75_IMPL=2 (DDR2 frame buffer) only (the nets are removed otherwise).
// 333.3 MHz fclk (PLL clkout3) and the 83.3 MHz pclk from CLKDIV / 4; the
// fabric runs on mclk, fclk only clocks the IOLOGIC (OSER8 / IDES8).
create_generated_clock -name fclk -source [get_ports {clk50}] -master_clock clk50 -divide_by 3 -multiply_by 20 [get_nets {fclk}]
create_generated_clock -name mclk -source [get_ports {clk50}] -master_clock clk50 -divide_by 3 -multiply_by 5 [get_nets {mclk}]
set_clock_groups -asynchronous -group [get_clocks {fclk mclk}] -group [get_clocks {sys_clk}] -group [get_clocks {disp_clk}] -group [get_clocks {rgmii_rxc}]
report_timing -setup -max_paths 20 -max_common_paths 1 -from_clock [get_clocks {mclk}] -to_clock [get_clocks {mclk}]
