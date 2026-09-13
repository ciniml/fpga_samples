// EasyCDR trace-link (1Gbps, 8b10b): phase 3 - timestamped signal tracing.
//
// TX: trace_frontend samples a demo signal, emits [K28.1][ts x3][data x2]
//     records into the link (K28.3 idle filler between records).
// RX: records ({K flag, byte} entries) are captured into the buffer and
//     dumped over UART; host/trace_view.py reconstructs the events.
//
// TX (pmod2 lane L1, D10/D11): reverse control channel - 2Mbps Manchester
//     (rtl/manchester ManchesterTx). Host 'X' frames are forwarded to the
//     trace transmitter FPGA (reset / enable / ignore mask, see
//     rtl/manchester/README.md). The old 8b10b demo TX was replaced; its
//     PLL (pll_tx_500m) is gone.
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
    output           o_selftest_p,   // pmod0 lane L1 (G7/G8): own trace stream for the loopback self-test
    output           o_selftest_n,
    output           o_serial_p,
    output           o_serial_n,
    input            reset_in,        // push button, active high (pull-down)
    output           o_dat_err,      // counter mismatch or 8b10b decode error
    output           o_dat_lock,     // aligned + comma watchdog
    output wire[7:0] o_dat_err_num,  // error count
    output           O_ERROR,        // sticky 8b10b decode error
    output           dout_flag_xor,  // toggles every 256 commas (~82us square)
    output           uart_txd,       // to host (BL616 bridge, 115200 8N1)
    input            uart_rxd        // from host
    );

    wire resetn_in = ~reset_in;

    // Host UART baud rate (BL616 bridge). 115200 is the proven default;
    // build variants at 921600 / 2000000 exist for faster dumps.
    localparam UART_BAUD = 115200;

    //------------------------------------------------------------------
    // RX clocking: 500MHz x 4 phases for the EasyCDR IP (PLL_T)
    //------------------------------------------------------------------
    wire pll_rx_lock;
    wire rxclk_500m_0 /* synthesis syn_keep=1 */;
    wire rxclk_500m_90;
    wire rxclk_500m_180;
    wire rxclk_500m_270;

`ifdef RATE_742M5
    pll_rx_371m_4ph u_pll_rx(     // 742.5Mbps variant (make RATE=742M5)
`else
    pll_rx_500m_4ph u_pll_rx(
`endif
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
    // Reverse control channel TX: 2Mbps Manchester on lane L1 (G7/G8).
    // Bytes come from the host 'X' command (trace_capture o_fwd_*) through
    // a small elastic FIFO (the UART can outpace the 2Mbps link at high
    // baud rates; frames are 4 bytes, so 16 entries are plenty).
    //------------------------------------------------------------------
    wire       fwd_valid;
    wire [7:0] fwd_data;

    reg [7:0] cfifo [0:15];
    reg [4:0] cwp, crp;
    wire cf_empty = (cwp == crp);
    wire cf_full  = (cwp[4] != crp[4]) && (cwp[3:0] == crp[3:0]);
    always @(posedge clk_in or posedge reset_in) begin
        if (reset_in) begin
            cwp <= 5'd0;
        end else if (fwd_valid && !cf_full) begin
            cfifo[cwp[3:0]] <= fwd_data;
            cwp <= cwp + 1'b1;
        end
    end

    wire ctrl_tx_ready;
    always @(posedge clk_in or posedge reset_in) begin
        if (reset_in)                            crp <= 5'd0;
        else if (ctrl_tx_ready && !cf_empty)     crp <= crp + 1'b1;
    end

    wire man_txd;
    ManchesterTx #(.BIT_CYCLES(25)) u_ctrl_tx(   // 50MHz / 25 = 2Mbps
        .i_clk   (clk_in),
        .i_rst   (reset_in),
        .i_valid (!cf_empty),
        .i_data  (cfifo[crp[3:0]]),
        .o_ready (ctrl_tx_ready),
        .o_txd   (man_txd)
    );

    // Reset burst for the CTRL_PULSE Nano9K variant (host command 'P'):
    // 4 levels x 20us, takes over the line while busy. Harmless to the
    // Manchester receiver (it just sees link loss for 80us; frames are
    // never sent during a burst because the host waits for the 'P' reply).
    wire pulse_req, pulse_busy, pulse_txd;
    PulseResetTx #(.HALF_CYCLES(1000), .HALVES(4), .IDLE_HALF(25)) u_pulse_tx(
        .i_clk  (clk_in),
        .i_rst  (reset_in),
        .i_req  (pulse_req),
        .o_busy (pulse_busy),
        .o_txd  (pulse_txd)
    );
    wire ctrl_txd = pulse_busy ? pulse_txd : man_txd;

    ELVDS_OBUF u_tx(
        .I  (ctrl_txd),
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

    reg       err_pulse;
    reg [7:0] err_num;
    reg       decerr_sticky;
    always @(posedge pclk_rx or posedge rx_reset) begin
        if (rx_reset) begin
            err_pulse     <= 1'b0;
            err_num       <= 8'd0;
            decerr_sticky <= 1'b0;
        end else begin
            err_pulse <= 1'b0;
            if (rx_data_en && rx_decerr) begin
                err_pulse     <= 1'b1;
                err_num       <= err_num + 1'b1;
                decerr_sticky <= 1'b1;
            end
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

    //------------------------------------------------------------------
    // Phase 2: payload capture buffer + UART dump (see trace_capture.v)
    //------------------------------------------------------------------
    localparam [7:0] K28_1 = 8'h3c;   // start of record
    localparam [7:0] K28_2 = 8'h5c;   // overflow marker
    // descriptor payload bytes must not enter the capture buffer
    wire desc_busy;
    wire cap_valid = rx_word_en && !desc_busy &&
                     (!rx_data[8] ||
                      rx_data[7:0] == K28_1 || rx_data[7:0] == K28_2);

    // on-the-fly record decoder feeding the trigger comparator
    wire        rec_valid;
    wire [31:0] rec_ts;
    wire [63:0] rec_data;
    wire [7:0]  desc_ver, desc_width, desc_tsbits, desc_flags;
    trace_rx_decoder #(.MAX_WIDTH(64), .MAX_TS_BITS(32)) u_decoder(   // layout from the descriptor
        .clk       (pclk_rx),
        .rst       (rx_reset),
        .in_valid  (rx_word_en),
        .in_word   (rx_data[8:0]),
        .rec_valid (rec_valid),
        .rec_ts    (rec_ts),
        .rec_data  (rec_data),
        .ovf_seen  (),
        .o_desc_ver    (desc_ver),
        .o_desc_width  (desc_width),
        .o_desc_tsbits (desc_tsbits),
        .o_desc_flags  (desc_flags),
        .o_desc_busy   (desc_busy)
    );

    // Host transport: UART today; a USB CDC core can replace this block by
    // driving the same byte-stream interface of trace_capture.
    wire       h_rx_valid, h_tx_valid, h_tx_ready;
    wire [7:0] h_rx_data,  h_tx_data;
    uart_rx #(.BAUD_DIVIDER(50_000_000 / UART_BAUD)) u_uart_rx(
        .clock(clk_in), .reset(reset_in),
        .data_valid(h_rx_valid), .data_ready(1'b1), .data_bits(h_rx_data),
        .rx(uart_rxd), .overrun());
    uart_tx #(.BAUD_DIVIDER(50_000_000 / UART_BAUD)) u_uart_tx(
        .clock(clk_in), .reset(reset_in),
        .data_valid(h_tx_valid), .data_ready(h_tx_ready), .data_bits(h_tx_data),
        .tx(uart_txd));

    //------------------------------------------------------------------
    // Link diagnostics (host command 'L') and loopback self-test source
    //------------------------------------------------------------------
    wire         diag_req, diag_done;
    wire [111:0] diag_data;
    trace_link_diag u_diag(
        .pclk(pclk_rx), .prst(rx_reset),
        .i_data_en(rx_data_en), .i_word(rx_data[8:0]), .i_decerr(rx_decerr),
        .i_status({3'b0, rx_reset, act_ok, desc_ver != 8'd0, rx_align, pll_rx_lock}),
        .i_desc_ver(desc_ver),
        .clk_sys(clk_in), .rst_sys(reset_in),
        .i_req(diag_req), .o_done(diag_done), .o_data(diag_data));

    // Self-test transmitter: a second trace core sending a free-running
    // 16-bit counter (steps every 5.12us) on pmod0 lane L1. Loop a USB-C
    // cable from pmod0 to pmod2 and the receiver sees this stream without
    // any other board (ctrl_test.py --selftest). Not built in the 742.5Mbps
    // variant (separate TX PLL would be needed).
    wire st_serial;
`ifndef RATE_742M5
    wire pll_tx_lock;
    wire txclk_500m /* synthesis syn_keep=1 */;
    wire txclk_100m;
    pll_tx_500m u_pll_tx(
        .lock(pll_tx_lock), .clkout0(txclk_500m), .clkout1(), .clkout2(), .clkout3(), .clkin(clk_in));
    CLKDIV u_clkdiv_tx(.HCLKIN(txclk_500m), .RESETN(resetn_in), .CALIB(1'b0), .CLKOUT(txclk_100m));
    defparam u_clkdiv_tx.DIV_MODE = "5";
    wire st_rstn = resetn_in & pll_tx_lock;

    reg [23:0] st_cnt;
    always @(posedge clk_in or posedge reset_in)
        if (reset_in) st_cnt <= 24'd0; else st_cnt <= st_cnt + 1'b1;

    wire [9:0] st_symbol;
    easycdr_trace_tx #(.WIDTH(16), .TS_BITS(24), .SYNC_STAGES(0), .HAS_PERIODIC(0), .HAS_TRIGGER(0), .FIFO_RAM("block")) u_st_tx(
        .sclk(clk_in), .srstn(resetn_in), .sig(st_cnt[23:8]),
        .clk(txclk_100m), .rstn(st_rstn),
        .i_enable(1'b1), .i_ignore_mask(16'd0), .i_desc_req(1'b0), .i_periodic_en(1'b0), .i_change_dis(1'b0),
        .i_period(24'd0), .i_arm(1'b0), .i_trig_mask(16'd0), .i_trig_value(16'd0), .i_post(16'd0),
        .o_symbol(st_symbol), .o_overflow(), .o_armed(), .o_triggered(), .o_done());
    OSER10 u_st_oser(
        .Q(st_serial),
        .D0(st_symbol[0]), .D1(st_symbol[1]), .D2(st_symbol[2]), .D3(st_symbol[3]), .D4(st_symbol[4]),
        .D5(st_symbol[5]), .D6(st_symbol[6]), .D7(st_symbol[7]), .D8(st_symbol[8]), .D9(st_symbol[9]),
        .PCLK(txclk_100m), .FCLK(txclk_500m), .RESET(~st_rstn));
`else
    assign st_serial = 1'b0;
`endif
    ELVDS_OBUF u_st_obuf(.I(st_serial), .O(o_selftest_p), .OB(o_selftest_n));

    trace_capture #(
        .ADDR_BITS    (14),                 // 16Ki entries ({K,byte})
        .DATA_BITS    (9),
        .MAX_WIDTH    (64)
    ) u_capture(
        .pclk       (pclk_rx),
        .prst       (rx_reset),
        .in_valid   (cap_valid),
        .in_data    (rx_data[8:0]),
        .rec_valid  (rec_valid),
        .rec_data   (rec_data),
        .i_desc_ver    (desc_ver),
        .i_desc_width  (desc_width),
        .i_desc_tsbits (desc_tsbits),
        .i_desc_flags  (desc_flags),
        .clk_sys    (clk_in),
        .rst_sys    (reset_in),
        .h_rx_valid (h_rx_valid),
        .h_rx_data  (h_rx_data),
        .h_tx_valid (h_tx_valid),
        .h_tx_data  (h_tx_data),
        .h_tx_ready (h_tx_ready),
        .o_fwd_valid (fwd_valid),
        .o_fwd_data  (fwd_data),
        .o_pulse_req (pulse_req),
        .o_diag_req  (diag_req),
        .i_diag_done (diag_done),
        .i_diag_data (diag_data)
    );

    assign o_dat_lock    = rx_align & act_ok;
    assign o_dat_err     = err_pulse;
    assign o_dat_err_num = err_num;
    assign O_ERROR       = decerr_sticky;
    assign dout_flag_xor = k_flag;

endmodule
