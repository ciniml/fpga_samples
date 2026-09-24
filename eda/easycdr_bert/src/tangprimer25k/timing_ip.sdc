// Gowin-IP receiver variant (USE_EASYCDR_IP=1). Template: project.tcl fills @FP@/@FH@ (FCLK period)
// and @PM@/@PD@ (pclk from 50MHz) per RATE variant and writes timing_gen.sdc into the build directory.
// EasyCDR BERT (1Gbps raw 16-bit). RX: 500MHz x4 phases from u_pll_rx,
// parallel clock share_clk4_o = 125MHz. TX: separate 500MHz PLL (BANK1
// HCLK group) + OSER8 with PCLK = the RX parallel clock (both 125MHz,
// unrelated phase - the OSER8 PCLK/FCLK pair is aligned by CLKDIV).
create_clock -name clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]
// (own PHY: the PLL lives in u_phy; with USE_EASYCDR_IP use the top-level names)
create_clock -name rxclk_500m_0   -period @FP@ -waveform {0 @FH@} [get_nets {u_phy/rxclk_500m_0}]
create_clock -name rxclk_500m_90  -period @FP@ -waveform {0 @FH@} [get_nets {u_phy/rxclk_500m_90}]
create_clock -name rxclk_500m_180 -period @FP@ -waveform {0 @FH@} [get_nets {u_phy/rxclk_500m_180}]
create_clock -name rxclk_500m_270 -period @FP@ -waveform {0 @FH@} [get_nets {u_phy/rxclk_500m_270}]
create_generated_clock -name pclk -source [get_ports {clk_in}] -master_clock clk_in -divide_by @PD@ -multiply_by @PM@ [get_nets {pclk}]
create_clock -name txclk_500m -period @FP@ -waveform {0 @FH@} [get_nets {txclk_500m}]
create_generated_clock -name txclk_125m -source [get_ports {clk_in}] -master_clock clk_in -divide_by @PD@ -multiply_by @PM@ [get_nets {txclk_125m}]

set_false_path -from [get_clocks {clk_in}] -to [get_clocks {rxclk_500m_0 rxclk_500m_90 rxclk_500m_180 rxclk_500m_270}]
// host <-> link crossings are toggle-handshaked / quasi-static (BertHost)
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {pclk txclk_125m}]
set_false_path -from [get_clocks {pclk txclk_125m}] -to [get_clocks {clk_in}]
// pclk (RX) -> txclk_125m (OSER8 PCLK): 8-bit word crossed by a 2-entry
// handshake-free FIFO in top.v (same nominal frequency, PLLs from the same
// crystal, so the pointer distance is constant)
set_false_path -from [get_clocks {pclk}] -to [get_clocks {txclk_125m}]
set_false_path -from [get_clocks {txclk_125m}] -to [get_clocks {pclk}]
