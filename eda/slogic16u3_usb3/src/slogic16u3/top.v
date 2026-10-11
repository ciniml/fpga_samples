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
    output wire led_r,         // G14: in U0
    output wire trace_p,       // F14 / E14 (UART TX / RX on the JTAG connector): EasyCDR trace link
    output wire trace_n        //   (TRACE=1; emulated LVDS, 1 Gb/s 8b10b, AC coupled into a Pmod EasyCDR)
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
    wire dev_configured, dev_reset, dbg_event, dbg_strobe; wire [31:0] dbg_state; wire [6:0] dev_address; wire [15:0] vendor_reg;
    wire ep_rx_valid, ep_rx_ready, ep_tx_valid, ep_tx_ready; wire [7:0] ep_rx_data, ep_tx_data;
    wire epw_valid, epw_ready; wire [31:0] epw_data;

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
        .o_vendor_reg(vendor_reg), .i_vendor_status({8'h55, 3'b0, ltssm_state, 7'b0, link_configured, 8'h03}),
        .o_rx_valid(ep_rx_valid), .o_rx_data(ep_rx_data), .i_rx_ready(ep_rx_ready),
        .i_tx_valid(ep_tx_valid), .i_tx_data(ep_tx_data), .o_tx_ready(ep_tx_ready),
        .i_txw_valid(epw_valid), .i_txw_data(epw_data), .o_txw_ready(epw_ready));
    // EP1: byte loopback, or (vendor register = 0x0001, vendor request 0x02 wValue) a PRBS15 source on
    // EP1 IN for throughput / integrity tests: x^15 + x^14 + 1, 32 bits per pclk into the 32-bit entry
    // of Usb3Device (byte 0 first, first bit in bit 0 of each byte; restarts from the all-ones state
    // when the mode is switched on; EP1 OUT is then drained and discarded). host/usb3_prbs.py checks it.
    function [14:0] prbs15_adv32(input [14:0] s);
        integer k; reg [14:0] t;
        begin
            t = s;
            for (k = 0; k < 32; k = k + 1) t = {t[13:0], t[14] ^ t[13]};
            prbs15_adv32 = t;
        end
    endfunction
    function [31:0] prbs15_word(input [14:0] s);   // the 32 bits those steps produce, first in bit 0
        integer k; reg [14:0] t; reg [31:0] b;
        begin
            t = s;
            for (k = 0; k < 32; k = k + 1) begin b[k] = t[14] ^ t[13]; t = {t[13:0], t[14] ^ t[13]}; end
            prbs15_word = b;
        end
    endfunction
    wire       prbs_mode = vendor_reg == 16'h0001;   // (exactly 1: usb_echo.py writes 0x5AA5 as a register test)
    reg        prbs_mode_d = 1'b0;
    reg [14:0] prbs_s = 15'h7FFF;
    reg [31:0] prbs_w = 32'd0;            // registered word (keeps the 32-step XOR network off the RAM write)
    always @(posedge pclk) begin
        prbs_mode_d <= prbs_mode;
        if (prbs_mode && !prbs_mode_d) begin prbs_s <= 15'h7FFF; prbs_w <= prbs15_word(15'h7FFF); end
        else if (prbs_mode && epw_ready) begin prbs_s <= prbs15_adv32(prbs_s); prbs_w <= prbs15_word(prbs15_adv32(prbs_s)); end
    end
    assign epw_valid   = prbs_mode && prbs_mode_d;   // (not in the clock that restarts it)
    assign epw_data    = prbs_w;
    assign ep_tx_valid = prbs_mode ? 1'b0 : ep_rx_valid;
    assign ep_tx_data  = ep_rx_data;
    assign ep_rx_ready = prbs_mode ? 1'b1 : ep_tx_ready;

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

    // ---------------------------------------------------------------- receive-side counters (pclk)
    // K28.5 symbols (COM), decode errors (RxStatus 4) and disparity errors (RxStatus 7). (The
    // Polling-time statistics and the Polling.Config capture that found the bring-up problems were
    // removed again: the device sits at 83 % of the CLSs and the debug logic cost pclk timing.)
    reg [15:0] cnt_com = 16'd0, cnt_dec = 16'd0, cnt_disp = 16'd0;
    wire [3:0] com_k = {rx_k[3] && rx_data[31:24] == 8'hBC, rx_k[2] && rx_data[23:16] == 8'hBC,
                        rx_k[1] && rx_data[15:8] == 8'hBC, rx_k[0] && rx_data[7:0] == 8'hBC};
    always @(posedge pclk) begin
        if (rx_valid && |com_k) cnt_com <= cnt_com + 16'd1;
        if (rx_status == 3'd4) cnt_dec <= cnt_dec + 16'd1;
        if (rx_status == 3'd7) cnt_disp <= cnt_disp + 16'd1;
    end

    // [15:0] magic, [16] ref_lock, [17] phy_resetn, [23:18] USB 2.0 pads {cdn, cdp, tdn, tdp, dxn, dxp},
    // [43:24] pclk / 16 edges per 2^22 osc, [351:44] pclk snapshot, [383:352] uptime (2^16 osc),
    // [399:384] COM count, [415:400] decode errors, [431:416] disparity errors (pclk, sampled as is)
    wire [431:0] cap = {cnt_disp, cnt_dec, cnt_com, up, snap, pf, pads_s, phy_resetn, ref_lock, 16'h5B31};
    // ---------------------------------------------------------------- packet trace (ER2)
    // 1024 pclk words of {RxStatus, RxValid, RxDataK, RxData, TxDataK, TxData} in a ring that runs
    // until a trigger, then 'post' more words and frozen; the write pointer is then the oldest entry.
    // Trigger modes (ER2 write with bit 30 = re-arm, bits 29:28 = mode; default mode 1 after reset):
    //   0: the header after the first data packet header in U0 (a SETUP's next stage), 768 after it
    //   1: U0 -> Recovery.Active, 256 after it (768 words of U0 traffic before the link dropped)
    //   2: a data packet payload with a bad CRC-32 / framing (Usb3Top o_dpp_err), 256 after it
    //   3: Usb3Device o_dbg_event (an EP1 IN ACK ignored / with Retry, a response lost), 256 after
    //      it; the header log then runs as a ring of EP1 IN headers only and stops 64 entries after it
    wire        w2; wire [30:0] w2_data;
    reg  [1:0]  tmode = 2'd1;
    reg         rearm_t = 1'b0;            // osc toggle -> pclk
    always @(posedge osc) if (w2 && w2_data[30]) begin tmode <= w2_data[29:28]; rearm_t <= ~rearm_t; end
    reg  [2:0]  rearm_s = 3'd0;
    always @(posedge pclk) rearm_s <= {rearm_s[1:0], rearm_t};
    wire        rearm = rearm_s[2] != rearm_s[1];
    reg  [1:0]  tmode_p = 2'd1;
    reg         dph_seen = 1'b0;
    reg  [4:0]  st_q = 5'd0;
    always @(posedge pclk) begin
        st_q <= ltssm_state;
        if (rearm) begin dph_seen <= 1'b0; tmode_p <= tmode; end
        else if (rx_hp_valid && rx_hp_hdr[4:0] == 5'h08) dph_seen <= 1'b1;
    end
    wire t_ev = tmode_p == 2'd0 ? (rx_hp_valid && dph_seen) :
                tmode_p == 2'd2 ? dpp_err :
                                  dbg_event;
    wire [9:0] t_post = tmode_p == 2'd0 ? 10'd767 : 10'd255;
    reg  [75:0] tbuf [0:1023];
    reg  [9:0]  twp = 10'd0, tpost = 10'd0;
    reg         ttrig = 1'b0, tfull = 1'b0;
    always @(posedge pclk) begin
        if (rearm) begin ttrig <= 1'b0; tfull <= 1'b0; tpost <= 10'd0; end
        else if (!tfull) begin
            tbuf[twp] <= {rx_status, rx_valid, rx_k, rx_data, tx_k, tx_data};
            twp <= twp + 10'd1;
            if (ttrig) begin tpost <= tpost + 10'd1; if (tpost == t_post) tfull <= 1'b1; end
            else if (t_ev) ttrig <= 1'b1;
        end
    end
    // header log: every header packet received (rx_hp_valid) or handed to the link for
    // transmission, from the first U0 entry: 128 entries of {dir (1 = tx), 24-bit pclk timestamp
    // (wraps every 134 ms), header DW2..DW0}, then frozen
    reg  [120:0] hlog [0:127];
    reg  [7:0]   hwp = 8'd0;
    reg  [23:0]  hts = 24'd0;
    reg          hrun = 1'b0, hwrap = 1'b0, htrig = 1'b0, hfrz = 1'b0;
    reg  [6:0]   hpost = 7'd0;
    wire         hring = tmode_p == 2'd3;     // ring mode: frozen 64 entries after the trigger
    // ITPs (every 125 us) are not logged; in ring mode only EP1 IN traffic (DW1 direction 1, endpoint 1)
    wire         hin_rx = rx_hp_hdr[39] && rx_hp_hdr[43:40] == 4'd1;
    wire         hin_tx = tx_hp_hdr[39] && tx_hp_hdr[43:40] == 4'd1;
    wire         hev_rx = rx_hp_valid && rx_hp_hdr[4:0] != 5'h0C && (!hring || hin_rx);
    wire         hev_tx = tx_hp_valid && tx_hp_ready && (!hring || hin_tx);
    always @(posedge pclk) begin
        hts <= hts + 24'd1;
        if (in_u0) hrun <= 1'b1;
        if (rearm) begin hwp <= 8'd0; hrun <= in_u0; hwrap <= 1'b0; htrig <= 1'b0; hfrz <= 1'b0; hpost <= 7'd0; end
        else begin
            if (hring && t_ev) htrig <= 1'b1;
            // ring mode also logs Usb3Device's EP1 IN state at every ACK it handles / packet it issues:
            // an entry of type 5'h1F with the state in DW1
            if (hrun && !hfrz && (hring || !hwp[7]) && (hev_rx || hev_tx || (hring && dbg_strobe))) begin
                hlog[hwp[6:0]] <= hev_rx ? {1'b0, hts, rx_hp_hdr} : (hring && dbg_strobe) ? {1'b1, hts, 32'd0, dbg_state, 32'h1F} :
                                  {1'b1, hts, tx_hp_hdr};
                hwp <= {1'b0, hwp[6:0] + 7'd1} | {hring ? 1'b0 : hwp[6:0] == 7'd127, 7'd0};
                if (hring && hwp[6:0] == 7'd127) hwrap <= 1'b1;
                if (hring && htrig) begin hpost <= hpost + 7'd1; if (hpost == 7'd63) hfrz <= 1'b1; end
            end
        end
    end
    reg  [10:0] tidx = 11'd0;          // [10] = 1: header log entry tidx[6:0], else trace entry
    reg  [120:0] tq = 121'd0;
    reg  [10:0] tq_idx = 11'd0;
    always @(posedge osc) begin
        if (w2 && !w2_data[30]) tidx <= w2_data[10:0];
        tq <= tidx[10] ? hlog[tidx[6:0]] : {45'd0, tbuf[tidx[9:0]]};   // static once full
        tq_idx <= tidx;
    end
    // ER2 (192 bits): [15:0] magic 0x5B33, [16] triggered, [17] full, [27:18] trace write pointer,
    // [38:28] index shown, [159:39] entry, [167:160] header log write pointer / count (128 = full),
    // [169:168] trigger mode, [170] header log wrapped (ring mode: oldest = pointer), [171] header log frozen
    wire [191:0] cap2 = {20'd0, hfrz, hwrap, tmode_p, hwp, tq, tq_idx, twp, tfull, ttrig, 16'h5B33};

    jtag_status #(.L(432), .L2(192)) u_jtag (.tck_pad_i(tck_pad_i), .tms_pad_i(tms_pad_i), .tdi_pad_i(tdi_pad_i),
        .tdo_pad_o(tdo_pad_o), .osc(osc), .cap(cap), .cap2(cap2), .o_w2(w2), .o_w2_data(w2_data));

    assign led_r = in_u0;

    // ---------------------------------------------------------------- EasyCDR trace link (TRACE=1)
    // 64 bits sampled on pclk (maps/slogic16u3_usb3.map), a timestamped record on every change, sent
    // as 1 Gb/s 8b10b over the UART pins of the JTAG connector to a Tang Primer 25K
    // (eda/easycdr_trace). No reverse control channel (one pair only): the trace always runs with
    // change detection, the descriptor goes out periodically and the 25K does the triggering.
`ifdef TRACE
    function [23:0] hsum(input [95:0] h);   // {rty, nump, seq, ept, sub, type}
        reg [31:0] dw1;
        begin
            dw1  = h[63:32];
            hsum = {dw1[6], dw1[20:16], (h[4:0] == 5'h08) ? dw1[4:0] : dw1[25:21], dw1[11:8], dw1[3:0], h[4:0]};
        end
    endfunction
    reg [23:0] rx_sum = 24'd0, tx_sum = 24'd0;
    reg        rx_ev = 1'b0, tx_ev = 1'b0, dpp_ev = 1'b0, rx_err_l = 1'b0;
    always @(posedge pclk) begin
        if (rx_hp_valid) begin rx_sum <= hsum(rx_hp_hdr); rx_ev <= ~rx_ev; end
        if (tx_hp_valid && tx_hp_ready) begin tx_sum <= hsum(tx_hp_hdr); tx_ev <= ~tx_ev; end
        if (dpp_err) dpp_ev <= ~dpp_ev;
        rx_err_l <= rx_status == 3'd4 || rx_status == 3'd7;
    end
    reg [63:0] trace_sig = 64'd0;
    always @(posedge pclk)
        trace_sig <= {1'b0, dev_configured, power_down, rx_err_l, warm_reset, hot_reset, dpp_ev,
                      tx_sum, tx_ev, rx_sum, rx_ev, in_u0, ltssm_state};

    wire tr_f500 /* synthesis syn_keep=1 */, tr_lock, tr_clk /* synthesis syn_keep=1 */;
    pll_trace500 u_pll_tr (.lock(tr_lock), .clkout0(tr_f500), .clkin(pclk));
    reg [3:0] tr_rst_sr = 4'd0;
    always @(posedge tr_f500 or negedge tr_lock)
        if (!tr_lock) tr_rst_sr <= 4'd0; else tr_rst_sr <= {tr_rst_sr[2:0], 1'b1};
    CLKDIV u_tr_div (.HCLKIN(tr_f500), .RESETN(tr_rst_sr[3]), .CALIB(1'b0), .CLKOUT(tr_clk));
    defparam u_tr_div.DIV_MODE = "5";
    reg [7:0] tr_rst_cnt = 8'd0;
    always @(posedge tr_clk or negedge tr_lock)
        if (!tr_lock) tr_rst_cnt <= 8'd0; else if (!tr_rst_cnt[7]) tr_rst_cnt <= tr_rst_cnt + 8'd1;
    wire tr_rstn = tr_rst_cnt[7];

    wire [7:0] map_addr, map_data, map_len;
    trace_map_rom u_map_rom (.addr(map_addr), .data(map_data), .len(map_len));
    wire [9:0] tr_sym;
    easycdr_trace_tx #(.WIDTH(64), .TS_BITS(24), .SYNC_STAGES(0), .FIFO_AW(6), .FIFO_RAM("block"),
                       .CFG_HASH(`TRACE_MAP_HASH)) u_trace_tx (
        .sclk(pclk), .srstn(~prst), .sig(trace_sig),
        .clk(tr_clk), .rstn(tr_rstn),
        .i_enable(1'b1), .i_ignore_mask(64'd0), .i_desc_req(1'b0),
        .i_map_req(1'b0), .i_map_len(map_len), .o_map_addr(map_addr), .i_map_data(map_data),
        .i_periodic_en(1'b0), .i_change_dis(1'b0), .i_tick_dis(1'b0), .i_period(24'd0),
        .i_arm(1'b0), .i_trig_mask(64'd0), .i_trig_value(64'd0), .i_post(16'd0),
        .o_symbol(tr_sym), .o_overflow(), .o_armed(), .o_triggered(), .o_done());
    // TRACE_INVERT: swap the line polarity (which ball of the pair is P depends on the wiring)
`ifdef TRACE_INVERT
    wire [9:0] tr_d = ~tr_sym;
`else
    wire [9:0] tr_d = tr_sym;
`endif
    wire tr_q;
    OSER10 u_tr_ser (.Q(tr_q), .D0(tr_d[0]), .D1(tr_d[1]), .D2(tr_d[2]), .D3(tr_d[3]), .D4(tr_d[4]),
        .D5(tr_d[5]), .D6(tr_d[6]), .D7(tr_d[7]), .D8(tr_d[8]), .D9(tr_d[9]),
        .PCLK(tr_clk), .FCLK(tr_f500), .RESET(~tr_rstn));
    ELVDS_OBUF u_tr_obuf (.I(tr_q), .O(trace_p), .OB(trace_n));
`else
    assign trace_p = 1'bz;   // the UART pins stay released without TRACE
    assign trace_n = 1'bz;
`endif
endmodule
