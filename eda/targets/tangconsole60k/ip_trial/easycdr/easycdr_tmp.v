//Copyright (C)2014-2025 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12
//Part Number: GW5AT-LV60PG484AC1/I0
//Device: GW5AT-60
//Device Version: B
//Created Time: Fri Oct  9 18:53:11 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	EasyCDR_Top your_instance_name(
		.rxp_i(rxp_i), //input rxp_i
		.rxn_i(rxn_i), //input rxn_i
		.pll_clkin_i(pll_clkin_i), //input pll_clkin_i
		.pll_clkout0_i(pll_clkout0_i), //input pll_clkout0_i
		.pll_clkout1_i(pll_clkout1_i), //input pll_clkout1_i
		.pll_clkout2_i(pll_clkout2_i), //input pll_clkout2_i
		.pll_clkout3_i(pll_clkout3_i), //input pll_clkout3_i
		.pll_lock_i(pll_lock_i), //input pll_lock_i
		.share_clk0_o(share_clk0_o), //output share_clk0_o
		.share_clk1_o(share_clk1_o), //output share_clk1_o
		.share_clk2_o(share_clk2_o), //output share_clk2_o
		.share_clk3_o(share_clk3_o), //output share_clk3_o
		.share_clk4_o(share_clk4_o), //output share_clk4_o
		.share_reset_o(share_reset_o), //output share_reset_o
		.rstn_i(rstn_i), //input rstn_i
		.dout_en_o(dout_en_o), //output dout_en_o
		.align_flag_o(align_flag_o), //output align_flag_o
		.error_o(error_o), //output error_o
		.dout_o(dout_o) //output [9:0] dout_o
	);

//--------Copy end-------------------
