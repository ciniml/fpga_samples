// USB_HOST variant additions (appended to timing_gen.sdc by project.tcl): clocks of the USB PHY,
// as eda/usb_device/src/tangprimer25k/timing.sdc (dd88bf7). clk_sys is the 60 MHz PLL output.
create_clock -name clk_sys -period 16.6667 -waveform {0 8.3333} [get_nets {clk_sys}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {clk_sys}]
create_clock -name os_f0   -period 2.0833 -waveform {0 1.0417} [get_nets {os_f0}]
create_clock -name os_f90  -period 2.0833 -waveform {0 1.0417} [get_nets {os_f90}]
create_clock -name os_f180 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f180}]
create_clock -name os_f270 -period 2.0833 -waveform {0 1.0417} [get_nets {os_f270}]
create_generated_clock -name os_pclk -source [get_ports {clk_in}] -master_clock clk_in -divide_by 5 -multiply_by 12 [get_nets {os_pclk}]
set_false_path -from [get_clocks {clk_in}] -to [get_clocks {os_f0 os_f90 os_f180 os_f270 os_pclk}]
// PCLK <-> 60 MHz: gray-pointer async FIFOs and 2FF synchronisers (usb_hs_os32)
set_false_path -from [get_clocks {os_pclk}] -to [get_clocks {clk_sys}]
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {os_pclk}]
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {os_f0 os_f90 os_f180 os_f270}]
// trace domains <-> clk_sys: the same 2FF / quasi-static crossings as with clk_in
set_false_path -from [get_clocks {clk_sys}] -to [get_clocks {rxclk_500m_0 rxclk_500m_90 rxclk_500m_180 rxclk_500m_270 pclk_rx}]
set_false_path -from [get_clocks {pclk_rx}] -to [get_clocks {clk_sys}]
