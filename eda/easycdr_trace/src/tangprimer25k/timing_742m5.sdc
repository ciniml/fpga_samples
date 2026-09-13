// Timing constraints for the EasyCDR trace-link sample (742.5Mbps variant: 370.83MHz x 4 phases, pclk_rx = 92.71MHz).
create_clock -name clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]

// RX: 500MHz 4-phase HCLK from u_pll_rx
create_clock -name rxclk_500m_0   -period 2.6966 -waveform {0 1.3483} [get_nets {rxclk_500m_0}]
create_clock -name rxclk_500m_90  -period 2.6966 -waveform {0 1.3462} [get_nets {rxclk_500m_90}]
create_clock -name rxclk_500m_180 -period 2.6966 -waveform {0 1.3462} [get_nets {rxclk_500m_180}]
create_clock -name rxclk_500m_270 -period 2.6966 -waveform {0 1.3462} [get_nets {rxclk_500m_270}]
// RX parallel clock: 92.71MHz (share_clk4_o = 370.83MHz / 4 = clk_in x 89/48), constrained on the
// top-level net because the IP-internal CLKDIV pin is not addressable.
create_generated_clock -name pclk_rx -source [get_ports {clk_in}] -master_clock clk_in -divide_by 48 -multiply_by 89 [get_nets {pclk_rx}]

// Reverse control channel TX (2Mbps Manchester) runs on clk_in directly.

set_false_path -from [get_clocks {clk_in}] -to [get_clocks {rxclk_500m_0 rxclk_500m_90 rxclk_500m_180 rxclk_500m_270}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {pclk_rx}]
# pclk_rx -> clk_in crossings are all quasi-static or 2FF-synchronized
# (trace_capture: full_sync_s / waddr_s / desc_m, buffer read after freeze),
# but STA treats the domains as related because pclk_rx is generated from
# clk_in - declare them asynchronous to silence bogus hold violations.
set_false_path -from [get_clocks {pclk_rx}] -to [get_clocks {clk_in}]
