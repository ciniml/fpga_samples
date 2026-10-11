// Logic analyzer on the Sipeed SLogic16U3 (GW5AT-15): 16 channels at up to 800 MS/s, streamed over
// USB 3.0 (rtl/la LaCore + rtl/usb3).
//
//   125 MHz oscillator (Q0 REFCLK0, D14 = OE) -> USB 3.0 PHY (src of ../slogic16u3_usb3) -> pclk 125 MHz
//   pclk -> pll_la400 -> fclk 400 MHz -> CLKDIV /4 -> sclk 100 MHz
//   CH0..15 (SSTL33 against the external VREF on M8 = J12's PWM through an RC: the input buffers are
//   the comparators, the inputs are divided by ~2 on the board) and the clock inputs CK0 / CK1
//   (H13 / G13, not divided) -> IDES8 (fclk DDR: 800 MS/s, 8 samples per sclk) -> LaCore
//   LaCore stream (AXI4-Stream, 32 bits, pclk) -> Usb3Device EP1 IN word input
//   LaCore registers <- vendor requests 0x03 (write) / 0x04 (read) (host/la_stream.c)
//
// Status over JTAG: ER1 (IR 0x42) read-only (jtag_status.v of ../slogic16u3_usb3, host/la_status.py).
module top (
    input  wire tck_pad_i,
    input  wire tms_pad_i,
    input  wire tdi_pad_i,
    output wire tdo_pad_o,

    input  wire usb_cmp_dp,    // H3 / H2: USB 2.0 D+ comparator (unused, kept quiet)
    input  wire usb_cmp_dp_n,
    input  wire usb_cmp_dn,    // M2 / M1
    input  wire usb_cmp_dn_n,
    input  wire usb_dxp,       // K3, K2, P2, P1 (inputs, no pull)
    input  wire usb_dxn,
    input  wire usb_tdp,
    input  wire usb_tdn,
    output wire usb_pullup,    // C14 (off: SuperSpeed only)
    output wire xo_en,         // D14: 125 MHz oscillator enable
    output wire led_r,         // G14: capturing

    input  wire [15:0] la_ch,  // CH0..15
    input  wire la_ck0,        // CK0 (H13): clock input of CH0..7
    input  wire la_ck1,        // CK1 (G13): clock input of CH8..15
    output wire vref_pwm       // J12: threshold PWM -> RC -> M8 (VREF)
);
    wire osc;   // ~51.7 MHz (measured)
    OSCA #(.FREQ_DIV(4)) u_osc (.OSCOUT(osc), .OSCEN(1'b1));
    assign xo_en = 1'b1;
    assign usb_pullup = 1'b0;
    wire cmp_dp, cmp_dn;
    TLVDS_IBUF u_cmp_dp (.I(usb_cmp_dp), .IB(usb_cmp_dp_n), .O(cmp_dp));
    TLVDS_IBUF u_cmp_dn (.I(usb_cmp_dn), .IB(usb_cmp_dn_n), .O(cmp_dn));

    // ---------------------------------------------------------------- ref_clk, PHY reset (as slogic16u3_usb3)
    reg [20:0] seq = 21'd0;
    always @(posedge osc) if (!seq[20]) seq <= seq + 21'd1;
    wire ref_clk /* synthesis syn_keep=1 */, ref_lock;
    pll_ref125 u_pll (.lock(ref_lock), .clkout0(ref_clk), .clkin(osc));
    reg [2:0] start_s = 3'd0;
    reg [16:0] phy_rst_cnt = 17'd0;
    wire phy_resetn = phy_rst_cnt[16];
    always @(posedge ref_clk) begin
        start_s <= {start_s[1:0], seq[20] & ref_lock};
        if (!start_s[2]) phy_rst_cnt <= 17'd0;
        else if (!phy_resetn) phy_rst_cnt <= phy_rst_cnt + 17'd1;
    end

    // ---------------------------------------------------------------- PHY
    wire pclk /* synthesis syn_keep=1 */;
    wire [31:0] rx_data, tx_data; wire [3:0] rx_k, tx_k; wire rx_valid, rx_elecidle, phy_status, power_present;
    wire [2:0] rx_status; wire [1:0] power_down; wire tx_elecidle, tx_detectrx, rx_polarity, rx_termination;
    SerDes_Top u_serdes (
        .USB3_0_PHY_Top_pclk(pclk),
        .USB3_0_PHY_Top_PipeRxData(rx_data),
        .USB3_0_PHY_Top_PipeRxDataK(rx_k),
        .USB3_0_PHY_Top_PipeRxDataValid(rx_valid),
        .USB3_0_PHY_Top_RxElecIdle(rx_elecidle),
        .USB3_0_PHY_Top_RxStatus(rx_status),
        .USB3_0_PHY_Top_PhyStatus(phy_status),
        .USB3_0_PHY_Top_PowerPresent(power_present),
        .USB3_0_PHY_Top_ref_clk(ref_clk),
        .USB3_0_PHY_Top_phy_resetn(phy_resetn),
        .USB3_0_PHY_Top_PipeTxData(tx_data),
        .USB3_0_PHY_Top_PipeTxDataK(tx_k),
        .USB3_0_PHY_Top_TxDetectRx_loopback(tx_detectrx),
        .USB3_0_PHY_Top_TxElecIdle(tx_elecidle),
        .USB3_0_PHY_Top_RxPolarity(rx_polarity),
        .USB3_0_PHY_Top_RxEqTraining(1'b0),
        .USB3_0_PHY_Top_RxTermination(rx_termination),
        .USB3_0_PHY_Top_TxOnesZeros(1'b0),
        .USB3_0_PHY_Top_PowerDown(power_down),
        .USB3_0_PHY_Top_ElasticityBufferMode(1'b0));

    // pclk-domain reset: held for 4096 pclk after phy_resetn (synchronised)
    reg [2:0] prn_s = 3'd0;
    reg [12:0] prst_cnt = 13'd0;
    always @(posedge pclk) begin
        prn_s <= {prn_s[1:0], phy_resetn};
        if (!prn_s[2]) prst_cnt <= 13'd0;
        else if (!prst_cnt[12]) prst_cnt <= prst_cnt + 13'd1;
    end
    wire prst = !prst_cnt[12];

    // ---------------------------------------------------------------- sample clocks
    // pclk -> PLL (held in reset with the pclk domain) -> fclk 400 MHz -> CLKDIV /4 -> sclk 100 MHz.
    // The divider leaves reset ~1 us after the lock; the sclk domain (and the IDES8s) ~10 us later.
    wire fclk_pll, s_lock;
    pll_la400 u_pll_la (.lock(s_lock), .clkout0(fclk_pll), .clkin(pclk), .reset(prst));
    reg [7:0] lock_cnt = 8'd0;   // pclk
    always @(posedge pclk) begin
        if (prst || !s_lock) lock_cnt <= 8'd0;
        else if (!lock_cnt[7]) lock_cnt <= lock_cnt + 8'd1;
    end
    wire div_resetn = lock_cnt[7];
    wire fclk, sclk /* synthesis syn_keep=1 */;
    DHCE u_dhce (.CLKIN(fclk_pll), .CEN(1'b0), .CLKOUT(fclk));
    CLKDIV u_clkdiv (.HCLKIN(fclk), .RESETN(div_resetn), .CALIB(1'b0), .CLKOUT(sclk));
    defparam u_clkdiv.DIV_MODE = "4";
    reg [2:0]  dr_s = 3'd0;
    reg [10:0] srst_cnt = 11'd0;
    always @(posedge sclk or negedge div_resetn) begin
        if (!div_resetn) begin dr_s <= 3'd0; srst_cnt <= 11'd0; end
        else begin
            dr_s <= {dr_s[1:0], 1'b1};
            if (dr_s[2] && !srst_cnt[10]) srst_cnt <= srst_cnt + 11'd1;
        end
    end
    wire srst = !srst_cnt[10];

    // ---------------------------------------------------------------- input samplers
    // IDES8: Q0 is the earliest of the 8 samples of a sclk
    wire [7:0] q_ch [0:15];
    wire [7:0] q_ck0, q_ck1;
    genvar c;
    generate for (c = 0; c < 16; c = c + 1) begin : g_ides
        IDES8 u_ides (.D(la_ch[c]), .FCLK(fclk), .PCLK(sclk), .CALIB(1'b0), .RESET(srst),
            .Q0(q_ch[c][0]), .Q1(q_ch[c][1]), .Q2(q_ch[c][2]), .Q3(q_ch[c][3]),
            .Q4(q_ch[c][4]), .Q5(q_ch[c][5]), .Q6(q_ch[c][6]), .Q7(q_ch[c][7]));
    end endgenerate
    IDES8 u_ides_ck0 (.D(la_ck0), .FCLK(fclk), .PCLK(sclk), .CALIB(1'b0), .RESET(srst),
        .Q0(q_ck0[0]), .Q1(q_ck0[1]), .Q2(q_ck0[2]), .Q3(q_ck0[3]), .Q4(q_ck0[4]), .Q5(q_ck0[5]), .Q6(q_ck0[6]), .Q7(q_ck0[7]));
    IDES8 u_ides_ck1 (.D(la_ck1), .FCLK(fclk), .PCLK(sclk), .CALIB(1'b0), .RESET(srst),
        .Q0(q_ck1[0]), .Q1(q_ck1[1]), .Q2(q_ck1[2]), .Q3(q_ck1[3]), .Q4(q_ck1[4]), .Q5(q_ck1[5]), .Q6(q_ck1[6]), .Q7(q_ck1[7]));
    // to LaCore's layout: sample i of a group in [8i+7:8i], channel c of the group in bit c of it
    // (registered once in sclk: the IDES8 outputs go straight into flip-flops)
    reg [63:0] raw_a = 64'd0, raw_b = 64'd0;
    reg [7:0]  ck_a = 8'd0, ck_b = 8'd0;
    integer i, k;
    always @(posedge sclk) begin
        for (i = 0; i < 8; i = i + 1)
            for (k = 0; k < 8; k = k + 1) begin
                raw_a[i*8 + k] <= q_ch[k][i];
                raw_b[i*8 + k] <= q_ch[8 + k][i];
            end
        ck_a <= q_ck0;
        ck_b <= q_ck1;
    end

    // ---------------------------------------------------------------- link + protocol
    wire rx_hp_valid; wire [95:0] rx_hp_hdr;
    wire dpp_start, dpp_valid, dpp_end, dpp_err; wire [31:0] dpp_data; wire [3:0] dpp_be;
    wire tx_hp_valid, tx_dpp, tx_hp_ready, tx_hp_idle; wire [95:0] tx_hp_hdr; wire [10:0] tx_dpp_len; wire [12:0] tx_dpp_base;
    wire dpp_rd; wire [12:0] dpp_addr; wire [31:0] dpp_rdata;
    wire [4:0] ltssm_state; wire in_u0, u0_entry, hot_reset, warm_reset, link_configured;
    wire dev_configured, dev_reset, dbg_event, dbg_strobe; wire [63:0] dbg_state; wire [6:0] dev_address; wire [15:0] vendor_reg;
    wire ep_rx_valid, ep_tx_ready; wire [7:0] ep_rx_data;
    wire la_tvalid, la_tready, la_tlast; wire [31:0] la_tdata;
    wire reg_wr; wire [7:0] reg_addr; wire [15:0] reg_wdata; wire [31:0] reg_rdata;

    Usb3Top u_usb3 (.i_clk(pclk), .i_rst(prst),
        .i_rx_data(rx_data), .i_rx_k(rx_k), .i_rx_valid(rx_valid), .i_rx_status(rx_status), .i_rx_elecidle(rx_elecidle),
        .i_phy_status(phy_status), .i_power_present(1'b1),
        .o_tx_data(tx_data), .o_tx_k(tx_k), .o_tx_elecidle(tx_elecidle), .o_tx_detectrx(tx_detectrx),
        .o_power_down(power_down), .o_rx_polarity(rx_polarity), .o_rx_termination(rx_termination),
        .o_rx_hp_valid(rx_hp_valid), .o_rx_hp_hdr(rx_hp_hdr),
        .o_dpp_start(dpp_start), .o_dpp_valid(dpp_valid), .o_dpp_data(dpp_data), .o_dpp_be(dpp_be), .o_dpp_end(dpp_end), .o_dpp_err(dpp_err),
        .i_tx_hp_valid(tx_hp_valid), .i_tx_hp_hdr(tx_hp_hdr), .i_tx_dpp(tx_dpp), .i_tx_dpp_len(tx_dpp_len), .i_tx_dpp_base(tx_dpp_base),
        .o_tx_hp_ready(tx_hp_ready), .o_tx_hp_idle(tx_hp_idle),
        .o_dpp_rd(dpp_rd), .o_dpp_addr(dpp_addr), .i_dpp_data(dpp_rdata),
        .o_ltssm_state(ltssm_state), .o_in_u0(in_u0), .o_u0_entry(u0_entry), .o_hot_reset(hot_reset), .o_warm_reset(warm_reset),
        .o_configured(link_configured));

    Usb3Device #(.STREAM_FLUSH_US(1000)) u_dev (.i_clk(pclk), .i_rst(prst),
        .i_in_u0(in_u0), .i_hot_reset(hot_reset), .i_warm_reset(warm_reset),
        .i_rx_hp_valid(rx_hp_valid), .i_rx_hp_hdr(rx_hp_hdr),
        .i_dpp_start(dpp_start), .i_dpp_valid(dpp_valid), .i_dpp_data(dpp_data), .i_dpp_be(dpp_be), .i_dpp_end(dpp_end), .i_dpp_err(dpp_err),
        .o_tx_hp_valid(tx_hp_valid), .o_tx_hp_hdr(tx_hp_hdr), .o_tx_dpp(tx_dpp), .o_tx_dpp_len(tx_dpp_len), .o_tx_dpp_base(tx_dpp_base),
        .i_tx_hp_ready(tx_hp_ready), .i_dpp_rd(dpp_rd), .i_dpp_addr(dpp_addr), .o_dpp_data(dpp_rdata),
        .o_configured(dev_configured), .o_address(dev_address), .o_reset(dev_reset), .o_dbg_event(dbg_event), .o_dbg_strobe(dbg_strobe), .o_dbg_state(dbg_state),
        .o_vendor_reg(vendor_reg), .i_vendor_status({8'h55, 3'b0, ltssm_state, 7'b0, link_configured, 8'h04}),
        .o_reg_wr(reg_wr), .o_reg_addr(reg_addr), .o_reg_wdata(reg_wdata), .i_reg_rdata(reg_rdata),
        .o_rx_valid(ep_rx_valid), .o_rx_data(ep_rx_data), .i_rx_ready(1'b1),     // EP1 OUT: discarded
        .i_tx_valid(1'b0), .i_tx_data(8'h00), .o_tx_ready(ep_tx_ready),
        .i_txw_valid(la_tvalid), .i_txw_data(la_tdata), .o_txw_ready(la_tready));

    // ---------------------------------------------------------------- logic analyzer
    reg [2:0] slock_s = 3'd0;
    always @(posedge pclk) slock_s <= {slock_s[1:0], !srst};
    wire la_pwm, la_active;
    LaCore #(.FIFO_AW(11), .BLK(256), .TIMEOUT(2500)) u_la (
        .i_uclk(pclk), .i_urst(prst),
        .i_reg_wr(reg_wr), .i_reg_addr(reg_addr), .i_reg_wdata(reg_wdata), .o_reg_rdata(reg_rdata),
        .o_tvalid(la_tvalid), .o_tdata(la_tdata), .o_tlast(la_tlast), .i_tready(la_tready),
        .o_pwm(la_pwm), .o_active(la_active), .i_salive(slock_s[2]),
        .i_sclk(sclk), .i_srst(srst), .i_raw_a(raw_a), .i_raw_b(raw_b), .i_ck_a(ck_a), .i_ck_b(ck_b));
    assign vref_pwm = la_pwm;
    assign led_r = la_active;

    // ---------------------------------------------------------------- status (JTAG ER1)
    // clock checks: pclk / 16 and sclk / 16 edges per 2^22 osc
    reg [3:0] pdiv = 4'd0 /* synthesis syn_preserve=1 */, sdiv = 4'd0 /* synthesis syn_preserve=1 */;
    always @(posedge pclk) pdiv <= pdiv + 4'd1;
    always @(posedge sclk) sdiv <= sdiv + 4'd1;
    reg [2:0] pds = 3'd0, sds = 3'd0; reg [21:0] gate = 22'd0; reg [19:0] pn = 20'd0, pf = 20'd0, sn = 20'd0, sf = 20'd0;
    always @(posedge osc) begin
        pds <= {pds[1:0], pdiv[3]}; sds <= {sds[1:0], sdiv[3]}; gate <= gate + 22'd1;
        if (&gate) begin pf <= pn; pn <= 20'd0; sf <= sn; sn <= 20'd0; end
        else begin
            if (pds[1] && !pds[2]) pn <= pn + 20'd1;
            if (sds[1] && !sds[2]) sn <= sn + 20'd1;
        end
    end
    reg [15:0] cnt_u0 = 16'd0, cnt_reset = 16'd0;
    reg [31:0] cnt_words = 32'd0;
    always @(posedge pclk) begin
        if (u0_entry) cnt_u0 <= cnt_u0 + 16'd1;
        if (hot_reset || warm_reset) cnt_reset <= cnt_reset + 16'd1;
        if (la_tvalid && la_tready) cnt_words <= cnt_words + 32'd1;
    end
    // snapshot of the pclk values every 1024 pclk (stable around the JTAG capture)
    reg [9:0] snap_div = 10'd0;
    reg [95:0] snap = 96'd0;
    always @(posedge pclk) begin
        snap_div <= snap_div + 10'd1;
        if (&snap_div) snap <= {cnt_words, 6'b0, la_active, dev_configured,
                                cnt_reset, cnt_u0, 3'b0, ltssm_state, 1'b0, dev_address, in_u0, link_configured, prst, srst, s_lock, 3'b0};
    end
    // [15:0] magic 0x5B4C, [35:16] pclk / 16 per 2^22 osc, [55:36] sclk / 16 per 2^22 osc, [151:56] snapshot:
    //   [58:56] 0, [59] s_lock, [60] srst, [61] prst, [62] link configured, [63] in U0, [70:64] address,
    //   [76:72] LTSSM state, [95:80] U0 entries, [111:96] hot/warm resets, [112] device configured,
    //   [113] capturing, [151:120] stream words sent
    wire [151:0] cap = {snap, sf, pf, 16'h5B4C};
    jtag_status #(.L(152), .L2(32)) u_jtag (.tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i), .tdo_pad_o(tdo_pad_o),
        .osc(osc), .cap(cap), .cap2(32'h00005B4D), .o_w2(), .o_w2_data());
endmodule
