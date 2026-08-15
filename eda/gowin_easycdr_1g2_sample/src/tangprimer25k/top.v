// 1.2Gbps EasyCDR loopback sample (Tang Primer 25K / GW5A-25A)
//
// Line rate 1.2Gbps is above 1Gbps, so the EasyCDR IP is used in its
// BEYOND_1G / 32-bit configuration (see easycdr_1912/define.v):
//   - RX HCLK  = line rate / 4  = 300MHz, 4 phases (u_pll_rx, PLL_T,
//     serves the BANK6/BANK7 HCLK group -> rxp/rxn on G11/G10, BANK7)
//   - RX PCLK  = line rate / 16 = 75MHz (share_clk4_o from the IP)
//   - dout_o is 32 bits wide, dout_en_o asserts every 2nd PCLK cycle
// The TX test-pattern generator runs on its own PLL because its 600MHz
// serializer clock cannot share the RX HCLK group:
//   - TX FCLK = 600MHz (u_pll_tx), TX PCLK = 150MHz (CLKDIV /4)
//   - txp/txn moved to F5/G5 (BANK1, pmod0) so the TX FCLK uses the
//     BANK0/BANK1 HCLK group
//
// Note on data format: the IDE 1.9.12 EasyCDR core packs recovered bits
// into dout_o earliest-bit-first at bit[0], which is the reverse of the
// bit order prbs_top expects, so each 16-bit half-word is bit-reversed
// before being fed to the PRBS inspector.
module top(
    input            clk_in,          // 50MHz
    input            i_serial_p,
    input            i_serial_n,
    output           o_serial_p,
    output           o_serial_n,
    input            reset_in,        // push button, active high (pull-down)
    output           o_dat_err,
    output           o_dat_lock,
    output wire[7:0] o_dat_err_num,
    output           O_ERROR,
    output           dout_flag_xor    // EC92 marker detect toggle (debug)
    );

    wire resetn_in = ~reset_in;

    //------------------------------------------------------------------
    // RX clocking: 300MHz x 4 phases for the EasyCDR IP
    //------------------------------------------------------------------
    wire pll_rx_lock;
    wire rxclk_300m_0 /* synthesis syn_keep=1 */;
    wire rxclk_300m_90;
    wire rxclk_300m_180;
    wire rxclk_300m_270;

    pll_rx_300m_4ph u_pll_rx(
        .lock    (pll_rx_lock),
        .clkout0 (rxclk_300m_0),
        .clkout1 (rxclk_300m_90),
        .clkout2 (rxclk_300m_180),
        .clkout3 (rxclk_300m_270),
        .clkin   (clk_in)
    );

    //------------------------------------------------------------------
    // EasyCDR IP (BEYOND_1G, 32-bit output, shared logic inside)
    //------------------------------------------------------------------
    wire        pclk_rx;          // share_clk4_o = 75MHz
    wire        rxclk_300m_dhce;  // share_clk0_o (DHCE-gated 300MHz, 0 deg)
    wire        rxclk_150m;       // inspector clock, see below
    wire        rx_reset;         // share_reset_o, active high
    wire [31:0] rx_data;
    wire        rx_data_en;       // asserts every 2nd pclk_rx cycle

    EasyCDR_Top u_EasyCDR_Top(
        .rxp_i         (i_serial_p),
        .rxn_i         (i_serial_n),
        .rstn_i        (resetn_in),
        .pll_clkin_i   (clk_in),
        .pll_clkout0_i (rxclk_300m_0),
        .pll_clkout1_i (rxclk_300m_90),
        .pll_clkout2_i (rxclk_300m_180),
        .pll_clkout3_i (rxclk_300m_270),
        .pll_lock_i    (pll_rx_lock),
        .share_clk0_o  (rxclk_300m_dhce),
        .share_clk1_o  (),
        .share_clk2_o  (),
        .share_clk3_o  (),
        .share_clk4_o  (pclk_rx),
        .share_reset_o (rx_reset),
        .dout_o        (rx_data),
        .dout_en_o     (rx_data_en)
        // The BEYOND_1G configuration has no error_o port.
    );
    assign O_ERROR = 1'b0;

    //------------------------------------------------------------------
    // 32bit -> 16bit x2 gearbox towards the PRBS inspector.
    // rx_data_en asserts every 2nd cycle, so the gearbox output carries
    // a valid 16-bit word on every pclk_rx cycle (16 bit x 75MHz = 1.2G).
    // rx_data[15:0] holds the earlier bits on the wire; each half-word is
    // bit-reversed to match the prbs_top word format (earliest at [15]).
    //------------------------------------------------------------------
    wire [15:0] rx_half0, rx_half1;
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin : g_bitrev
            assign rx_half0[gi] = rx_data[15-gi];
            assign rx_half1[gi] = rx_data[31-gi];
        end
    endgenerate

    // The BEYOND_1G core delivers dout_en in a bursty cadence - including on
    // back-to-back cycles - even though the long-term average is one 32-bit
    // word per two cycles, so half-words are buffered in a small FIFO.
    //
    // The FIFO is drained and the PRBS inspector is clocked at 150MHz (2x the
    // parallel clock, from the same DHCE-gated 300MHz HCLK, so the domains
    // are edge-related). This gives the 16-bit inspector path 2.4Gbps of
    // capacity against the 1.2Gbps line rate: in a two-board setup the
    // crystal frequency offset then merely modulates the valid duty cycle
    // (~50%) instead of slowly overflowing a rate-matched FIFO.
    CLKDIV u_clkdiv_insp(
        .HCLKIN (rxclk_300m_dhce),
        .RESETN (resetn_in),
        .CALIB  (1'b0),
        .CLKOUT (rxclk_150m)
    );
    defparam u_clkdiv_insp.DIV_MODE = "2";

    reg [15:0] gb_q [0:15];
    reg [3:0]  gb_wp, gb_rp;
    reg [15:0] gb_data;
    reg        gb_vld;
    // write side: 75MHz parallel-clock domain
    always @(posedge pclk_rx or posedge rx_reset) begin
        if (rx_reset) begin
            gb_wp <= 4'd0;
        end else if (rx_data_en) begin
            gb_q[gb_wp]      <= rx_half0;
            gb_q[gb_wp+4'd1] <= rx_half1;
            gb_wp <= gb_wp + 4'd2;
        end
    end
    // read side: 150MHz inspector domain (edge-related to the write clock)
    always @(posedge rxclk_150m or posedge rx_reset) begin
        if (rx_reset) begin
            gb_rp   <= 4'd0;
            gb_data <= 16'h0000;
            gb_vld  <= 1'b0;
        end else if (gb_rp != gb_wp) begin
            gb_data <= gb_q[gb_rp];
            gb_rp   <= gb_rp + 4'd1;
            gb_vld  <= 1'b1;
        end else begin
            gb_vld <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // TX clocking: 600MHz serializer clock + 150MHz parallel clock
    //------------------------------------------------------------------
    wire pll_tx_lock;
    wire txclk_600m /* synthesis syn_keep=1 */;
    wire txclk_150m;

    pll_tx_600m u_pll_tx(
        .lock    (pll_tx_lock),
        .clkout0 (txclk_600m),
        .clkout1 (),
        .clkout2 (),
        .clkout3 (),
        .clkin   (clk_in)
    );

    CLKDIV u_clkdiv_tx(
        .HCLKIN (txclk_600m),
        .RESETN (resetn_in),
        .CALIB  (1'b0),
        .CLKOUT (txclk_150m)
    );
    defparam u_clkdiv_tx.DIV_MODE = "4";

    //------------------------------------------------------------------
    // PRBS generator / inspector.
    // Generator runs in the TX domain (150MHz), inspector in the RX
    // parallel domain (75MHz). Resets release only after both PLLs are
    // locked and the EasyCDR share-reset has deasserted.
    //------------------------------------------------------------------
    wire prbs_rstn = resetn_in & ~rx_reset & pll_tx_lock & pll_rx_lock;
    wire [7:0] oser8_pdata;
    wire o_serial_data;

    prbs_top u_prbs_top(
        .i_clk1        (txclk_150m),
        .i_clk2        (rxclk_150m),
        .i_rst_n1      (prbs_rstn),
        .i_rst_n2      (prbs_rstn),
        .o_dout        (oser8_pdata),
        .i_prbs_enable (1'b1),
        .i_dat_vld_10b (1'b0),
        .i_dat_10b     (10'b0000000000),
        .i_dat_vld_16b (gb_vld),
        .i_dat_16b     (gb_data),
        .o_dat_err     (o_dat_err),
        .o_dat_lock    (prbs_lock),
        .o_dat_err_num (o_dat_err_num)
    );

    OSER8 u_OSER8(
        .Q0    (o_serial_data),
        .Q1    (),
        .D0    (oser8_pdata[0]),
        .D1    (oser8_pdata[1]),
        .D2    (oser8_pdata[2]),
        .D3    (oser8_pdata[3]),
        .D4    (oser8_pdata[4]),
        .D5    (oser8_pdata[5]),
        .D6    (oser8_pdata[6]),
        .D7    (oser8_pdata[7]),
        .TX0   (1'b0),
        .TX1   (1'b0),
        .TX2   (1'b0),
        .TX3   (1'b0),
        .PCLK  (txclk_150m),
        .FCLK  (txclk_600m),
        .RESET (~prbs_rstn)
    );

    ELVDS_OBUF u_tx(
        .I  (o_serial_data),
        .O  (o_serial_p),
        .OB (o_serial_n)
    );

    //------------------------------------------------------------------
    // Debug: toggle a flag whenever the 0xEC92 marker word appears in the
    // received stream. With the PRBS9 pattern this yields a square wave
    // with a 13.6us period (marker once per 511-word cycle at 75M word/s)
    // when the link is receiving correctly.
    //------------------------------------------------------------------
    reg dout_flag;
    always @(posedge rxclk_150m or posedge rx_reset)
        if (rx_reset) dout_flag <= 1'b0;
        else if (gb_vld && gb_data == 16'hec92) dout_flag <= ~dout_flag;

    assign dout_flag_xor = dout_flag;

    // Marker watchdog: the PRBS inspector locks onto the degenerate all-zero
    // sequence when the cable is unplugged (an LFSR fixed point), so qualify
    // the lock output with "the EC92 marker has been seen recently". The
    // marker arrives every 6.8us on a healthy link; time out after ~109us.
    wire prbs_lock;
    reg [12:0] act_cnt;
    reg        act_ok;
    always @(posedge rxclk_150m or posedge rx_reset) begin
        if (rx_reset) begin
            act_cnt <= 13'd0;
            act_ok  <= 1'b0;
        end else if (gb_vld && gb_data == 16'hec92) begin
            act_cnt <= 13'd0;
            act_ok  <= 1'b1;
        end else if (&act_cnt) begin
            act_ok <= 1'b0;
        end else begin
            act_cnt <= act_cnt + 1'b1;
        end
    end
    assign o_dat_lock = prbs_lock & act_ok;

endmodule
