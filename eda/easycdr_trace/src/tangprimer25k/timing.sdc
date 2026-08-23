// Timing constraints for the EasyCDR trace-link sample (1Gbps, 8b10b).
create_clock -name clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]

// RX: 500MHz 4-phase HCLK from u_pll_rx
create_clock -name rxclk_500m_0   -period 2.0 -waveform {0 1.0} [get_nets {rxclk_500m_0}]
create_clock -name rxclk_500m_90  -period 2.0 -waveform {0 1.0} [get_nets {rxclk_500m_90}]
create_clock -name rxclk_500m_180 -period 2.0 -waveform {0 1.0} [get_nets {rxclk_500m_180}]
create_clock -name rxclk_500m_270 -period 2.0 -waveform {0 1.0} [get_nets {rxclk_500m_270}]
// RX parallel clock: 125MHz (share_clk4_o = 500MHz / 4), constrained on the
// top-level net because the IP-internal CLKDIV pin is not addressable.
create_generated_clock -name pclk_rx -source [get_ports {clk_in}] -master_clock clk_in -divide_by 2 -multiply_by 5 [get_nets {pclk_rx}]

// TX: 500MHz serializer clock and 100MHz parallel clock
create_clock -name txclk_500m -period 2.0 -waveform {0 1.0} [get_nets {txclk_500m}]
create_generated_clock -name txclk_100m -source [get_ports {clk_in}] -master_clock clk_in -divide_by 1 -multiply_by 2 [get_nets {txclk_100m}]

set_false_path -from [get_clocks {clk_in}] -to [get_clocks {rxclk_500m_0 rxclk_500m_90 rxclk_500m_180 rxclk_500m_270}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {pclk_rx txclk_100m}]
