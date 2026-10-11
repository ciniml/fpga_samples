// SLogic16U3 USB 3.0, REF=1 (top_ref.v): as timing.sdc without ref_clk (the PHY IP leaves it unused, the net is swept)
// The USB 3.0 PHY IP also runs logic on the lane's recovered receive clock (125 MHz, into its elastic
// buffer) and on the register-port clock of its upar arbiter; both cross to pclk inside the IP.
create_clock -name pclk -period 8 -waveform {0 4} [get_nets {pclk}]
create_clock -name rx_clk -period 8 -waveform {0 4} [get_nets {u_serdes/q0_lane0_fabric_rx_clk}]
create_clock -name drp_clk -period 10 -waveform {0 5} [get_nets {u_serdes/upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[0]}]
create_clock -name osc -period 19.0 -waveform {0 9.5} [get_nets {osc}]
create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {pclk}] -group [get_clocks {rx_clk}] -group [get_clocks {drp_clk}] -group [get_clocks {osc}] -group [get_clocks {tck}]
