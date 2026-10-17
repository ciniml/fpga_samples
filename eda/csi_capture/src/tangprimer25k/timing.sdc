// eda/csi_capture — Tang Primer 25K

create_clock -name clock -period 20 -waveform {0 10} [get_ports {clock}]
// 500 MHz x 4 phases (PLL_T) and the /4 word clock
create_clock -name rxclk_500m_0   -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_0}]
create_clock -name rxclk_500m_90  -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_90}]
create_clock -name rxclk_500m_180 -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_180}]
create_clock -name rxclk_500m_270 -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_270}]
create_generated_clock -name pclk -source [get_ports {clock}] -master_clock clock -divide_by 2 -multiply_by 5 [get_pins {u_phy/u_clkdiv/CLKOUT}]

// The camera lanes are sampled asynchronously (oversampling).
set_false_path -from [get_ports {csi_clk_p csi_d0_p csi_d1_p}]

// System (50 MHz) <-> word clock (125 MHz): toggle handshakes, quasi-static
// settings, and memories read only while they are not written.
set_false_path -from [get_clocks {clock}] -to [get_clocks {pclk rxclk_500m_0 rxclk_500m_90 rxclk_500m_180 rxclk_500m_270}]
set_false_path -from [get_clocks {pclk}] -to [get_clocks {clock}]
