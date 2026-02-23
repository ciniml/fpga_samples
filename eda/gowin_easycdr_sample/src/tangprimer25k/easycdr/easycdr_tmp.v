//Copyright (C)2014-2023 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//GOWIN Version: V1.9.9 Beta-5
//Part Number: GW5A-LV25UG324ES
//Device: GW5A-25
//Device Version: A
//Created Time: Wed Sep 27 08:50:25 2023

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	EasyCDR_Top your_instance_name(
		.rxp_i(rxp_i_i), //input rxp_i
		.rxn_i(rxn_i_i), //input rxn_i
		.rstn_i(rstn_i_i), //input rstn_i
		.pll_clkin_i(pll_clkin_i_i), //input pll_clkin_i
		.pll_clkout0_i(pll_clkout0_i_i), //input pll_clkout0_i
		.pll_clkout1_i(pll_clkout1_i_i), //input pll_clkout1_i
		.pll_clkout2_i(pll_clkout2_i_i), //input pll_clkout2_i
		.pll_clkout3_i(pll_clkout3_i_i), //input pll_clkout3_i
		.pll_lock_i(pll_lock_i_i), //input pll_lock_i
		.share_clk0_o(share_clk0_o_o), //output share_clk0_o
		.share_clk1_o(share_clk1_o_o), //output share_clk1_o
		.share_clk2_o(share_clk2_o_o), //output share_clk2_o
		.share_clk3_o(share_clk3_o_o), //output share_clk3_o
		.share_clk4_o(share_clk4_o_o), //output share_clk4_o
		.share_reset_o(share_reset_o_o), //output share_reset_o
		.dout_o(dout_o_o), //output [15:0] dout_o
		.dout_en_o(dout_en_o_o), //output dout_en_o
		.error_o(error_o_o) //output error_o
	);

//--------Copy end-------------------
