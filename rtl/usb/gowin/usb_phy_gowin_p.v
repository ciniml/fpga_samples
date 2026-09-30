// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Gowin front end for UsbPhy with synchronous clocks: the successor of
// usb_phy_gowin.v + usb_hs_os32.v (HS_OS32 = 1) without the asynchronous
// FIFOs. The oversampler front end (OSIDES32, squelch, OsCdr, BitGearbox)
// runs on PCLK = FCLK / 4 (120 MHz, CLKDIV); UsbPhy and the link (UsbDevice)
// run on FCLK / 8 (60 MHz, a second CLKDIV of the same clock, released
// together), so every PCLK edge that coincides with a 60 MHz edge is known
// (ph) and the two sides talk through plain registers: a 4-entry word buffer
// for the recovered bytes, a nibble split for the transmit words.
//
// Receive: the differential receiver goes to an OSIDES32 (4-phase FCLK
// 480 MHz, two IODELAY taps -> 8 samples per HS bit), the comparators to
// two IDES8 at 960 Msps (squelch / SE0 / FS line state). OsCdr (OSR 8)
// recovers 3..5 bits per word, BitGearbox packs bytes for UsbPhy
// (i_rx_dd_valid = 0 on a clock without one). In FS (chirp / enumeration)
// UsbPhy uses sample 0: one line sample per clock.
// Transmit: UsbPhy's 8 line bits per 60 MHz clock go out through OSER8s, 4
// per PCLK, each bit sent twice at 960 Mbps (= 480 Mbps exactly), tri-stated
// by TX0..3.
// Squelch / masking / re-acquisition / histogram: as usb_hs_os32.v.
// Pins / external parts: the TN710 USB2.0-RC circuit (see usb_phy_gowin.v).
`timescale 1ns/1ps
module usb_phy_gowin_p #(
    parameter DLY0 = 0,
    parameter DLY1 = 20    // second IODELAY tap = half the phase spacing (~260 ps)
) (
    input  wire        clk_ref_i,     // 50 MHz (reset sequencing)
    input  wire        rstn_ref_i,
    input  wire        pll_lock_i,    // 4-phase PLL lock
    input  wire        fclk0_i,       // 4-phase oversampling clocks from the PLL
    input  wire        fclk90_i,
    input  wire        fclk180_i,
    input  wire        fclk270_i,
    output wire        pclk_o,        // 120 MHz (FCLK / 4)
    output wire        clk60_o,       // 60 MHz (FCLK / 8), link clock, edges coincide with every other pclk edge
    output wire        rst60_o,       // link-domain reset: dividers not running yet
    input  wire        rst_i,         // link-domain reset for the PHY (soft reset)

    // debug (clk60 in, pclk out; quasi-static)
    input  wire        i_scan_freeze, // eye scan: freeze the CDR at class i_scan_class
    input  wire        i_scan_ofs,    // eye scan: acquire each packet at (best + i_scan_class), no tracking
    input  wire [2:0]  i_scan_class,
    input  wire        i_hist_run,    // transition histogram window: cleared on the rising edge, accumulates while high
    output wire [191:0] o_hist,       // 8 x 24-bit transitions per sample class (stable while i_hist_run is low)
    output wire [31:0] o_samples,     // raw OSIDES32 word (pclk)
    output wire [15:0] o_cmp_dbg,     // {cdp, cdn} comparator words (pclk)
    output wire        o_tx_oe,       // PHY driver enable (clk60)
    output wire [1:0]  o_mon_line,    // {D-, D+} comparator levels, one sample per clk60 (FS line state)

    // UTMI (clk60)
    input  wire [7:0]  utmi_data_out_i,
    input  wire        utmi_txvalid_i,
    output wire        utmi_txready_o,
    output wire [7:0]  utmi_data_in_o,
    output wire        utmi_rxactive_o,
    output wire        utmi_rxvalid_o,
    output wire        utmi_rxerror_o,
    output wire [1:0]  utmi_linestate_o,
    input  wire [1:0]  utmi_opmode_i,
    input  wire [1:0]  utmi_xcvrselect_i,
    input  wire        utmi_termselect_i,

    // USB2.0-RC pins (TN710)
    input  wire        usb_rx_dp_i,     // USB_RX_D+  (LVDS pair P)
    input  wire        usb_rx_dn_i,     // USB_RX_D-  (LVDS pair N)
    input  wire        usb_rxdp_p_i,    // USB_RXDP_D+ = D+
    input  wire        usb_rxdp_n_i,    // USB_RXDP_D- = VREF
    input  wire        usb_rxdn_p_i,    // USB_RXDN_D+ = D-
    input  wire        usb_rxdn_n_i,    // USB_RXDN_D- = VREF
    output wire        usb_tx_dp_o,     // USB_TX_D+
    output wire        usb_tx_dn_o,     // USB_TX_D-
    output wire        usb_pullup_en_o,
    output wire        usb_term_dp_o,
    output wire        usb_term_dn_o
);
    // ---- clocking / reset (as usb_hs_os32.v / eda/easycdr_bert oscdr_phy_gw5a.v) ----
    reg [3:0] delay_cnt;
    reg       resetn_div;
    always @(posedge clk_ref_i or negedge rstn_ref_i) begin
        if (!rstn_ref_i) begin delay_cnt <= 4'd0; resetn_div <= 1'b0; end
        else if (!pll_lock_i) begin delay_cnt <= 4'd0; resetn_div <= 1'b0; end
        else if (&delay_cnt) resetn_div <= 1'b1;
        else delay_cnt <= delay_cnt + 1'b1;
    end
    reg cen;
    always @(posedge clk_ref_i or negedge rstn_ref_i) begin
        if (!rstn_ref_i)          cen <= 1'b1;
        else if (!pll_lock_i)     cen <= 1'b1;
        else if (delay_cnt >= 4'd7) cen <= 1'b0;
    end
    wire fclkp, fclkqp, fclkn, fclkqn, pclk, clk60;
    DHCE u_dhce_0  (.CLKIN(fclk0_i),   .CEN(cen), .CLKOUT(fclkp));
    DHCE u_dhce_90 (.CLKIN(fclk90_i),  .CEN(cen), .CLKOUT(fclkqp));
    DHCE u_dhce_180(.CLKIN(fclk180_i), .CEN(cen), .CLKOUT(fclkn));
    DHCE u_dhce_270(.CLKIN(fclk270_i), .CEN(cen), .CLKOUT(fclkqn));
    // both dividers leave reset together, so their edges coincide (every clk60 edge is a pclk edge)
    CLKDIV u_clkdiv4(.HCLKIN(fclkp), .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(pclk));
    defparam u_clkdiv4.DIV_MODE = "4";
    CLKDIV u_clkdiv8(.HCLKIN(fclkp), .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(clk60));
    defparam u_clkdiv8.DIV_MODE = "8";
    assign pclk_o  = pclk;
    assign clk60_o = clk60;
    reg [2:0] rst_sync;
    always @(posedge pclk or negedge resetn_div) begin
        if (!resetn_div) rst_sync <= 3'b111; else rst_sync <= {rst_sync[1:0], 1'b0};
    end
    wire prst = rst_sync[2];
    reg [2:0] rst60_sync;
    always @(posedge clk60 or negedge resetn_div) begin
        if (!resetn_div) rst60_sync <= 3'b111; else rst60_sync <= {rst60_sync[1:0], 1'b0};
    end
    assign rst60_o = rst60_sync[2];
    reg rst_i_p; always @(posedge pclk) rst_i_p <= rst_i;   // synchronous domains: one register
    wire rst = prst | rst_i_p;

    // ---- link clock phase: ph = 1 in the pclk cycle that ends on a clk60 edge ----
    // A pclk toggle captured by clk60: both paths are full-cycle (no same-edge hold race).
    reg tp;   always @(posedge pclk)  tp   <= ~tp;
    reg tp_c; always @(posedge clk60) tp_c <= tp;
    wire ph = tp == tp_c;

    // ---- oversampling deserializer ----
    wire [31:0] samples;
    assign o_samples = samples;
    assign o_cmp_dbg = {cdp, cdn};
    wire rx_dd_ib, rx_dp_ib, rx_dn_ib;
    TLVDS_IBUF u_ibuf_dd (.I(usb_rx_dp_i),  .IB(usb_rx_dn_i),  .O(rx_dd_ib));
    TLVDS_IBUF u_ibuf_dp (.I(usb_rxdp_p_i), .IB(usb_rxdp_n_i), .O(rx_dp_ib));
    TLVDS_IBUF u_ibuf_dn (.I(usb_rxdn_p_i), .IB(usb_rxdn_n_i), .O(rx_dn_ib));
    OSIDES32 #(
        .C_STATIC_DLY_0(DLY0), .DYN_DLY_EN_0("FALSE"), .ADAPT_EN_0("FALSE"),
        .C_STATIC_DLY_1(DLY1), .DYN_DLY_EN_1("FALSE"), .ADAPT_EN_1("FALSE")
    ) u_osides32(
        .Q(samples), .DF0(), .DF1(), .D(rx_dd_ib), .PCLK(pclk),
        .FCLKP(fclkp), .FCLKQP(fclkqp), .FCLKN(fclkn), .FCLKQN(fclkqn), .RESET(prst),
        .SDTAP0(1'b0), .VALUE0(1'b0), .DLYSTEP0(8'd0), .SDTAP1(1'b0), .VALUE1(1'b0), .DLYSTEP1(8'd0));

    // ---- comparators at 960 Msps: squelch (HS) and line state / SE0 (FS) ----
    wire [7:0] cdp, cdn;
    IDES8 u_ides_dp(.D(rx_dp_ib), .FCLK(fclkp), .PCLK(pclk), .CALIB(1'b0), .RESET(prst),
        .Q0(cdp[0]), .Q1(cdp[1]), .Q2(cdp[2]), .Q3(cdp[3]), .Q4(cdp[4]), .Q5(cdp[5]), .Q6(cdp[6]), .Q7(cdp[7]));
    IDES8 u_ides_dn(.D(rx_dn_ib), .FCLK(fclkp), .PCLK(pclk), .CALIB(1'b0), .RESET(prst),
        .Q0(cdn[0]), .Q1(cdn[1]), .Q2(cdn[2]), .Q3(cdn[3]), .Q4(cdn[4]), .Q5(cdn[5]), .Q6(cdn[6]), .Q7(cdn[7]));
    // (see usb_hs_os32.v for the reasoning behind the squelch, the mask timing and the hold level)
    // (wire declarations used above: the comparator words and the transmit enable in pclk)
    reg         cmp_r, cmp_r2;
    reg  [31:0] samples_d, samples_d2;
    always @(posedge pclk) begin
        cmp_r <= |cdp | |cdn; cmp_r2 <= cmp_r;
        samples_d <= samples; samples_d2 <= samples_d;
    end
    // own transmission: the echo lags the driver enable by 6-7 words and outlasts it by ~7
    reg  [13:0] drv_sh;
    always @(posedge pclk) drv_sh <= {drv_sh[12:0], w_oe};
    wire tx_mask = |drv_sh[13:4] | w_oe;
    wire sq = ~(cmp_r | cmp_r2) | tx_mask;       // squelched: idle line or own transmission (aligned with samples_d2)
    reg  hold;
    always @(posedge pclk) if (!sq) hold <= samples_d2[31];
    wire [31:0] samples_m = sq ? {32{hold}} : samples_d2;
    wire sq_open = ~sq;                          // (capture hook)
    reg  [23:0] sq_sh;
    always @(posedge pclk) sq_sh <= {sq_sh[22:0], sq};
    wire reacq   = |sq_sh[23:12];
    wire sq_long = sq & &sq_sh[23:0];            // idle for 25 words (~210 ns)

    // ---- CDR + gearbox ----
    wire [4:0] bits; wire [3:0] nbits;
    reg [1:0] scan_fz_s, scan_ofs_s; reg [2:0] scan_cls_s;
    always @(posedge pclk) begin scan_fz_s <= {scan_fz_s[0], i_scan_freeze}; scan_ofs_s <= {scan_ofs_s[0], i_scan_ofs}; scan_cls_s <= i_scan_class; end
    wire scan_fz = scan_fz_s[1];
    wire [23:0] cdr_cnt;   // 8 classes x 3 bits (0..4 transitions per word)
    wire [2:0]  cdr_phase; wire cdr_slip, cdr_lock;
    OsCdr #(.SAMPLES(32), .OSR(8), .IIR(2), .HYST(2), .ACT_MIN(1), .DLY(9)) u_cdr(
        .i_clk(pclk), .i_rst(prst), .i_samples(samples_m), .i_freeze(scan_fz), .i_reacq(reacq & ~scan_fz),
        .i_phase_force(scan_fz), .i_phase_val(scan_cls_s), .i_phase_ofs(scan_ofs_s[1]), .o_cnt(cdr_cnt), .o_phase(cdr_phase), .o_acq(),
        .o_bits(bits), .o_nbits(nbits), .o_lock(cdr_lock), .o_slip(cdr_slip), .o_acc_first(), .o_acc_last());
    // Activity window: the gearbox is held cleared while the line is idle. The CDR keeps producing
    // (hold-level) bits in idle at exactly the rate the PHY consumes, so nothing is lost by dropping
    // them, and a packet then starts with an empty accumulator (no stale bits ahead of its SYNC).
    // The window opens with the first word carrying transitions (the SYNC; the CDR/gearbox output
    // lags the input by DLY 9 + ~5 words, so the clear ends long before the SYNC bits arrive) and
    // closes once idle has lasted 25 words, i.e. after the packet tail has left the pipeline.
    wire toggling = (samples_m != 32'h0) && (samples_m != 32'hffffffff);
    reg  act;
    always @(posedge pclk) begin
        if (prst) act <= 1'b0;
        else if (toggling) act <= 1'b1;
        else if (sq_long) act <= 1'b0;
    end
    wire       gb_valid; wire [7:0] gb_word;
    BitGearbox #(.IN_MAX(8), .OUT_W(8)) u_gb(     // IN_MAX 8: 16-bit accumulator, room for a run of 5-bit words
        .i_clk(pclk), .i_rst(prst | ~act), .i_bits({3'b0, bits}), .i_nbits(nbits), .o_valid(gb_valid), .o_word(gb_word));

    // ---- FS / LS view: one line sample per clock (sample 0), SE0 from the comparators ----
    // (SE_FROM_DIFF of usb_phy_gowin.v: J/K from the differential receiver, SE0 = both comparators
    // low by majority over 24 samples; the data is delayed two words to line up with the filter)
    function [3:0] popcnt8(input [7:0] v);
        integer k; begin popcnt8 = 0; for (k = 0; k < 8; k = k + 1) popcnt8 = popcnt8 + v[k]; end
    endfunction
    wire [7:0] se0_raw = ~cdp & ~cdn;
    // majority over 48 samples (50 ns, as the original's three 60 MHz words) surrounding the 3-word-delayed level
    reg  [3:0] se0_c [0:5];
    reg  [2:0] dd_d; wire dd_d2 = dd_d[2];
    integer si;
    always @(posedge pclk) begin
        se0_c[0] <= popcnt8(se0_raw);
        for (si = 1; si < 6; si = si + 1) se0_c[si] <= se0_c[si-1];
        dd_d <= {dd_d[1:0], samples[0]};
    end
    reg  [5:0] se0_sum;
    always @(posedge pclk) se0_sum <= se0_c[0] + se0_c[1] + se0_c[2] + se0_c[3] + se0_c[4] + se0_c[5];
    wire se0_f = se0_sum >= 6'd24;
    reg [1:0] mon_line; always @(posedge clk60) mon_line <= {cdn[0], cdp[0]};
    assign o_mon_line = mon_line;

    // ---- PHY (UsbPhy at clk60, 8 line bits per clock) ----
    // The bit-level PHY (NRZI / stuffing / SYNC / EOP, UsbPhyRx + UsbPhyTx) does not close timing at
    // 120 MHz with 4 bits per clock on the GW5A (both the decoder and the stuffer miss by 1-2 ns, and
    // the SIE's byte mux in front of the transmitter by more), so it stays at 60 MHz with 8 bits per
    // clock. The two domains are synchronous: the recovered bytes go through a 4-entry buffer whose
    // read side presents one word per clk60 edge, the transmit words are split into nibbles in pclk.
    // Every register that faces clk60 is updated at the end of a ph = 0 cycle (E + T), i.e. a full
    // pclk period before the clk60 edge E' that samples it; clk60 registers are sampled in pclk at
    // the end of ph = 0 cycles (E + T), a full pclk period after they changed at E.
    //
    // Receive word buffer: the CDR yields exactly 4 bits per pclk on average (frequency-locked
    // clocks), i.e. one byte per clk60, with a jitter of +/- one word (3..5 bits per word, phase
    // wander within a packet); the buffer only absorbs that jitter. It is held cleared while the line
    // is idle (act = 0): the idle (hold-level) bits are not needed, and a packet then starts with an
    // empty buffer. A read slot with no word gives i_rx_dd_valid = 0 (the PHY just waits).
    reg  [7:0] rmem [0:3];
    reg  [2:0] rwp, rrp;
    reg  [7:0] l_word; reg l_valid, l_act, l_dd, l_se0;
    wire       r_empty = rwp == rrp;
    always @(posedge pclk) begin
        if (prst | ~act) begin rwp <= 3'd0; rrp <= 3'd0; end
        else begin
            if (gb_valid) begin rmem[rwp[1:0]] <= gb_word; rwp <= rwp + 1'b1; end
            if (!ph) begin
                if (!r_empty) begin l_word <= rmem[rrp[1:0]]; rrp <= rrp + 1'b1; end
            end
        end
        if (!ph) begin l_valid <= act && !r_empty; l_act <= act; l_dd <= dd_d2; l_se0 <= se0_f; end
    end
    // (SE_FROM_DIFF of usb_phy_gowin.v: J/K from the differential receiver, SE0 from the comparators;
    // in HS the line state is SE0 while idle, else the last recovered level)
    wire       hs_sel = (utmi_xcvrselect_i == 2'b00) && !utmi_termselect_i;
    // The pclk registers above are launched at E + T and sampled at the clk60 edge E'; the two CLKDIVs
    // can leave reset one FCLK apart (2 ns) and the placement adds skew, so the crossing must stay a
    // plain register-to-register path: the mux below is quasi-static (hs_sel) and its result is
    // re-registered in clk60 before any PHY logic sees it (one clk60 of extra receive latency).
    wire [7:0] m_dd = hs_sel ? l_word : {8{l_dd}};
    wire       m_dd_valid = hs_sel ? l_valid : 1'b1;
    wire [7:0] m_dp = hs_sel ? ( l_word & {8{l_act}}) : {8{ l_dd & ~l_se0}};
    wire [7:0] m_dn = hs_sel ? (~l_word & {8{l_act}}) : {8{~l_dd & ~l_se0}};
    reg  [7:0] rx_dd, rx_dp, rx_dn; reg rx_dd_valid;
    always @(posedge clk60) begin rx_dd <= m_dd; rx_dd_valid <= m_dd_valid; rx_dp <= m_dp; rx_dn <= m_dn; end
    wire [7:0] tx_dp8, tx_dn8; wire tx_oe;
    wire       pullup_dp_en, pullup_dn_en, term_dp_en, term_dn_en;
    reg        rst60_l; always @(posedge clk60) rst60_l <= rst60_o | rst_i;
    assign o_tx_oe = tx_oe;
    UsbPhy #(.W(8), .FS_CLOCKS_PER_BIT(5), .LS_CLOCKS_PER_BIT(40)) u_phy (
        .i_clk            (clk60),
        .i_rst            (rst60_l),
        .i_utmi_data_out  (utmi_data_out_i),
        .i_utmi_txvalid   (utmi_txvalid_i),
        .o_utmi_txready   (utmi_txready_o),
        .o_utmi_data_in   (utmi_data_in_o),
        .o_utmi_rxactive  (utmi_rxactive_o),
        .o_utmi_rxvalid   (utmi_rxvalid_o),
        .o_utmi_rxerror   (utmi_rxerror_o),
        .o_utmi_linestate (utmi_linestate_o),
        .i_utmi_opmode    (utmi_opmode_i),
        .i_utmi_xcvrselect(utmi_xcvrselect_i),
        .i_utmi_termselect(utmi_termselect_i),
        .i_rx_dp          (rx_dp),
        .i_rx_dn          (rx_dn),
        .i_rx_dd          (rx_dd),
        .i_rx_dd_valid    (rx_dd_valid),
        .o_tx_dp          (tx_dp8),
        .o_tx_dn          (tx_dn8),
        .o_tx_oe          (tx_oe),
        .o_pullup_dp_en   (pullup_dp_en),
        .o_pullup_dn_en   (pullup_dn_en),
        .o_term_dp_en     (term_dp_en),
        .o_term_dn_en     (term_dn_en)
    );
    // transmit word (launched on a clk60 edge E) -> pclk register at E + T -> nibble 0 in the cycle
    // ending at E + 2T, nibble 1 in the one after; each bit goes out twice at 960 Mbps
    // (the PHY's line outputs are re-registered in clk60 first, so the crossing into pclk is
    // register-to-register as well; one clk60 of extra transmit latency)
    reg [7:0] t_dp8, t_dn8; reg t_oe;
    always @(posedge clk60) begin t_dp8 <= tx_dp8; t_dn8 <= tx_dn8; t_oe <= tx_oe; end
    reg [7:0] w_dp, w_dn; reg w_oe;
    always @(posedge pclk) if (!ph) begin w_dp <= t_dp8; w_dn <= t_dn8; w_oe <= t_oe; end
    wire [3:0] tx_dp = ph ? w_dp[3:0] : w_dp[7:4];
    wire [3:0] tx_dn = ph ? w_dn[3:0] : w_dn[7:4];
    wire       tx_oen = ~w_oe;

    // ---- transition histogram (eye diagram of the edges, 1/8 UI bins; see usb_hs_os32.v) ----
    reg [2:0]  hist_s; always @(posedge pclk) hist_s <= {hist_s[1:0], i_hist_run};
    reg        hist_acq;
    always @(posedge pclk) if (sq) hist_acq <= 1'b0; else if (cdr_slip) hist_acq <= 1'b1;
    reg [23:0] cnt_d [0:3]; reg [3:0] drv_d; reg [2:0] ph_d [0:3];
    integer di;
    always @(posedge pclk) begin
        cnt_d[0] <= cdr_cnt; ph_d[0] <= cdr_phase; drv_d <= {drv_d[2:0], cmp_r2 & ~sq & hist_acq};
        for (di = 1; di < 4; di = di + 1) begin cnt_d[di] <= cnt_d[di-1]; ph_d[di] <= ph_d[di-1]; end
    end
    wire        hist_ok = &drv_d && (cmp_r2 & ~sq);
    wire [23:0] hist_cnt = cnt_d[3];
    wire [2:0]  hist_ph  = ph_d[3];
    reg [23:0] hist [0:7];
    genvar hc;
    generate for (hc = 0; hc < 8; hc = hc + 1) begin : g_hist
        wire [2:0] src = hc + hist_ph;
        always @(posedge pclk) begin
            if (hist_s[1] & ~hist_s[2]) hist[hc] <= 24'd0;
            else if (hist_s[2] && hist_ok) hist[hc] <= hist[hc] + hist_cnt[src*3 +: 3];
        end
        assign o_hist[hc*24 +: 24] = hist[hc];
    end endgenerate

    // ---- serializers: 4 line bits per pclk, each sent twice at 960 Mbps ----
    wire tx_dp_q, tx_dn_q, tx_dp_oen, tx_dn_oen;
    OSER8 u_oser_dp(
        .D0(tx_dp[0]), .D1(tx_dp[0]), .D2(tx_dp[1]), .D3(tx_dp[1]), .D4(tx_dp[2]), .D5(tx_dp[2]), .D6(tx_dp[3]), .D7(tx_dp[3]),
        .TX0(tx_oen), .TX1(tx_oen), .TX2(tx_oen), .TX3(tx_oen), .FCLK(fclkp), .PCLK(pclk), .RESET(prst),
        .Q0(tx_dp_q), .Q1(tx_dp_oen));
    OSER8 u_oser_dn(
        .D0(tx_dn[0]), .D1(tx_dn[0]), .D2(tx_dn[1]), .D3(tx_dn[1]), .D4(tx_dn[2]), .D5(tx_dn[2]), .D6(tx_dn[3]), .D7(tx_dn[3]),
        .TX0(tx_oen), .TX1(tx_oen), .TX2(tx_oen), .TX3(tx_oen), .FCLK(fclkp), .PCLK(pclk), .RESET(prst),
        .Q0(tx_dn_q), .Q1(tx_dn_oen));
    TBUF u_tbuf_dp (.I(tx_dp_q), .OEN(tx_dp_oen), .O(usb_tx_dp_o));
    TBUF u_tbuf_dn (.I(tx_dn_q), .OEN(tx_dn_oen), .O(usb_tx_dn_o));

    // ---- terminations / pull-up (external R1..R3, TN710) ----
    assign usb_pullup_en_o = pullup_dp_en;
    assign usb_term_dp_o   = term_dp_en ? 1'b0 : 1'bz;
    assign usb_term_dn_o   = term_dn_en ? 1'b0 : 1'bz;
endmodule
