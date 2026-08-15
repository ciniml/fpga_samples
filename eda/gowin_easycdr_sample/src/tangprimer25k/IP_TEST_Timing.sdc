//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: V1.9.9 Beta-5
//Created Time: 2023-10-09 10:58:08
create_clock -name Clk_in -period 20 -waveform {0 10} [get_ports {clk_in}]
create_clock -name CLK_500_0 -period 2 -waveform {0 1} [get_nets {pllclk_625m_0}]
#create_clock -name tck_pad_i -period 50 -waveform {0 25} [get_ports {tck_pad_i}]
create_clock -name CLK_500_270 -period 2 -waveform {0 1} [get_nets {pllclk_625m_270}]
create_clock -name CLK_500_180 -period 2 -waveform {0 1} [get_nets {pllclk_625m_180}]
create_clock -name CLK_500_90 -period 2 -waveform {0 1} [get_nets {pllclk_625m_90}]
create_generated_clock -name sample_clk -source [get_ports {clk_in}] -master_clock Clk_in -divide_by 8 -multiply_by 25 [get_pins {clkdiv_sample_clk/CLKOUT}]
# The original constraint targeted the CLKDIV pin inside the encrypted EasyCDR IP
# (u_EasyCDR_Top/u_EasyCDR/u_share_logic_mod/clkdiv_inst/CLKOUT). The IP is now built
# from its post-PnR netlist (easycdr.vo) whose escaped hierarchy names are not
# addressable from SDC, so constrain the same 156.25MHz clock on the top-level net.
create_generated_clock -name clk1_156M -source [get_ports {clk_in}] -master_clock Clk_in -divide_by 8 -multiply_by 25 [get_nets {pllclk_156_25m}]
#set_false_path -from [get_clocks {tck_pad_i}] -to [get_clocks {sample_clk}] 
set_false_path -from [get_clocks {Clk_in}] -to [get_clocks {CLK_500_180 CLK_500_90 CLK_500_270 CLK_500_0}] 
#set_false_path -from [get_clocks {sample_clk}] -to [get_clocks {tck_pad_i}] 
set_false_path -from [get_clocks {Clk_in}] -to [get_clocks {clk1_156M}] 
