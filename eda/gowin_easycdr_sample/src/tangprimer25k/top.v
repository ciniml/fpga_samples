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
    `elsif OUTPUT32BIT
        wire[31:0]      parrallel_data  ;
    `endif
    `ifdef OUTPUT16BIT
        wire[15:0]      parrallel_data_bitrev;
        genvar gbr;
        generate
            for (gbr = 0; gbr < 16; gbr = gbr + 1) begin : g_bitrev
                assign parrallel_data_bitrev[gbr] = parrallel_data[15-gbr];
            end
        endgenerate
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
            // The IDE 1.9.12 EasyCDR core packs recovered bits into dout_o in
            // the opposite bit order from the V1.9.9 core that prbs_top was
            // written against, so reverse the word here.
            .i_dat_16b     (parrallel_data_bitrev),
        `elsif OUTPUT32BIT
            // BEYOND_1G mode: 32-bit words are split into two 16-bit words by
            // the gearbox below, since prbs_top only has a 16-bit input.
            .i_dat_vld_10b ('b0),
            .i_dat_10b     (10'b0000000000),
            .i_dat_vld_16b (gb_vld),
            .i_dat_16b     (gb_data),
        `endif
`ifdef DIAG_LIVENESS
        .o_dat_err     (),
        .o_dat_lock    (),
`else
        .o_dat_err     (o_dat_err),
        .o_dat_lock    (prbs_lock),
`endif
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
		.dout_o(parrallel_data), //output [31:0] dout_o
		.dout_en_o(parrallel_div) //output dout_en_o
		// The BEYOND_1G configuration of the 1.9.12 EasyCDR IP has no error_o
		// port (it exists only in the 10-bit + 8b10B-decode configuration).
	);
	assign O_ERROR = 1'b0;

`ifdef OUTPUT32BIT
    // Gearbox: split each 32-bit CDR output word into two 16-bit words for
    // prbs_top. dout_en_o asserts once every 4 cycles of the 156.25MHz
    // parallel clock, so the two 16-bit words fit in consecutive cycles.
    // parrallel_data[15:0] holds the earlier bits on the wire.
    reg [15:0] gb_data;
    reg        gb_vld;
    reg [15:0] gb_hi;
    reg        gb_pending;
    always @(posedge pllclk_156_25m or posedge reset1) begin
        if (reset1) begin
            gb_data    <= 16'h0000;
            gb_hi      <= 16'h0000;
            gb_vld     <= 1'b0;
            gb_pending <= 1'b0;
        end else if (parrallel_div) begin
            gb_data    <= parrallel_data[15:0];
            gb_hi      <= parrallel_data[31:16];
            gb_vld     <= 1'b1;
            gb_pending <= 1'b1;
        end else if (gb_pending) begin
            gb_data    <= gb_hi;
            gb_vld     <= 1'b1;
            gb_pending <= 1'b0;
        end else begin
            gb_vld <= 1'b0;
        end
    end
    wire [15:0] dbg_word = gb_data;
    wire        dbg_vld  = gb_vld;
`else
    wire [15:0] dbg_word = parrallel_data_bitrev;
    wire        dbg_vld  = parrallel_div;
`endif

    // Marker watchdog: the PRBS inspector locks onto the degenerate all-zero
    // sequence when no signal is present (an LFSR fixed point), so qualify
    // the lock output with "the EC92 marker has been seen recently". On a
    // healthy 1Gbps link the marker arrives every 8.18us; time out after
    // ~65us (2^13 cycles of the 125MHz parallel clock).
    wire prbs_lock;
    reg [12:0] act_cnt;
    reg        act_ok;
    always @(posedge pllclk_156_25m or posedge reset1) begin
        if (reset1) begin
            act_cnt <= 13'd0;
            act_ok  <= 1'b0;
        end else if (dbg_vld && dbg_word == 16'hec92) begin
            act_cnt <= 13'd0;
            act_ok  <= 1'b1;
        end else if (&act_cnt) begin
            act_ok <= 1'b0;
        end else begin
            act_cnt <= act_cnt + 1'b1;
        end
    end
`ifndef DIAG_LIVENESS
    assign o_dat_lock = prbs_lock & act_ok;
`endif

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
        else if (dbg_word==16'hec92 && dbg_vld=='b1) dout_flag <= ~dout_flag;

    always @ (negedge resetn_in or posedge sample_156_25m)
        if (!resetn_in) dout_flag_dly <= 'b0;
        else dout_flag_dly <= dout_flag;

`ifdef DIAG_LIVENESS
    // Liveness diagnostic build: repurpose the three observable pins as
    // stage-by-stage heartbeat indicators (visible LED-rate blinking).
    //   o_dat_lock (B2): independent-PLL domain alive (sample_156_25m)
    //   o_dat_err  (C2): EasyCDR share-clock domain alive (share_clk4)
    //   dout_flag_xor (E1): dout_en pulsing AND parallel data changing
    reg [23:0] diag_cnt_sample;
    always @(posedge sample_156_25m) diag_cnt_sample <= diag_cnt_sample + 1'b1;

    reg [23:0] diag_cnt_share;
    always @(posedge pllclk_156_25m) diag_cnt_share <= diag_cnt_share + 1'b1;

    reg [15:0] diag_last_word;
    reg [20:0] diag_cnt_chg;
    always @(posedge pllclk_156_25m) begin
        if (parrallel_div) begin
            diag_last_word <= parrallel_data[15:0];
            if (parrallel_data[15:0] != diag_last_word)
                diag_cnt_chg <= diag_cnt_chg + 1'b1;
        end
    end

  `ifdef DIAG_LIVENESS4
    // Fourth-stage diagnostics: search the RX stream for the EC92 marker at
    // every bit shift, in both bit orders.
    //   o_dat_lock (B2): stretched hit, forward bit order, any of 17 shifts
    //   o_dat_err  (C2): stretched hit, reversed bit order, any of 17 shifts
    //   dout_flag_xor (E1): dout_en_o raw (known-good reference)
    wire [15:0] rx_word = parrallel_data[15:0];
    wire [15:0] rx_word_rev;
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_rev
            assign rx_word_rev[gi] = rx_word[15-gi];
        end
    endgenerate

    reg [31:0] fwd_win, rev_win;
    always @(posedge pllclk_156_25m) begin
        if (parrallel_div) begin
            fwd_win <= {fwd_win[15:0], rx_word};
            rev_win <= {rx_word_rev, rev_win[31:16]};
        end
    end

    reg fwd_hit, rev_hit;
    integer si;
    always @(*) begin
        fwd_hit = 1'b0;
        rev_hit = 1'b0;
        for (si = 0; si <= 16; si = si + 1) begin
            if (fwd_win[si +: 16] == 16'hec92) fwd_hit = 1'b1;
            if (rev_win[si +: 16] == 16'hec92) rev_hit = 1'b1;
        end
    end

    // Toggle-per-hit flags: scope-measured toggle period discriminates a real
    // PRBS stream (hits every few us) from uniformly random data (hits every
    // ~100us) and from repetitive garbage (no hits or an odd fixed rate).
    reg fwd_tgl, rev_tgl;
    always @(posedge pllclk_156_25m) begin
        if (parrallel_div && fwd_hit) fwd_tgl <= ~fwd_tgl;
        if (parrallel_div && rev_hit) rev_tgl <= ~rev_tgl;
    end

    assign o_dat_lock    = fwd_tgl;
    assign o_dat_err     = rev_tgl;
    assign dout_flag_xor = parrallel_div;
  `elsif DIAG_LIVENESS3
    // Third-stage diagnostics: raw signals, no dividers, for scope observation.
    //   o_dat_lock (B2): replica of the IP-internal PCLK-domain reset release
    //                    (resetn_in & ~reset1) — expected steady High
    //   o_dat_err  (C2): XOR-reduce of dout_o — toggles iff parallel data changes
    //   dout_flag_xor (E1): dout_en_o raw — expect ~8ns pulses every ~40ns
    assign o_dat_lock    = resetn_in & ~reset1;
    assign o_dat_err     = ^parrallel_data;
    assign dout_flag_xor = parrallel_div;
  `elsif DIAG_LIVENESS2
    // Second-stage diagnostics: raw reset/lock levels plus dout_en activity.
    //   o_dat_lock (B2): pll_locked1 — expected steady High
    //   o_dat_err  (C2): reset1 (EasyCDR share_reset_o) — expected steady Low;
    //                    steady High means the IP reset sequencer never releases
    //   dout_flag_xor (E1): blink if dout_en pulses at all (data content ignored)
    reg [20:0] diag_cnt_den;
    always @(posedge pllclk_156_25m) if (parrallel_div) diag_cnt_den <= diag_cnt_den + 1'b1;
    assign o_dat_lock    = pll_locked1;
    assign o_dat_err     = reset1;
    assign dout_flag_xor = diag_cnt_den[20];
  `else
    assign o_dat_lock    = diag_cnt_sample[23];
    assign o_dat_err     = diag_cnt_share[23];
    assign dout_flag_xor = diag_cnt_chg[20];
  `endif
`else
    // Debug aid: output the EC92-detect toggle flag directly instead of the
    // single-cycle pulse. If the RX parallel datapath is alive and carrying
    // (even misaligned) data, this pin shows a few-hundred-Hz square wave;
    // a dead datapath shows a static level.
    assign dout_flag_xor = dout_flag;
`endif

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