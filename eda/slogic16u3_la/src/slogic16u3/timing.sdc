// SLogic16U3 logic analyzer: PHY pclk 125 MHz, sample clock sclk 100 MHz (fclk 400 MHz / 4, fclk from a
// PLL on pclk; the two meet only through LaCore's asynchronous FIFOs and synchronisers), ref_clk ~125 MHz
// (internal oscillator PLL), osc ~52 MHz (JTAG status). The USB 3.0 PHY IP also runs logic on the lane's
// recovered receive clock and on its register-port clock (both cross to pclk inside the IP).
create_clock -name pclk -period 8 -waveform {0 4} [get_nets {pclk}]
create_clock -name sclk -period 10 -waveform {0 5} [get_nets {sclk}]
create_clock -name fclk -period 2.5 -waveform {0 1.25} [get_nets {fclk}]
create_clock -name ref_clk -period 8 -waveform {0 4} [get_nets {ref_clk}]
create_clock -name rx_clk -period 8 -waveform {0 4} [get_nets {u_serdes/q0_lane0_fabric_rx_clk}]
create_clock -name drp_clk -period 10 -waveform {0 5} [get_nets {u_serdes/upar_arbiter_wrap_SerDes_Top_inst_drp_clk_o[0]}]
create_clock -name osc -period 19.0 -waveform {0 9.5} [get_nets {osc}]
create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {pclk}] -group [get_clocks {sclk}] -group [get_clocks {fclk}] -group [get_clocks {rx_clk}] -group [get_clocks {drp_clk}] -group [get_clocks {ref_clk}] -group [get_clocks {osc}] -group [get_clocks {tck}]
