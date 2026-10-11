//Copyright (C)2014-2026 Gowin Semiconductor Corporation.
//All rights reserved.
//File Title: Template file for instantiation
//Tool Version: V1.9.12.03
//Part Number: GW5AT-LV15MG132C1/I0
//Device: GW5AT-15
//Device Version: A
//Created Time: Sun Oct 11 13:39:41 2026

//Change the instance name and port connections to the signal names
//--------Copy here to design--------

	\~upar_arbiter_wrap.SerDes_Top your_instance_name(
		.drp_clk_o(drp_clk_o), //output [3:0] drp_clk_o
		.drp_addr_i(drp_addr_i), //input [95:0] drp_addr_i
		.drp_wren_i(drp_wren_i), //input [3:0] drp_wren_i
		.drp_wrdata_i(drp_wrdata_i), //input [127:0] drp_wrdata_i
		.drp_strb_i(drp_strb_i), //input [31:0] drp_strb_i
		.drp_ready_o(drp_ready_o), //output [3:0] drp_ready_o
		.drp_rden_i(drp_rden_i), //input [3:0] drp_rden_i
		.drp_rdvld_o(drp_rdvld_o), //output [3:0] drp_rdvld_o
		.drp_rddata_o(drp_rddata_o), //output [127:0] drp_rddata_o
		.drp_resp_o(drp_resp_o), //output [3:0] drp_resp_o
		.upar_clk_i(upar_clk_i), //input upar_clk_i
		.upar_rst_o(upar_rst_o), //output upar_rst_o
		.upar_addr_o(upar_addr_o), //output [23:0] upar_addr_o
		.upar_wren_o(upar_wren_o), //output upar_wren_o
		.upar_wrdata_o(upar_wrdata_o), //output [31:0] upar_wrdata_o
		.upar_strb_o(upar_strb_o), //output [7:0] upar_strb_o
		.upar_ready_i(upar_ready_i), //input upar_ready_i
		.upar_rden_o(upar_rden_o), //output upar_rden_o
		.upar_bus_width_o(upar_bus_width_o), //output upar_bus_width_o
		.upar_rdvld_i(upar_rdvld_i), //input upar_rdvld_i
		.upar_rddata_i(upar_rddata_i) //input [31:0] upar_rddata_i
	);

//--------Copy end-------------------
