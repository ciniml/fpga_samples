// Tang Primer 20K: everything but the PHY reset sequencer and the DDR3
// memory side runs on the 50MHz RMII reference clock; the 27MHz crystal
// clocks the Ethernet PHY init and feeds the DDR3 rPLL.
create_clock -name rmii_txclk -period 20.000 -waveform {0 10.000} [get_ports {rmii_txclk}]
create_clock -name clock      -period 37.037 -waveform {0 18.518} [get_ports {clock}]
// rPLL output: 27 MHz x 11 = 297 MHz (OSER8/IDES8 FCLK, DDR3 CK = 148.5 MHz)
create_clock -name fclk -period 3.367 -waveform {0 1.683} [get_nets {fclk}]
// CLKDIV /4: 74.25 MHz memory-side logic clock
create_clock -name pclk -period 13.468 -waveform {0 6.734} [get_nets {pclk}]
// RMII and DDR3 domains are decoupled inside Ddr3Ctrl (toggle synchronisers)
set_clock_groups -asynchronous -group [get_clocks {rmii_txclk}] -group [get_clocks {clock}] -group [get_clocks {fclk pclk}]
