// gb_camera: eda/cart_game's clocks + eda/csi_capture's camera clocks
//   50 MHz -> PLLA 100 / 200 MHz (GameCart + GbCamera / QspiRom)
//   50 MHz -> pll_usb 60 MHz -> pll_hs960 960 / 480 MHz -> CLKDIV /8: os_pclk 120 MHz, clk60 60 MHz (USB)
//   50 MHz -> PLLA (PLL_T) 500 MHz x 4 phases -> CLKDIV /4: pclk 125 MHz (camera)
//   50 MHz: csi_ctrl (camera I2C, its UART)
create_clock -name clk_in  -period 20 -waveform {0 10} [get_ports {clk_in}]
create_generated_clock -name clk  -source [get_ports {clk_in}] -master_clock clk_in -multiply_by 2 [get_pins {u_pll/PLLA_inst/CLKOUT0}]
create_generated_clock -name clk2 -source [get_ports {clk_in}] -master_clock clk_in -multiply_by 4 [get_pins {u_pll/PLLA_inst/CLKOUT1}]
create_clock -name pll_60m -period 16.6667 -waveform {0 8.3333} [get_nets {pll_60m}]
create_clock -name os_f960 -period 1.0417 -waveform {0 0.5208} [get_nets {os_f960}]
create_clock -name os_f480 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f480}]
create_clock -name os_pclk -period 8.3333 -waveform {0 4.1667} [get_pins {u_usbphy/u_clkdiv_p/CLKOUT}]
create_clock -name clk60   -period 16.6667 -waveform {0 8.3333} [get_nets {clk60}]
create_clock -name rxclk_500m_0   -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_0}]
create_clock -name rxclk_500m_90  -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_90}]
create_clock -name rxclk_500m_180 -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_180}]
create_clock -name rxclk_500m_270 -period 2 -waveform {0 1} [get_nets {u_phy/rxclk_500m_270}]
create_generated_clock -name pclk -source [get_ports {clk_in}] -master_clock clk_in -divide_by 2 -multiply_by 5 [get_pins {u_phy/u_clkdiv/CLKOUT}]

// USB: meets the cartridge clocks only in the two ByteAfifos (as eda/cart_game, eda/usb_device timing_sl.sdc)
set_clock_groups -asynchronous -group [get_clocks {os_f960 os_f480 os_pclk clk60}]
set_false_path -from [get_clocks {os_pclk}] -to [get_clocks {os_f960 os_f480}]
set_clock_uncertainty -setup -from [get_clocks {clk60}] -to [get_clocks {os_pclk}] 2.1
set_clock_uncertainty -setup -from [get_clocks {os_pclk}] -to [get_clocks {clk60}] 2.1

// camera lanes: sampled asynchronously (oversampling)
set_false_path -from [get_ports {csi_clk_p csi_d0_p csi_d1_p}]
// csi_ctrl (50 MHz) <-> camera word clock: toggles, quasi-static settings (as eda/csi_capture)
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {pclk rxclk_500m_0 rxclk_500m_90 rxclk_500m_180 rxclk_500m_270}]
set_false_path -from [get_clocks {pclk}] -to [get_clocks {clk_in}]
// camera word clock <-> GameCart / GbCamera: the frame buffer (read after the frame-complete
// toggle, written again a frame later) and that toggle (3 flip-flops)
set_clock_groups -asynchronous -group [get_clocks {pclk rxclk_500m_0 rxclk_500m_90 rxclk_500m_180 rxclk_500m_270}] -group [get_clocks {clk clk2}]

// GbColorQuant moves only every other clock (GbCamera's q_ce): 2 clocks between its registers
set_multicycle_path -from [get_regs {u_cam/u_quant/*}] -to [get_regs {u_cam/u_quant/*}] -setup -end 2
set_multicycle_path -from [get_regs {u_cam/u_quant/*}] -to [get_regs {u_cam/u_quant/*}] -hold -end 1
