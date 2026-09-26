// timing.sdc — DVI input → HUB75 display.

// On-board 50 MHz oscillator (HUB75 clock domain).
create_clock -name clock -period 20 -waveform {0 10} [get_ports {clock}]

// Cable pixel clock recovered from the DVI CLK pair (74.25 MHz).
create_clock -name dvi_pclk -period 13.468 -waveform {0 6.734} [get_ports {dvi_clk_p}]

// PLL outputs, named explicitly so exceptions below can reference them.
create_generated_clock -name pclk -source [get_ports {dvi_clk_p}] -master_clock dvi_pclk -multiply_by 1 [get_pins {pll_main/PLLA_inst/CLKOUT0}]
create_generated_clock -name fclk -source [get_ports {dvi_clk_p}] -master_clock dvi_pclk -multiply_by 5 [get_pins {pll_main/PLLA_inst/CLKOUT1}]

// IODELAY tap registers are quasi-static (see eda/dvi_capture).
set_false_path -from [get_pins {u_phy/*/delay_tap_reg*/Q}]
set_false_path -from [get_pins {u_phy/*/dlystep*/Q}]

// Serial data paths: alignment is by calibration, not static timing.
set_false_path -from [get_ports {dvi_d0_p dvi_d1_p dvi_d2_p}]
set_false_path -from [get_clocks {dvi_pclk}] -to [get_clocks {fclk}]

// reset_seq output is held for many cycles.
set_false_path -from [get_pins {reset_seq_pclk/reset_seq_0_s0/Q}] -to [get_pins {u_phy/*/u_ides10/RESET}]

// CALIB pulse is 5 fclk wide with a settle period after it.
set_false_path -from [get_pins {u_phy/u_core/o_align_shift_req*/Q}] -to [get_pins {u_phy/*/u_ides10/CALIB}]

// The recovered video domain and the 50 MHz board domain (HUB75, DDC,
// UART) only meet through 2FF / gray-code / quasi-static crossings
// (u_fifo, crop_to_hub75's flip-pending sync, loop_check).
set_clock_groups -asynchronous -group [get_clocks {clock}] -group [get_clocks {dvi_pclk pclk fclk}]
