// eda/camera_dvi — Tang Primer 25K

create_clock -name clock -period 20 -waveform {0 10} [get_ports {clock}]
// camera: 500 MHz x 4 phases (PLL_T) and the /4 word clock (as eda/csi_capture)
create_clock -name rxclk_500m_0   -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_0}]
create_clock -name rxclk_500m_90  -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_90}]
create_clock -name rxclk_500m_180 -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_180}]
create_clock -name rxclk_500m_270 -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_270}]
create_generated_clock -name pclk -source [get_ports {clock}] -master_clock clock -divide_by 2 -multiply_by 5 [get_pins {u_phy/u_clkdiv/CLKOUT}]
// display: 50 MHz -> 27 MHz -> 74.25 MHz pixel / 371.25 MHz serial (as eda/dvi_loopback RATE=720P)
create_generated_clock -name clock_27 -source [get_ports {clock}] -master_clock clock -multiply_by 27 -divide_by 50 [get_pins {u_pll_27/PLLA_inst/CLKOUT0}]
create_generated_clock -name tx_pclk -source [get_pins {u_pll_27/PLLA_inst/CLKOUT0}] -master_clock clock_27 -multiply_by 11 -divide_by 4 [get_pins {u_pll_tx/PLLA_inst/CLKOUT0}]
create_generated_clock -name tx_fclk -source [get_pins {u_pll_27/PLLA_inst/CLKOUT0}] -master_clock clock_27 -multiply_by 55 -divide_by 4 [get_pins {u_pll_tx/PLLA_inst/CLKOUT1}]

// The camera lanes are sampled asynchronously (oversampling).
set_false_path -from [get_ports {csi_clk_p csi_d0_p csi_d1_p}]

// System (50 MHz) <-> camera word clock (125 MHz): toggle handshakes,
// quasi-static settings, memories read only while they are not written.
set_false_path -from [get_clocks {clock}] -to [get_clocks {pclk rxclk_500m_0 rxclk_500m_90 rxclk_500m_180 rxclk_500m_270}]
set_false_path -from [get_clocks {pclk}] -to [get_clocks {clock}]
// Camera (pclk) <-> display (tx_pclk): the raw line ring (rows written and
// read are kept apart by the genlock) and the row 0 toggle (2FF).
// System <-> display: quasi-static design registers, 2FF toggles, status
// read for debugging.
set_clock_groups -asynchronous -group [get_clocks {pclk}] -group [get_clocks {tx_pclk tx_fclk}]
set_clock_groups -asynchronous -group [get_clocks {clock clock_27}] -group [get_clocks {tx_pclk tx_fclk}]

// TX: reset into the OSER10s is held for many cycles.
set_false_path -from [get_pins {u_reset_tx/reset_seq_0_s0/Q}] -to [get_pins {g_oser*u_oser/RESET}]
