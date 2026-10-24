// DK_LED-RXCARD_GW3A20: ethernet_hub75 timing constraints.
create_clock -name clk50 -period 20.000 -waveform {0 10.000} [get_ports {clk50}]
create_clock -name rgmii_rxc -period 8.000 -waveform {0 4.000} [get_ports {rgmii_rxc}]
// PLLB (VCO 1000 MHz): 125 MHz system / RGMII TX, 50 MHz display
create_generated_clock -name sys_clk -source [get_ports {clk50}] -master_clock clk50 -divide_by 2 -multiply_by 5 [get_nets {sys_clk}]
create_generated_clock -name disp_clk -source [get_ports {clk50}] -master_clock clk50 -divide_by 1 -multiply_by 1 [get_nets {disp_clk}]

// RGMII receive with the PHY's RXC delay on (Rtl8211eInit): data valid
// at least 1.2 ns before and after each RXC edge at the pins.
set_input_delay -clock rgmii_rxc -max 2.800 [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock rgmii_rxc -min 1.200 [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock rgmii_rxc -clock_fall -max 2.800 -add_delay [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]
set_input_delay -clock rgmii_rxc -clock_fall -min 1.200 -add_delay [get_ports {rgmii_rx_ctl rgmii_rxd[*]}]

// PHY receive / system + RGMII transmit / display: crossings are
// synchronisers and dual-clock memories
set_clock_groups -asynchronous -group [get_clocks {rgmii_rxc}] -group [get_clocks {sys_clk}] -group [get_clocks {disp_clk}]

report_timing -setup -max_paths 300 -max_common_paths 1
