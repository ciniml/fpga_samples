// EasyCDR BERT: bit-error-rate tester for the 1Gbps ExtEasyCDR / USB-C link.
//
//   TX : rtl/bert PrbsGen (8 bits per 125MHz clock) -> OSER8 (FCLK 500MHz
//        from a dedicated PLL in the BANK0/1 HCLK group) -> pmod0 lane L1
//        (G7/G8). The BERT core runs in the RX parallel clock domain; the
//        8-bit word crosses to the TX clock through a small async FIFO
//        (both 125MHz clocks come from the same 50MHz crystal).
//   RX : own EasyCDR-compatible PHY (oscdr_phy_gw5a: TLVDS_IBUF -> OSIDES32
//        -> rtl/oscdr OsCdr -> gearbox), raw 16-bit words on pmod2 lane L0
//        (G11/G10) -> PrbsChk. `define USE_EASYCDR_IP swaps in the Gowin IP
//        (no bit reversal needed for either: word[0] is the earliest bit).
//        Own PHY extras: CDR freeze + IODELAY scan offset (BertCore
//        EXT_CTRL 0x30/0x31) for BERT-based eye scans.
//   Host: UART (C3/B3, 115200) -> BertHost register bridge. See
//        rtl/bert/README.md for the register map and host/bert.html.
//
// Physical link, termination, CTLE and drive settings are identical to
// eda/easycdr_trace (see its README).
module top(
    input            clk_in,          // 50MHz
    input            i_serial_p,
    input            i_serial_n,
    output           o_tone_p,        // pmod2 L1 (D10/D11): 125MHz tone for the standalone IODELAY test
    output           o_tone_n,
    input            i_tone_p,        // pmod0 L0 (F5/G5): tone back through the cable -> IODELAY under test
    input            i_tone_n,
    output           o_serial_p,
    output           o_serial_n,
    input            reset_in,        // push button, active high
    output           o_dat_err,       // stretched error pulse (C2)
    output           o_dat_lock,      // PRBS lock (B2)
    output wire[7:0] o_dat_err_num,   // unused (kept for the shared cst)
    output           O_ERROR,         // unused
    output           dout_flag_xor,   // RX activity (E1)
    output           uart_txd,
    input            uart_rxd
    );
    wire resetn_in = ~reset_in;
    localparam UART_BAUD = 115200;

    //------------------------------------------------------------------
    // RX: own EasyCDR-compatible PHY (default) or the Gowin IP (define
    // USE_EASYCDR_IP for A/B comparison). Both provide pclk (125MHz),
    // a pclk-domain reset and raw 16-bit words + strobe.
    //------------------------------------------------------------------
    wire        pll_rx_lock;
    wire        pclk;          // 125MHz parallel clock
    wire        rx_reset;      // pclk-domain reset, active high
    wire [15:0] rx_data;
    wire        rx_data_en;
    wire [15:0] ext_ctrl;      // BertCore 0x30/0x31
    wire [7:0]  ext_status;    // BertCore 0x32
`ifdef USE_EASYCDR_IP
    ip_phy_gw5a u_phy(
        .clk_in(clk_in), .rstn_in(resetn_in),
        .i_serial_p(i_serial_p), .i_serial_n(i_serial_n),
        .o_pclk(pclk), .o_reset(rx_reset), .o_pll_lock(pll_rx_lock),
        .o_dout(rx_data), .o_dout_en(rx_data_en));
    assign ext_status = 8'h00;
    wire [6:0] dbg_addr;
    wire [7:0] dbg_data = 8'h00;
`else
    // ext_ctrl[0] = freeze CDR phase, [1] = TX PLL PSDIR, [2] = TX PLL PSPULSE,
    // [3] = IODELAY_1 SDTAP, [4] = IODELAY_1 VALUE (host toggles it for edges), [5] = OSIDES32 reset,
    // [14:8] = IODELAY_1 DLYSTEP (DYN_DLY1 build only), [15] = raw sample capture trigger
`ifdef DYN_DLY1
    localparam PHY_DYN1 = "TRUE";
`else
    localparam PHY_DYN1 = "FALSE";
`endif
`ifdef DYN_DLY0
    localparam PHY_DYN0 = "TRUE";
`else
    localparam PHY_DYN0 = "FALSE";
`endif
`ifdef ADAPT_DLY1
    localparam PHY_ADAPT1 = "TRUE";
`else
    localparam PHY_ADAPT1 = "FALSE";
`endif
    wire cdr_lock, cdr_slip, dly_sat;
    wire [1:0] cdr_phase;
    wire [31:0] raw_samples;
    oscdr_phy_gw5a #(.DLY0(0), .DLY1(21), .DYN1(PHY_DYN1), .DYN0(PHY_DYN0), .ADAPT1(PHY_ADAPT1)) u_phy(
        .clk_in(clk_in), .rstn_in(resetn_in),
        .i_serial_p(i_serial_p), .i_serial_n(i_serial_n),
        .i_freeze(ext_ctrl[0]),
        .i_sdtap1(ext_ctrl[3]), .i_value1(ext_ctrl[4]), .i_dlystep1({1'b0, ext_ctrl[14:8]}), .i_osides_rst(ext_ctrl[5]),
        .o_pclk(pclk), .o_reset(rx_reset), .o_pll_lock(pll_rx_lock),
        .o_dout(rx_data), .o_dout_en(rx_data_en),
        .o_cdr_lock(cdr_lock), .o_cdr_phase(cdr_phase), .o_cdr_slip(cdr_slip), .o_dly_sat(dly_sat),
        .o_samples(raw_samples));
    // raw sample capture: ext_ctrl[15] rising edge stores 32 consecutive
    // OSIDES32 words; readable through BertCore 0x80..0xFF (byte k of word k/4)
    reg  [31:0] cap_mem [0:31];
    reg  [5:0]  cap_cnt;
    reg         cap_arm_q;
    always @(posedge pclk or posedge rx_reset) begin
        if (rx_reset) begin
            cap_cnt <= 6'd32; cap_arm_q <= 1'b0;
        end else begin
            cap_arm_q <= ext_ctrl[15];
            if (ext_ctrl[15] && !cap_arm_q) cap_cnt <= 6'd0;
            else if (cap_cnt != 6'd32) begin
                cap_mem[cap_cnt[4:0]] <= raw_samples;
                cap_cnt <= cap_cnt + 1'b1;
            end
        end
    end
    // read side registered (the address is quasi-static before a request)
    wire [6:0]  dbg_addr;
    reg  [31:0] dbg_word;
    reg  [7:0]  dbg_data;
    always @(posedge pclk) begin
        dbg_word <= cap_mem[dbg_addr[6:2]];
        dbg_data <= dbg_word[dbg_addr[1:0]*8 +: 8];
    end
    // slip activity: stretched so the host can see it
    reg [15:0] slip_cnt;
    always @(posedge pclk or posedge rx_reset)
        if (rx_reset) slip_cnt <= 16'd0; else if (cdr_slip) slip_cnt <= slip_cnt + 1'b1;
`ifdef IODLY_TEST
    assign ext_status = ext_status_iodly;
`else
    assign ext_status = {slip_cnt[3:0], dly_sat, cdr_phase, cdr_lock};
`endif
`endif

    //------------------------------------------------------------------
    // TX clocking: dedicated 500MHz PLL + CLKDIV/4 = 125MHz
    //------------------------------------------------------------------
    wire pll_tx_lock;
    wire txclk_500m /* synthesis syn_keep=1 */;
    wire txclk_125m;
    // Eye scan: the TX PLL's channel 0 phase is stepped by 125ps per PSPULSE
    // (ext_ctrl[2], direction ext_ctrl[1]) while the RX CDR phase is frozen
    // (ext_ctrl[0]); the data eye then moves across the fixed RX sampling
    // point and the BERT counts errors per step.
    pll_tx_500m u_pll_tx(
        .lock(pll_tx_lock), .clkout0(txclk_500m), .clkout1(), .clkout2(), .clkout3(), .clkin(clk_in),
        .psdir(ext_ctrl[1]), .pspulse(ext_ctrl[2]));
    CLKDIV u_clkdiv_tx(.HCLKIN(txclk_500m), .RESETN(resetn_in), .CALIB(1'b0), .CLKOUT(txclk_125m));
    defparam u_clkdiv_tx.DIV_MODE = "4";
    wire tx_rst = reset_in | ~pll_tx_lock;

    //------------------------------------------------------------------
    // Standalone IODELAY test (IODLY_TEST=1): a 500MHz tone straight from the
    // DPS-shifted TX clock (no divider: CLKDIV re-syncs on phase steps and
    // breaks the linear phase ramp) goes out on pmod2 L1,
    // comes back on pmod0 L0, through an IODELAY in dynamic mode, and is
    // sampled by a flip-flop on the RX pclk (fixed phase). The fraction of
    // ones over 255 samples (ext_status) locates the tone edge relative to
    // the sampling instant; moving the IODELAY must move that edge.
    //------------------------------------------------------------------
    wire tone_ser;
`ifdef IODLY_TEST
    ODDR u_tone_oddr(.Q0(tone_ser), .Q1(), .D0(1'b1), .D1(1'b0), .TX(1'b0), .CLK(txclk_500m));
    wire tone_in, tone_dly, dly_df;
    TLVDS_IBUF u_tone_ibuf(.O(tone_in), .I(i_tone_p), .IB(i_tone_n));
`ifndef IODLY_STATIC
`define IODLY_STATIC 0
`endif
`ifdef IODLY_DYN
    localparam IODLY_DYN_EN = "TRUE";
`else
    localparam IODLY_DYN_EN = "FALSE";
`endif
`ifdef IODLY_ADAPT
    localparam IODLY_ADAPT_EN = "TRUE";
`else
    localparam IODLY_ADAPT_EN = "FALSE";
`endif
    IODELAY #(.C_STATIC_DLY(`IODLY_STATIC), .DYN_DLY_EN(IODLY_DYN_EN), .ADAPT_EN(IODLY_ADAPT_EN)) u_tone_dly(
        .DO(tone_dly), .DF(dly_df), .DI(tone_in),
        .SDTAP(ext_ctrl[3]), .VALUE(ext_ctrl[4]), .DLYSTEP({1'b0, ext_ctrl[14:8]}));
    reg        tone_s0, tone_s1;
    reg [7:0]  tone_cnt, tone_ones, tone_acc;
    always @(posedge pclk) begin
        tone_s0 <= tone_dly;
        tone_s1 <= tone_s0;
        if (tone_cnt == 8'd254) begin
            tone_ones <= tone_acc + tone_s1;
            tone_acc  <= 8'd0;
            tone_cnt  <= 8'd0;
        end else begin
            tone_acc <= tone_acc + tone_s1;
            tone_cnt <= tone_cnt + 1'b1;
        end
    end
    wire [7:0] ext_status_iodly = tone_ones;   // 0..255 = ones per 255 samples
`else
    assign tone_ser = 1'b0;
    wire [7:0] ext_status_iodly = 8'h00;
`endif
    ELVDS_OBUF u_tone_obuf(.I(tone_ser), .O(o_tone_p), .OB(o_tone_n));

    //------------------------------------------------------------------
    // BERT core (pclk) + host bridge (clk_in)
    //------------------------------------------------------------------
    wire [7:0] tx_word;
    wire       reg_req, reg_wr;
    wire [7:0] reg_addr, reg_wdat, reg_rdat;
    wire       locked;
    // Verified on hardware (2026-09-13): the raw 16-bit dout_o of the 1.9.12
    // core already delivers bit 0 = earliest on the wire for this checker,
    // so no bit reversal (RX_BITREV=1 does NOT lock).
    BertCore #(.TX_WIDTH(8), .RX_WIDTH(16), .RX_BITREV_DEFAULT(1'b0)) u_core(
        .i_clk(pclk), .i_rst(rx_reset),
        .o_tx_data(tx_word),
        .i_rx_valid(rx_data_en), .i_rx_data(rx_data), .i_link_ok(pll_rx_lock & pll_tx_lock),
        .o_ext_ctrl(ext_ctrl), .i_ext_status(ext_status), .o_dbg_addr(dbg_addr), .i_dbg_data(dbg_data),
        .i_reg_req(reg_req), .i_reg_wr(reg_wr), .i_reg_addr(reg_addr), .i_reg_wdat(reg_wdat), .o_reg_rdat(reg_rdat),
        .o_locked(locked));

    wire       h_rx_valid, h_tx_valid, h_tx_ready;
    wire [7:0] h_rx_data,  h_tx_data;
    uart_rx #(.BAUD_DIVIDER(50_000_000 / UART_BAUD)) u_uart_rx(
        .clock(clk_in), .reset(reset_in),
        .data_valid(h_rx_valid), .data_ready(1'b1), .data_bits(h_rx_data), .rx(uart_rxd), .overrun());
    uart_tx #(.BAUD_DIVIDER(50_000_000 / UART_BAUD)) u_uart_tx(
        .clock(clk_in), .reset(reset_in),
        .data_valid(h_tx_valid), .data_ready(h_tx_ready), .data_bits(h_tx_data), .tx(uart_txd));

    BertHost u_host(
        .i_clk(clk_in), .i_rst(reset_in),
        .i_rx_valid(h_rx_valid), .i_rx_data(h_rx_data),
        .o_tx_valid(h_tx_valid), .o_tx_data(h_tx_data), .i_tx_ready(h_tx_ready),
        .i_lclk(pclk), .i_lrst(rx_reset),
        .o_reg_req(reg_req), .o_reg_wr(reg_wr), .o_reg_addr(reg_addr), .o_reg_wdat(reg_wdat), .i_reg_rdat(reg_rdat));

    //------------------------------------------------------------------
    // pclk -> txclk_125m word FIFO (8 entries, gray pointers). Both clocks
    // are 125MHz from the same crystal, so once primed the occupancy is
    // constant; the reader waits until 4 entries are queued.
    //------------------------------------------------------------------
    reg [7:0] wfifo [0:7];
    reg [3:0] wp_bin;  reg [3:0] wp_gray;
    reg [3:0] rp_bin;  reg [3:0] rp_gray;
    reg [3:0] wp_gray_t0, wp_gray_t1;   // wp gray synced into txclk
    reg       primed;
    always @(posedge pclk or posedge rx_reset) begin
        if (rx_reset) begin
            wp_bin <= 4'd0; wp_gray <= 4'd0;
        end else begin
            wfifo[wp_bin[2:0]] <= tx_word;
            wp_bin  <= wp_bin + 1'b1;
            wp_gray <= (wp_bin + 1'b1) ^ ((wp_bin + 1'b1) >> 1);
        end
    end
    function [3:0] gray2bin(input [3:0] g);
        gray2bin = {g[3], g[3]^g[2], g[3]^g[2]^g[1], g[3]^g[2]^g[1]^g[0]};
    endfunction
    wire [3:0] wp_bin_t = gray2bin(wp_gray_t1);
    wire [3:0] occ      = wp_bin_t - rp_bin;
    reg  [7:0] oser_word;
    always @(posedge txclk_125m or posedge tx_rst) begin
        if (tx_rst) begin
            wp_gray_t0 <= 4'd0; wp_gray_t1 <= 4'd0;
            rp_bin <= 4'd0; rp_gray <= 4'd0; primed <= 1'b0;
            oser_word <= 8'h00;
        end else begin
            wp_gray_t0 <= wp_gray; wp_gray_t1 <= wp_gray_t0;
            if (!primed) begin
                if (occ >= 4'd4) primed <= 1'b1;
            end else if (occ != 4'd0) begin
                oser_word <= wfifo[rp_bin[2:0]];
                rp_bin    <= rp_bin + 1'b1;
            end
        end
    end

    // (An IODELAY in the TX output path was tried for the eye scan: the
    // taps worked - 1 tap = 12.5ps confirmed - but the delay line degrades
    // the 1Gbps signal so much that the PRBS never locks. Removed.)
    wire o_serial_data;
    wire tx_dly_sat = 1'b0;
    OSER8 u_OSER8(
        .Q0(o_serial_data), .Q1(),
        .D0(oser_word[0]), .D1(oser_word[1]), .D2(oser_word[2]), .D3(oser_word[3]),
        .D4(oser_word[4]), .D5(oser_word[5]), .D6(oser_word[6]), .D7(oser_word[7]),
        .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
        .PCLK(txclk_125m), .FCLK(txclk_500m), .RESET(tx_rst));
    ELVDS_OBUF u_tx(.I(o_serial_data), .O(o_serial_p), .OB(o_serial_n));

    //------------------------------------------------------------------
    // status pins
    //------------------------------------------------------------------
    reg [15:0] act_cnt; reg act_ok;
    reg [19:0] err_stretch;
    always @(posedge pclk or posedge rx_reset) begin
        if (rx_reset) begin
            act_cnt <= 16'd0; act_ok <= 1'b0; err_stretch <= 20'd0;
        end else begin
            if (rx_data_en) begin act_cnt <= 16'd0; act_ok <= 1'b1; end
            else if (&act_cnt) act_ok <= 1'b0;
            else act_cnt <= act_cnt + 1'b1;
            if (u_core.u_chk.o_valid && u_core.u_chk.o_errs != 0) err_stretch <= 20'hfffff;
            else if (err_stretch != 0) err_stretch <= err_stretch - 1'b1;
        end
    end
    assign o_dat_lock    = locked;
    assign o_dat_err     = (err_stretch != 0);
    assign dout_flag_xor = act_ok;
    assign o_dat_err_num = 8'h00;
    assign O_ERROR       = 1'b0;
endmodule
