// EasyCDR trace-link Phase 1: 8b10b link-layer loopback test (1Gbps).
//
// TX: easycdr_trace_tx_core (K28.5 comma every 16 words + incrementing
//     counter payload, 8b10b encoded) -> OSER10 (FCLK 500MHz, PCLK 100MHz)
// RX: EasyCDR in the 10-bit + Word Alignment + 8B/10B Decoding
//     configuration (line rate 1Gbps, HCLK 500MHz x4 phases, PCLK 125MHz):
//       dout_o[8]   = K-character flag
//       dout_o[7:0] = decoded byte
//       align_flag_o / error_o come from the IP itself.
// The RX checker verifies the counter sequence and drives the same
// observation pins as the PRBS samples (lock/err/marker).
//
// Physical link: ExtEasyCDR modules + passive USB-C cable (see the
// gowin_easycdr_1g2_sample README); TX on pmod0 lane L1 (G7/G8), RX on
// pmod2 lane L0 (G11/G10).
module top(
    input            clk_in,          // 50MHz
    input            i_serial_p,
    input            i_serial_n,
    output           o_serial_p,
    output           o_serial_n,
    input            reset_in,        // push button, active high (pull-down)
    output           o_dat_err,      // counter mismatch or 8b10b decode error
    output           o_dat_lock,     // aligned + comma watchdog
    output wire[7:0] o_dat_err_num,  // error count
    output           O_ERROR,        // sticky 8b10b decode error
    output           dout_flag_xor   // toggles every 256 commas (~82us square)
    );

    wire resetn_in = ~reset_in;

    //------------------------------------------------------------------
    // RX clocking: 500MHz x 4 phases for the EasyCDR IP (PLL_T)
    //------------------------------------------------------------------
    wire pll_rx_lock;
    wire rxclk_500m_0 /* synthesis syn_keep=1 */;
    wire rxclk_500m_90;
    wire rxclk_500m_180;
    wire rxclk_500m_270;

    pll_rx_500m_4ph u_pll_rx(
        .lock    (pll_rx_lock),
        .clkout0 (rxclk_500m_0),
        .clkout1 (rxclk_500m_90),
        .clkout2 (rxclk_500m_180),
        .clkout3 (rxclk_500m_270),
        .clkin   (clk_in)
    );

    //------------------------------------------------------------------
    // EasyCDR IP: 10bit + WORD_ALI + DECODE_8B10B (see easycdr_1912/define.v)
    //------------------------------------------------------------------
    wire       pclk_rx;        // share_clk4_o = 125MHz
    wire       rx_reset;       // share_reset_o, active high
    wire [9:0] rx_data;        // [8]=K flag, [7:0]=decoded byte
    wire       rx_data_en;     // ~80% duty (10-bit words at 100M word/s)
    wire       rx_align;       // align_flag_o
    wire       rx_decerr;      // error_o (disparity / code violation)

    EasyCDR_Top u_EasyCDR_Top(
        .rxp_i         (i_serial_p),
        .rxn_i         (i_serial_n),
        .rstn_i        (resetn_in),
        .pll_clkin_i   (clk_in),
        .pll_clkout0_i (rxclk_500m_0),
        .pll_clkout1_i (rxclk_500m_90),
        .pll_clkout2_i (rxclk_500m_180),
        .pll_clkout3_i (rxclk_500m_270),
        .pll_lock_i    (pll_rx_lock),
        .share_clk0_o  (),
        .share_clk1_o  (),
        .share_clk2_o  (),
        .share_clk3_o  (),
        .share_clk4_o  (pclk_rx),
        .share_reset_o (rx_reset),
        .align_flag_o  (rx_align),
        .error_o       (rx_decerr),
        .dout_o        (rx_data),
        .dout_en_o     (rx_data_en)
    );

    //------------------------------------------------------------------
    // TX clocking: 500MHz serializer clock + 100MHz (/5) parallel clock.
    // Separate PLL because TX lives in the BANK0/BANK1 HCLK group.
    //------------------------------------------------------------------
    wire pll_tx_lock;
    wire txclk_500m /* synthesis syn_keep=1 */;
    wire txclk_100m;

    pll_tx_500m u_pll_tx(
        .lock    (pll_tx_lock),
        .clkout0 (txclk_500m),
        .clkout1 (),
        .clkout2 (),
        .clkout3 (),
        .clkin   (clk_in)
    );

    CLKDIV u_clkdiv_tx(
        .HCLKIN (txclk_500m),
        .RESETN (resetn_in),
        .CALIB  (1'b0),
        .CLKOUT (txclk_100m)
    );
    defparam u_clkdiv_tx.DIV_MODE = "5";

    wire tx_rstn = resetn_in & pll_tx_lock;
    wire [9:0] tx_symbol;

    easycdr_trace_tx_core #(.FRAME_LEN(16)) u_tx_core(
        .clk      (txclk_100m),
        .rstn     (tx_rstn),
        .o_symbol (tx_symbol)
    );

    wire o_serial_data;
    OSER10 u_OSER10(
        .Q     (o_serial_data),
        .D0    (tx_symbol[0]),
        .D1    (tx_symbol[1]),
        .D2    (tx_symbol[2]),
        .D3    (tx_symbol[3]),
        .D4    (tx_symbol[4]),
        .D5    (tx_symbol[5]),
        .D6    (tx_symbol[6]),
        .D7    (tx_symbol[7]),
        .D8    (tx_symbol[8]),
        .D9    (tx_symbol[9]),
        .PCLK  (txclk_100m),
        .FCLK  (txclk_500m),
        .RESET (~tx_rstn)
    );

    ELVDS_OBUF u_tx(
        .I  (o_serial_data),
        .O  (o_serial_p),
        .OB (o_serial_n)
    );

    //------------------------------------------------------------------
    // RX checker (125MHz parallel-clock domain)
    //------------------------------------------------------------------
    localparam [7:0] K28_5 = 8'hbc;

    wire rx_word_en = rx_data_en && rx_align;
    wire rx_is_k    = rx_word_en &&  rx_data[8] && (rx_data[7:0] == K28_5);
    wire rx_is_d    = rx_word_en && !rx_data[8];

    reg [7:0] expect_d;
    reg       expect_vld;
    reg       err_pulse;
    reg [7:0] err_num;
    reg       decerr_sticky;
    always @(posedge pclk_rx or posedge rx_reset) begin
        if (rx_reset) begin
            expect_d      <= 8'd0;
            expect_vld    <= 1'b0;
            err_pulse     <= 1'b0;
            err_num       <= 8'd0;
            decerr_sticky <= 1'b0;
        end else begin
            err_pulse <= 1'b0;
            if (rx_is_d) begin
                if (expect_vld && rx_data[7:0] != expect_d) begin
                    err_pulse <= 1'b1;
                    err_num   <= err_num + 1'b1;
                end
                expect_d   <= rx_data[7:0] + 1'b1;  // resync on mismatch
                expect_vld <= 1'b1;
            end
            if (rx_data_en && rx_decerr) begin
                err_pulse     <= 1'b1;
                err_num       <= err_num + 1'b1;
                decerr_sticky <= 1'b1;
            end
            if (!rx_align)
                expect_vld <= 1'b0;
        end
    end

    // Comma watchdog: commas arrive every 160ns on a healthy link; drop the
    // lock indication if none is seen for ~65us.
    reg [12:0] act_cnt;
    reg        act_ok;
    always @(posedge pclk_rx or posedge rx_reset) begin
        if (rx_reset) begin
            act_cnt <= 13'd0;
            act_ok  <= 1'b0;
        end else if (rx_is_k) begin
            act_cnt <= 13'd0;
            act_ok  <= 1'b1;
        end else if (&act_cnt) begin
            act_ok <= 1'b0;
        end else begin
            act_cnt <= act_cnt + 1'b1;
        end
    end

    // Marker output: toggle every 256 commas -> ~82us period square wave.
    reg [7:0] k_cnt;
    reg       k_flag;
    always @(posedge pclk_rx or posedge rx_reset) begin
        if (rx_reset) begin
            k_cnt  <= 8'd0;
            k_flag <= 1'b0;
        end else if (rx_is_k) begin
            k_cnt <= k_cnt + 1'b1;
            if (&k_cnt) k_flag <= ~k_flag;
        end
    end

    assign o_dat_lock    = rx_align & act_ok;
    assign o_dat_err     = err_pulse;
    assign o_dat_err_num = err_num;
    assign O_ERROR       = decerr_sticky;
    assign dout_flag_xor = k_flag;

endmodule
