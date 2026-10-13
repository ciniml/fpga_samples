// Lane 3 variant (LANE=3, Console USB-A port 2P)
// Tang Console 60K USB 3.0: PHY pclk 125 MHz, ref_clk 125 MHz (PLLA from sys_clk), sys_clk 50 MHz (UART / JTAG status).
// The USB 3.0 PHY IP also runs logic on the lane's recovered receive clock and on the register-port clock
// of its upar arbiter; both cross to pclk inside the IP.
create_clock -name sys_clk -period 20 -waveform {0 10} [get_ports {sys_clk}]
create_clock -name pclk -period 8 -waveform {0 4} [get_nets {pclk}]
create_clock -name rx_clk -period 8 -waveform {0 4} [get_nets {u_serdes/q0_lane3_fabric_rx_clk}]
create_clock -name drp_clk -period 10 -waveform {0 5} [get_nets {dbg_drp_clk_Z}]
create_clock -name tck -period 100 -waveform {0 50} [get_ports {tck_pad_i}]
set_clock_groups -asynchronous -group [get_clocks {pclk}] -group [get_clocks {rx_clk}] -group [get_clocks {drp_clk}] -group [get_clocks {sys_clk}] -group [get_clocks {tck}]
