// Tang Console 60K USB 3.0, REF=1 (top_ref.v): Gowin's reference controller on the Lane2 PHY IP
create_clock -name sys_clk -period 20 -waveform {0 10} [get_ports {sys_clk}]
create_clock -name pclk -period 8 -waveform {0 4} [get_nets {pclk}]
create_clock -name rx_clk -period 8 -waveform {0 4} [get_nets {u_serdes/q0_lane2_fabric_rx_clk}]
create_clock -name drp_clk -period 10 -waveform {0 5} [get_nets {u_serdes/upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[2]}]
create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {pclk}] -group [get_clocks {rx_clk}] -group [get_clocks {drp_clk}] -group [get_clocks {sys_clk}] -group [get_clocks {tck}]
