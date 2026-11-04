// DK_LED-RXCARD_GW3A20: appended to timing.sdc by project.tcl for
// TXC_SHIFTED=1 only (the 270° PLL output is unused and removed otherwise).
// TXD / TX_CTL ODDRs on the 270° clock; their inputs come from sys_clk 6 ns
// earlier.
create_generated_clock -name clk270 -source [get_ports {clk50}] -master_clock clk50 -divide_by 2 -multiply_by 5 -phase 270 [get_nets {clk270}]
report_timing -setup -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {sys_clk}] -to_clock [get_clocks {clk270}]
report_timing -hold -max_paths 10 -max_common_paths 1 -from_clock [get_clocks {sys_clk}] -to_clock [get_clocks {clk270}]
