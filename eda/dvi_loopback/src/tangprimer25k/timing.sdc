// timing.sdc — DVI 1080p60 loopback (Tang Primer 25K)

// Board clock
create_clock -name clock -period 20 -waveform {0 10} [get_ports {clock}]

// TX: 50 MHz -> 27 MHz -> 148.5 MHz pixel / 742.5 MHz serial
create_generated_clock -name clock_27 -source [get_ports {clock}] -master_clock clock -multiply_by 27 -divide_by 50 [get_pins {u_pll_27/PLLA_inst/CLKOUT0}]
create_generated_clock -name tx_pclk -source [get_pins {u_pll_27/PLLA_inst/CLKOUT0}] -master_clock clock_27 -multiply_by 11 -divide_by 2 [get_pins {u_pll_tx/PLLA_inst/CLKOUT0}]
create_generated_clock -name tx_fclk -source [get_pins {u_pll_27/PLLA_inst/CLKOUT0}] -master_clock clock_27 -multiply_by 55 -divide_by 2 [get_pins {u_pll_tx/PLLA_inst/CLKOUT1}]

// RX: cable pixel clock 148.5 MHz
create_clock -name rx_cable_clk -period 6.734 -waveform {0 3.367} [get_ports {rx_clk_p}]
create_generated_clock -name rx_pclk -source [get_ports {rx_clk_p}] -master_clock rx_cable_clk -multiply_by 1 [get_pins {pll_main/PLLA_inst/CLKOUT0}]
create_generated_clock -name rx_fclk -source [get_ports {rx_clk_p}] -master_clock rx_cable_clk -multiply_by 5 [get_pins {pll_main/PLLA_inst/CLKOUT1}]

// Domains are asynchronous to each other (RX follows the cable). All
// crossings are 2FF / toggle handshakes / quasi-static (loop_check.sv).
set_clock_groups -asynchronous -group [get_clocks {clock clock_27}] -group [get_clocks {tx_pclk tx_fclk}] -group [get_clocks {rx_cable_clk rx_pclk rx_fclk}]

// ---- RX PHY exceptions (as eda/dvi_capture) ----
// IODELAY tap / DLYSTEP registers are quasi-static.
set_false_path -from [get_pins {u_phy/*/delay_tap_reg*/Q}]
set_false_path -from [get_pins {u_phy/*/dlystep*/Q}]
// Serial data path: aligned by the IODELAY tap and word alignment.
set_false_path -from [get_ports {rx_d0_p rx_d1_p rx_d2_p}]
// Reset into IDES10 RESET (fclk) is held for many cycles.
set_false_path -from [get_pins {reset_seq_pclk/reset_seq_0_s0/Q}] -to [get_pins {u_phy/*/u_ides10/RESET}]
// align_shift_req is one pclk (= 5 fclk) wide, followed by a settle period.
set_false_path -from [get_pins {u_phy/u_core/o_align_shift_req*/Q}] -to [get_pins {u_phy/*/u_ides10/CALIB}]

// ---- TX exceptions (as eda/dvi_out_tpg) ----
set_false_path -from [get_pins {u_reset_tx/reset_seq_0_s0/Q}] -to [get_pins {g_oser*u_oser/RESET}]
