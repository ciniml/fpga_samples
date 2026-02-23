`include"define.v"

module top(
    input            clk_in,
    input            i_serial_p,
    input            i_serial_n,
    output           o_serial_p,
    output           o_serial_n,
    input            reset_in,
    output           o_dat_err       ,
    output           o_dat_lock      ,
    output wire[7:0] o_dat_err_num   ,
    output           O_ERROR         ,
    output           dout_flag_xor
    );
    wire            pllclk_625m_0/* synthesis syn_keep=1 */;
    wire            pllclk_625m_90;
    wire            pllclk_625m_180;
    wire            pllclk_625m_270;
    wire            pllclk_156_25m;
    wire            txclk_625m_0/* synthesis syn_keep=1 */;
    wire            txclk_625m_90;
    wire            txclk_625m_180;
    wire            txclk_625m_270;
    wire            txclk_156_25m;
    wire            reset1/* synthesis syn_keep=1 */;
    wire            resetn2/* synthesis syn_keep=1 */;
    wire            clk_uart;
    wire            o_pllclk_625m_0;
    wire            o_pllclk_625m_90;
    wire            o_pllclk_625m_180;
    wire            o_pllclk_625m_270;
    wire            o_txclk_625m_0;
    wire            o_txclk_625m_90;
    wire            o_txclk_625m_180;
    wire            o_txclk_625m_270;
    wire            pll_locked1/* synthesis syn_keep=1 */;
    wire            pll_locked2/* synthesis syn_keep=1 */;
    wire            cen1/* synthesis syn_keep=1 */;
    wire            cen2/* synthesis syn_keep=1 */;
    wire            o_serial_data;
    wire            i_serial_data;
//    wire            reset1/* synthesis syn_keep=1 */;
    wire            reset2 /* synthesis syn_keep=1 */;
    wire[7:0]       oser8_pdata;
    wire            parrallel_div;
    `ifdef OUTPUT10BIT
        wire[9:0]       parrallel_data  ;
    `elsif OUTPUT16BIT
        wire[15:0]      parrallel_data  ;
    `endif
    wire share_clk0_i;
    wire share_clk1_i;
    wire share_clk2_i;
    wire share_clk3_i;
    wire share_clk4_i;
    wire share_reset_i;
`ifdef SHARED_LOGIC
    assign share_clk1_i = 'b0;
    assign share_clk1_i = 'b0;
    assign share_clk2_i = 'b0;
    assign share_clk3_i = 'b0;
    assign share_clk4_i = 'b0;
    assign share_reset_i = 'b0;
`else
    
    CLKDIV clkdiv_inst1(
        .HCLKIN         (pllclk_625m_0   ),
        .RESETN         ('b1             ),
        .CALIB          (1'b0            ),
        .CLKOUT         (share_clk4_i    )
    );
    defparam clkdiv_inst1.DIV_MODE="4";

    assign share_clk1_i = pllclk_625m_0;
    assign share_clk1_i = pllclk_625m_90;
    assign share_clk2_i = pllclk_625m_180;
    assign share_clk3_i = pllclk_625m_270;
    assign share_reset_i = 'b0;
`endif

    wire resetn_in;
    assign resetn_in = ~reset_in;
    
    pll_clk50_class625 u_pll_clk(
        .lock(pll_locked1), //output lock
        .clkout0(pllclk_625m_0), //output clkout0
        .clkout1(pllclk_625m_90), //output clkout1
        .clkout2(pllclk_625m_180), //output clkout2
        .clkout3(pllclk_625m_270), //output clkout3
        .clkin(clk_in) //input clkin
    );

    prbs_top u_prbs_top(
        .i_clk1         (pllclk_156_25m),
        .i_clk2         (pllclk_156_25m),        
        .i_rst_n1       (reset1 | resetn_in),
        .i_rst_n2       (reset1 | resetn_in),
        .o_dout        (oser8_pdata),
        .i_prbs_enable ('b1),
        `ifdef OUTPUT10BIT
            .i_dat_vld_10b (parrallel_div),
            .i_dat_10b     (parrallel_data),
            .i_dat_vld_16b ('b0),
            .i_dat_16b     (16'h0000),
        `elsif OUTPUT16BIT
            .i_dat_vld_10b ('b0),
            .i_dat_10b     (10'b0000000000),
            .i_dat_vld_16b (parrallel_div),
            .i_dat_16b     (parrallel_data),
        `endif
        .o_dat_err     (o_dat_err),
        .o_dat_lock    (o_dat_lock),
        .o_dat_err_num (o_dat_err_num)
    );

    OSER8 u_OSER8(
        .Q0       (o_serial_data      ),
        .Q1       (                   ),
        .D0       (oser8_pdata[0]     ),
        .D1       (oser8_pdata[1]     ),
        .D2       (oser8_pdata[2]     ),
        .D3       (oser8_pdata[3]     ),
        .D4       (oser8_pdata[4]     ),
        .D5       (oser8_pdata[5]     ),
        .D6       (oser8_pdata[6]     ), 
        .D7       (oser8_pdata[7]     ), 
        .TX0      (1'b0               ),
        .TX1      (1'b0               ),
        .TX2      (1'b0               ),
        .TX3      (1'b0               ),
        .PCLK     (pllclk_156_25m      ),
        .FCLK     (o_pllclk_625m_0     ),
        .RESET    (reset1 | !resetn_in)
    );

    ELVDS_OBUF u_tx(
        .I     (o_serial_data ),
        .O     (o_serial_p    ),
        .OB    (o_serial_n    )
        );

	EasyCDR_Top u_EasyCDR_Top(
		.rxp_i(i_serial_p), //input rxp_i
		.rxn_i(i_serial_n), //input rxn_i
		.rstn_i(resetn_in), //input rstn_i
		.pll_clkin_i(clk_in), //input pll_clkin_i
		.pll_clkout0_i(pllclk_625m_0), //input pll_clkout0_i
		.pll_clkout1_i(pllclk_625m_90), //input pll_clkout1_i
		.pll_clkout2_i(pllclk_625m_180), //input pll_clkout2_i
		.pll_clkout3_i(pllclk_625m_270), //input pll_clkout3_i
		.pll_lock_i(pll_locked1), //input pll_lock_i
		.share_clk0_o(o_pllclk_625m_0), //output share_clk0_o
		.share_clk1_o(o_pllclk_625m_90), //output share_clk1_o
		.share_clk2_o(o_pllclk_625m_180), //output share_clk2_o
		.share_clk3_o(o_pllclk_625m_270), //output share_clk3_o
		.share_clk4_o(pllclk_156_25m), //output share_clk4_o
		.share_reset_o(reset1), //output share_reset_o
		.dout_o(parrallel_data), //output [15:0] dout_o
		.dout_en_o(parrallel_div), //output dout_en_o
		.error_o(O_ERROR) //output error_o
	);

    reg[7:0]    oser8_pdata_dly0 /* synthesis syn_keep=1 */;
    reg[7:0]    oser8_pdata_dly1 /* synthesis syn_keep=1 */;
    reg[7:0]    oser8_pdata_dly2 /* synthesis syn_keep=1 */;
    wire[23:0]  oser8_pdata_dly3 /* synthesis syn_keep=1 */;
    reg         flag_oser8_align /* synthesis syn_keep=1 */;
    reg 	    dout_flag /* synthesis syn_keep=1 */;
    reg 	    dout_flag_dly /* synthesis syn_keep=1 */;
    //wire 	    dout_flag_xor /* synthesis syn_keep=1 */;
    always @ (negedge resetn_in or posedge sample_156_25m) begin
        if (!resetn_in) begin
            oser8_pdata_dly0 <= 8'h00;
            oser8_pdata_dly1 <= 8'h00;
            oser8_pdata_dly2 <= 8'h00;
        end else begin
            oser8_pdata_dly0 <= {oser8_pdata[0],oser8_pdata[1],oser8_pdata[2],oser8_pdata[3],oser8_pdata[4],oser8_pdata[5],oser8_pdata[6],oser8_pdata[7]};
            oser8_pdata_dly1 <= oser8_pdata_dly0;
            oser8_pdata_dly2 <= oser8_pdata_dly1;
        end
    end

    assign oser8_pdata_dly3 = {oser8_pdata_dly2,oser8_pdata_dly1,oser8_pdata_dly0};
	
    always @ (negedge resetn_in or posedge sample_156_25m)
        if (!resetn_in) 
            flag_oser8_align <= 'b0;
        else if (oser8_pdata_dly3[15:0]==16'hec92 || oser8_pdata_dly3[16:1]==16'hec92 || oser8_pdata_dly3[17:2]==16'hec92 ||
                 oser8_pdata_dly3[18:3]==16'hec92 || oser8_pdata_dly3[19:4]==16'hec92 || oser8_pdata_dly3[20:5]==16'hec92 ||
                 oser8_pdata_dly3[21:6]==16'hec92 || oser8_pdata_dly3[22:7]==16'hec92 || oser8_pdata_dly3[23:8]==16'hec92)
            flag_oser8_align <= 'b1;
        else
            flag_oser8_align <= 'b0;

    always @ (negedge resetn_in or posedge sample_156_25m)
        if (!resetn_in) dout_flag <= 'b0;
        else if (parrallel_data==16'hec92 && parrallel_div=='b1) dout_flag <= ~dout_flag;

    always @ (negedge resetn_in or posedge sample_156_25m)
        if (!resetn_in) dout_flag_dly <= 'b0;
        else dout_flag_dly <= dout_flag;

    assign dout_flag_xor = dout_flag_dly ^ dout_flag;

    wire sample_625m/* synthesis syn_keep=1 */;
    wire sample_156_25m/* synthesis syn_keep=1 */;

    pll_clk50_class625 u_sample_clk(
        .lock(), //output lock
        .clkout0(sample_625m), //output clkout0
        .clkout1(), //output clkout1
        .clkout2(), //output clkout2
        .clkout3(), //output clkout3
        .clkin(clk_in) //input clkin
    );
    CLKDIV clkdiv_sample_clk(
        .HCLKIN         (sample_625m     ),
        .RESETN         (resetn_in),
        .CALIB          (1'b0             ),
        .CLKOUT         (sample_156_25m   )
    );
    defparam clkdiv_sample_clk.DIV_MODE="4";

//--------------------------------------------------------------------------------------------------------------------------------------------
endmodule