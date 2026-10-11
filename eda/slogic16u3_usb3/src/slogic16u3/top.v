// USB 3.0 (SuperSpeed) device on the Sipeed SLogic16U3 (GW5AT-15): Gowin USB 3.0 PHY IP + rtl/usb3.
//
//   D14 high -> 125 MHz oscillator on Q0 REFCLK0 -> USB 3.0 PHY (GUI, src/slogic16u3/usb3_ln0: Q0 lane 0,
//   QPLL0, 5 Gb/s, PIPE 32 bits / pclk 125 MHz) -> Usb3Top (LTSSM / link) + Usb3Device (EP1 loopback)
//   internal oscillator ~51.66 MHz -> pll_ref125 -> the PHY's ref_clk (its reset / register logic)
//
// The receive pair of lane 0 is the one the VL162 Type-C mux feeds (LFPS seen there in both plug
// orientations, top_lanes.v); the transmit pair is assumed to be lane 0 as well.
// The USB 2.0 pins are kept quiet and observed: the comparator pairs and the dx / term balls are
// inputs without pull-ups (left undeclared they get the default weak pull-up and the host sees a
// low-speed device), the D+ pull-up (C14) is off: SuperSpeed only.
//
// Status over JTAG: ER1 (IR 0x42) read-only, 384 bits (jtag_status.v, host/usb3_status.py).
module top (
    input  wire tck_pad_i,
    input  wire tms_pad_i,
    input  wire tdi_pad_i,
    output wire tdo_pad_o,

    input  wire usb_cmp_dp,    // H3 / H2: D+ against VREF
    input  wire usb_cmp_dp_n,
    input  wire usb_cmp_dn,    // M2 / M1: D- against VREF
    input  wire usb_cmp_dn_n,
    input  wire usb_dxp,       // K3, K2, P2, P1: USB 2.0 dx / term balls (inputs, no pull)
    input  wire usb_dxn,
    input  wire usb_tdp,
    input  wire usb_tdn,
    output wire usb_pullup,    // C14 (off)
    output wire xo_en,         // D14: 125 MHz oscillator enable
    output wire led_r          // G14: in U0
);
    wire osc;   // ~51.7 MHz (measured)
    OSCA #(.FREQ_DIV(4)) u_osc (.OSCOUT(osc), .OSCEN(1'b1));
    assign xo_en = 1'b1;
    assign usb_pullup = 1'b0;
    wire cmp_dp, cmp_dn;
    TLVDS_IBUF u_cmp_dp (.I(usb_cmp_dp), .IB(usb_cmp_dp_n), .O(cmp_dp));
    TLVDS_IBUF u_cmp_dn (.I(usb_cmp_dn), .IB(usb_cmp_dn_n), .O(cmp_dn));

    // ---------------------------------------------------------------- ref_clk, PHY reset
    // ~20 ms after configuration the PLL leaves reset (the 125 MHz oscillator settles meanwhile);
    // phy_resetn ~1 ms after its lock (as the Console design)
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

    // ---------------------------------------------------------------- link + protocol
    wire rx_hp_valid; wire [95:0] rx_hp_hdr;
    wire dpp_start, dpp_valid, dpp_end, dpp_err; wire [31:0] dpp_data; wire [3:0] dpp_be;
    wire tx_hp_valid, tx_dpp, tx_hp_ready, tx_hp_idle; wire [95:0] tx_hp_hdr; wire [10:0] tx_dpp_len; wire [11:0] tx_dpp_base;
    wire dpp_rd; wire [11:0] dpp_addr; wire [31:0] dpp_rdata;
    wire [4:0] ltssm_state; wire in_u0, u0_entry, hot_reset, warm_reset, link_configured;
    wire dev_configured, dev_reset; wire [6:0] dev_address; wire [15:0] vendor_reg;
    wire ep_rx_valid, ep_rx_ready, ep_tx_valid, ep_tx_ready; wire [7:0] ep_rx_data, ep_tx_data;

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
        .o_configured(dev_configured), .o_address(dev_address), .o_reset(dev_reset),
        .o_vendor_reg(vendor_reg), .i_vendor_status({8'h55, 3'b0, ltssm_state, 7'b0, link_configured, 8'h03}),
        .o_rx_valid(ep_rx_valid), .o_rx_data(ep_rx_data), .i_rx_ready(ep_rx_ready),
        .i_tx_valid(ep_tx_valid), .i_tx_data(ep_tx_data), .o_tx_ready(ep_tx_ready));
    // EP1 byte loopback
    assign ep_tx_valid = ep_rx_valid;
    assign ep_tx_data  = ep_rx_data;
    assign ep_rx_ready = ep_tx_ready;

    // ---------------------------------------------------------------- statistics (pclk)
    reg [15:0] cnt_u0 = 16'd0, cnt_hp = 16'd0, cnt_reset = 16'd0, cnt_dpp_err = 16'd0, cnt_physt = 16'd0;
    reg [31:0] cnt_bytes = 32'd0;
    reg [4:0]  st_max = 5'd0, st_d = 5'd0;
    reg [31:0] st_seen = 32'd0;
    reg [79:0] st_trace = 80'd0;    // last 16 LTSSM states entered, newest in [4:0]
    reg [7:0]  cnt_trans = 8'd0;
    reg        elec_d = 1'b1;
    reg [15:0] cnt_lfps = 16'd0;    // RxElecIdle falling edges (LFPS bursts / data start)
    always @(posedge pclk) begin
        if (u0_entry) cnt_u0 <= cnt_u0 + 16'd1;
        if (rx_hp_valid) cnt_hp <= cnt_hp + 16'd1;
        if (hot_reset || warm_reset) cnt_reset <= cnt_reset + 16'd1;
        if (dpp_end && dpp_err) cnt_dpp_err <= cnt_dpp_err + 16'd1;
        if (phy_status) cnt_physt <= cnt_physt + 16'd1;
        if (ep_rx_valid && ep_rx_ready) cnt_bytes <= cnt_bytes + 32'd1;
        if (ltssm_state > st_max) st_max <= ltssm_state;
        st_seen[ltssm_state] <= 1'b1;
        st_d <= ltssm_state;
        if (ltssm_state != st_d) begin st_trace <= {st_trace[74:0], ltssm_state}; cnt_trans <= cnt_trans + 8'd1; end
        elec_d <= rx_elecidle;
        if (elec_d && !rx_elecidle) cnt_lfps <= cnt_lfps + 16'd1;
    end

    // snapshot for the status register: refreshed every 1024 pclk, so the JTAG side (osc) sees a
    // value that stays put for ~8 us around its capture
    reg [9:0]  snap_div = 10'd0;
    // (bit positions below are those of the status register: live[0] lands on bit 44)
    reg [307:0] snap = 308'd0;
    wire [307:0] live = {
        cnt_bytes,                                              // [351:320]
        st_trace,                                               // [319:240]
        st_seen,                                                // [239:208]
        cnt_lfps, cnt_physt, cnt_dpp_err, cnt_reset, cnt_hp, cnt_u0, // [207:112]
        vendor_reg,                                             // [111:96]
        cnt_trans,                                              // [95:88]
        1'b0, dev_address,                                      // [87:80]
        2'b0, power_present, rx_elecidle, phy_status, rx_status, // [79:72]
        3'b0, st_max,                                           // [71:64]
        3'b0, ltssm_state,                                      // [63:56]
        1'b0, power_down, tx_elecidle, tx_detectrx, rx_termination, rx_polarity, rx_valid, // [55:48]
        dev_configured, link_configured, in_u0, prst};          // [47:44]
    always @(posedge pclk) begin snap_div <= snap_div + 10'd1; if (&snap_div) snap <= live; end

    // pclk frequency: pclk / 16 edges per 2^22 osc cycles
    reg [3:0] pdiv = 4'd0 /* synthesis syn_preserve=1 */;
    always @(posedge pclk) pdiv <= pdiv + 4'd1;
    reg [2:0] pds = 3'd0; reg [21:0] gate = 22'd0; reg [19:0] pn = 20'd0, pf = 20'd0;
    always @(posedge osc) begin
        pds <= {pds[1:0], pdiv[3]}; gate <= gate + 22'd1;
        if (&gate) begin pf <= pn; pn <= 20'd0; end
        else if (pds[1] && !pds[2]) pn <= pn + 20'd1;
    end
    reg [31:0] up = 32'd0; reg [15:0] upl = 16'd0;
    always @(posedge osc) begin upl <= upl + 16'd1; if (&upl) up <= up + 32'd1; end
    reg [5:0] pads_s = 6'd0;
    always @(posedge osc) pads_s <= {cmp_dn, cmp_dp, usb_tdn, usb_tdp, usb_dxn, usb_dxp};

    // ---------------------------------------------------------------- receive-side debug (pclk)
    // counters: K28.5 symbols (COM), decode errors (RxStatus 4) and disparity errors (RxStatus 7);
    // capture: 64 PIPE receive words {RxStatus, RxValid, RxDataK, RxData} around the first TS2 seen
    // in Polling.Config (8 before, 56 from it), then frozen; entry cwp is the oldest. The JTAG side shows entry up[5:0] (rotates every
    // ~1.3 ms), so the host assembles the buffer from repeated reads.
    reg [15:0] cnt_com = 16'd0, cnt_dec = 16'd0, cnt_disp = 16'd0;
    reg [39:0] cbuf [0:63];
    reg [6:0]  cwp = 7'd0;
    reg [8:0]  cdly = 9'd0;
    reg        cfull = 1'b0, carm = 1'b0, ctrig = 1'b0;
    reg [5:0]  cpost = 6'd0;
    wire [3:0] com_k = {rx_k[3] && rx_data[31:24] == 8'hBC, rx_k[2] && rx_data[23:16] == 8'hBC,
                        rx_k[1] && rx_data[15:8] == 8'hBC, rx_k[0] && rx_data[7:0] == 8'hBC};
    always @(posedge pclk) begin
        if (rx_valid && |com_k) cnt_com <= cnt_com + 16'd1;
        if (rx_status == 3'd4) cnt_dec <= cnt_dec + 16'd1;
        if (rx_status == 3'd7) cnt_disp <= cnt_disp + 16'd1;
        // ring buffer while in Polling.Config, stopped 56 words after the first TS2 body word
        // (D5.2 x 4), so it holds 8 words before it; cwp then points at the oldest entry
        if (ltssm_state == 5'd9) carm <= 1'b1;
        if (carm && !cfull) begin
            cbuf[cwp[5:0]] <= {rx_status, rx_valid, rx_k, rx_data};
            cwp <= {1'b0, cwp[5:0] + 6'd1};
            if (ctrig) begin cpost <= cpost + 6'd1; if (cpost == 6'd55) cfull <= 1'b1; end
            else if (rx_valid && rx_k == 4'd0 && rx_data == 32'h45454545) ctrig <= 1'b1;
        end
    end
    // per-state receive statistics for Polling.RxEQ (7) and Polling.Active (8), accumulated over all
    // visits: {COM words, RxElecIdle cycles, RxValid cycles, cycles}, 24 bits each
    reg [23:0] ps_cnt [0:7];
    integer pi;
    initial for (pi = 0; pi < 8; pi = pi + 1) ps_cnt[pi] = 24'd0;
    wire       ps_in  = ltssm_state == 5'd7 || ltssm_state == 5'd8;
    wire [2:0] ps_b   = {ltssm_state == 5'd8, 2'b00};
    always @(posedge pclk) if (ps_in) begin
        ps_cnt[ps_b + 3'd0] <= ps_cnt[ps_b + 3'd0] + 24'd1;
        if (rx_valid)              ps_cnt[ps_b + 3'd1] <= ps_cnt[ps_b + 3'd1] + 24'd1;
        if (rx_elecidle)           ps_cnt[ps_b + 3'd2] <= ps_cnt[ps_b + 3'd2] + 24'd1;
        if (rx_valid && |com_k)    ps_cnt[ps_b + 3'd3] <= ps_cnt[ps_b + 3'd3] + 24'd1;
    end
    reg [39:0] cbuf_q; reg [5:0] cidx;
    always @(posedge osc) begin cbuf_q <= cbuf[up[5:0]]; cidx <= up[5:0]; end   // static once cfull

    // [15:0] magic, [16] ref_lock, [17] phy_resetn, [23:18] USB 2.0 pads {cdn, cdp, tdn, tdp, dxn, dxp},
    // [43:24] pclk / 16 edges per 2^22 osc, [383:352] uptime (2^16 osc),
    // [423:384] capture entry, [429:424] its index, [430] capture full, [447:432] COM count,
    // [463:448] decode errors, [479:464] disparity errors
    // [671:480] per-state statistics ps_cnt[0..7] (24 bits each, pclk, sampled as is)
    wire [671:480] cap_ps = {ps_cnt[7], ps_cnt[6], ps_cnt[5], ps_cnt[4], ps_cnt[3], ps_cnt[2], ps_cnt[1], ps_cnt[0]};
    // [679:674] cwp (oldest capture entry)
    wire [679:0] cap = {2'b0, cwp[5:0], cap_ps, cnt_disp, cnt_dec, cnt_com, 1'b0, cfull, cidx, cbuf_q,
                        up, snap, pf, pads_s, phy_resetn, ref_lock, 16'h5B31};
    // ---------------------------------------------------------------- U0 packet trace (ER2)
    // 1024 pclk words of {RxStatus, RxValid, RxDataK, RxData, TxDataK, TxData} around the first data
    // packet header received in U0 (a SETUP), or the header after it (TRACE_AFTER_DPH): 256 before
    // it, 768 from it, then frozen. Read through
    // ER2: a scan writing bit L2-1 = 1 and the index in bits L2-32 +: 11 (jtag_status o_w2_data)
    // selects an entry, the next scan returns it (layout below).
    // TRACE_AFTER_DPH: trigger on the first header after it instead (the SETUP's STATUS stage)
    localparam TRACE_AFTER_DPH = 1;
    reg  dph_seen = 1'b0;
    always @(posedge pclk) if (rx_hp_valid && rx_hp_hdr[4:0] == 5'h08) dph_seen <= 1'b1;
    wire is_dph = rx_hp_valid && (TRACE_AFTER_DPH ? dph_seen : rx_hp_hdr[4:0] == 5'h08);
    reg  [75:0] tbuf [0:1023];
    reg  [9:0]  twp = 10'd0, tpost = 10'd0;
    reg         ttrig = 1'b0, tfull = 1'b0;
    always @(posedge pclk) begin
        if (!tfull && (in_u0 || ttrig)) begin
            tbuf[twp] <= {rx_status, rx_valid, rx_k, rx_data, tx_k, tx_data};
            twp <= twp + 10'd1;
            if (ttrig) begin tpost <= tpost + 10'd1; if (tpost == 10'd767) tfull <= 1'b1; end
            else if (is_dph) ttrig <= 1'b1;
        end
    end
    // header log: every header packet received (rx_hp_valid) or handed to the link for
    // transmission, from the first U0 entry: 128 entries of {dir (1 = tx), 24-bit pclk timestamp
    // (wraps every 134 ms), header DW2..DW0}, then frozen
    reg  [120:0] hlog [0:127];
    reg  [7:0]   hwp = 8'd0;
    reg  [23:0]  hts = 24'd0;
    reg          hrun = 1'b0;
    always @(posedge pclk) begin
        hts <= hts + 24'd1;
        if (in_u0) hrun <= 1'b1;
        if (hrun && !hwp[7]) begin
            if (rx_hp_valid && rx_hp_hdr[4:0] != 5'h0C) begin hlog[hwp[6:0]] <= {1'b0, hts, rx_hp_hdr}; hwp <= hwp + 8'd1; end   // ITPs (every 125 us) not logged
            else if (tx_hp_valid && tx_hp_ready) begin hlog[hwp[6:0]] <= {1'b1, hts, tx_hp_hdr}; hwp <= hwp + 8'd1; end
        end
    end
    wire        w2; wire [30:0] w2_data;
    reg  [10:0] tidx = 11'd0;          // [10] = 1: header log entry tidx[6:0], else trace entry
    reg  [120:0] tq = 121'd0;
    reg  [10:0] tq_idx = 11'd0;
    always @(posedge osc) begin
        if (w2) tidx <= w2_data[10:0];
        tq <= tidx[10] ? hlog[tidx[6:0]] : {45'd0, tbuf[tidx[9:0]]};   // static once full
        tq_idx <= tidx;
    end
    // ER2 (192 bits): [15:0] magic 0x5B33, [16] triggered, [17] full, [27:18] trace write pointer,
    // [38:28] index shown, [159:39] entry, [167:160] header log count (128 = full)
    wire [191:0] cap2 = {24'd0, hwp, tq, tq_idx, twp, tfull, ttrig, 16'h5B33};

    jtag_status #(.L(680), .L2(192)) u_jtag (.tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i),
        .tdo_pad_o(tdo_pad_o), .osc(osc), .cap(cap), .cap2(cap2), .o_w2(w2), .o_w2_data(w2_data));

    assign led_r = in_u0;
endmodule
