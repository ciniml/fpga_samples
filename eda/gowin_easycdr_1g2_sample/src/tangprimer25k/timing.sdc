// Timing constraints for the 1.2Gbps EasyCDR loopback sample.
create_clock -name clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]

// RX: 300MHz 4-phase HCLK from u_pll_rx
create_clock -name rxclk_300m_0   -period 3.333 -waveform {0 1.666} [get_nets {rxclk_300m_0}]
create_clock -name rxclk_300m_90  -period 3.333 -waveform {0 1.666} [get_nets {rxclk_300m_90}]
create_clock -name rxclk_300m_180 -period 3.333 -waveform {0 1.666} [get_nets {rxclk_300m_180}]
create_clock -name rxclk_300m_270 -period 3.333 -waveform {0 1.666} [get_nets {rxclk_300m_270}]
// RX parallel clock: 75MHz (share_clk4_o = 300MHz / 4). The IP-internal CLKDIV
// pin is not addressable from SDC, so constrain the top-level net.
create_generated_clock -name pclk_rx -source [get_ports {clk_in}] -master_clock clk_in -divide_by 2 -multiply_by 3 [get_nets {pclk_rx}]

// TX: 600MHz serializer clock and 150MHz parallel clock
create_clock -name txclk_600m -period 1.666 -waveform {0 0.833} [get_nets {txclk_600m}]
create_generated_clock -name txclk_150m -source [get_ports {clk_in}] -master_clock clk_in -divide_by 1 -multiply_by 3 [get_nets {txclk_150m}]

set_false_path -from [get_clocks {clk_in}] -to [get_clocks {rxclk_300m_0 rxclk_300m_90 rxclk_300m_180 rxclk_300m_270}]
# RX-side inspector clock: 150MHz = (DHCE-gated 300MHz)/2
create_generated_clock -name rxclk_150m -source [get_ports {clk_in}] -master_clock clk_in -divide_by 1 -multiply_by 3 [get_nets {rxclk_150m}]

set_false_path -from [get_clocks {clk_in}] -to [get_clocks {pclk_rx txclk_150m rxclk_150m}]
