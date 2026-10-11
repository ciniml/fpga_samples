// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// usb_phy_gowin_sl: UsbPhy front end for boards wired in Gowin's USB 2.0 SoftPHY "Single LVDS"
// arrangement (IPUG781, e.g. the Sipeed SLogic16U3): one bidirectional pair (dxp/dxn) carries both
// the transmitter and the differential receiver, two comparator pairs (D+ / VREF, D- / VREF) and
// two termination pins (term_dp / term_dn, drive low = HS termination). The dx pair is an
// emulated-differential IOBUF (LVCMOS33D): it can only drive J or K, so SE0 is made by tri-stating
// it and pulling both lines low through the termination pins (FS EOP; in HS the lines rest at SE0
// on the terminations anyway). Derived from usb_phy_gowin_p.v (synchronous clocks, no FIFOs).
//
// OSIDES32 needs its D straight from an input buffer (CK3001), so the receiver behind the IOBUF
// is an IDES16 instead, run at twice Gowin's FCLK: FCLK 960 MHz (DDR) = 1.92 Gsps, 4 samples per
// HS bit, PCLK = FCLK / 8 = 120 MHz (CLKDIV). The link clock clk60 is a CLKDIV /8 of a 480 MHz
// output of the same PLL VCO, released together with the PCLK divider, so every clk60 edge is a
// pclk edge (ph) and the two sides talk through plain registers: a 4-entry word buffer for the
// recovered bytes, a nibble split for the transmit words.
//
// Receive: IDES16 on the dx pair's receiver (16 samples per pclk, Q0 earliest), the comparators to
// two IDES16 as well (squelch / SE0 / FS line state). OsCdr (OSR 4) recovers 3..5 bits per word,
// BitGearbox packs bytes for UsbPhy (i_rx_dd_valid = 0 on a clock without one). In FS (chirp /
// enumeration) UsbPhy uses sample 0: one line sample per clock.
// Transmit: UsbPhy's 8 line bits per 60 MHz clock go out through an OSER16 at 1.92 Gbps, 4 per
// pclk, each bit sent 4 times. OSER16 has no tri-state control: the IOBUF's OEN comes from a pclk
// register delayed to line up with the serialiser (data appears ~1.9 pclk after the OSER16 captures
// it, prim_sim) and stretched by one word at either end; the data is held at the last line bit while
// the driver is off, so the stretch (and any misalignment) only lengthens the first / last level.
`timescale 1ns/1ps
module usb_phy_gowin_sl #(
    parameter OE_DLY = 2    // driver enable delay (pclk) behind the word handed to the OSER16 (>= 2)
) (
    input  wire        clk_ref_i,     // 50 MHz (reset sequencing)
    input  wire        rstn_ref_i,
    input  wire        pll_lock_i,    // PLL lock
    input  wire        fclk_i,        // 960 MHz (IDES16 / OSER16 FCLK)
    input  wire        fclk480_i,     // 480 MHz, same VCO (clk60 divider)
    output wire        pclk_o,        // 120 MHz (fclk / 8)
    output wire        clk60_o,       // 60 MHz (fclk480 / 8), link clock, edges coincide with every other pclk edge
    output wire        rst60_o,       // link-domain reset: dividers not running yet
    input  wire        rst_i,         // link-domain reset for the PHY (soft reset)

    // debug (clk60 in, pclk out; quasi-static)
    input  wire        i_scan_freeze, // eye scan: freeze the CDR at class i_scan_class
    input  wire        i_scan_ofs,    // eye scan: acquire each packet at (best + i_scan_class), no tracking
    input  wire [1:0]  i_scan_class,
    input  wire        i_hist_run,    // transition histogram window: cleared on the rising edge, accumulates while high
    output wire [95:0] o_hist,        // 4 x 24-bit transitions per sample class (stable while i_hist_run is low)
    output wire [15:0] o_samples,     // raw IDES16 word (pclk)
    output wire [31:0] o_cmp_dbg,     // {cdp, cdn} comparator words (pclk)
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

    // Single LVDS pins (IPUG781)
    inout  wire        usb_dxp_io,      // dx pair, D+ side (LVCMOS33D bidirectional)
    inout  wire        usb_dxn_io,      // dx pair, D- side
    input  wire        usb_rxdp_p_i,    // D+   (comparator pair P)
    input  wire        usb_rxdp_n_i,    // VREF (comparator pair N)
    input  wire        usb_rxdn_p_i,    // D-
    input  wire        usb_rxdn_n_i,    // VREF
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
    wire fclk, fclk480, pclk, clk60;
    DHCE u_dhce    (.CLKIN(fclk_i),    .CEN(cen), .CLKOUT(fclk));
    DHCE u_dhce_480(.CLKIN(fclk480_i), .CEN(cen), .CLKOUT(fclk480));
    // both dividers leave reset together, so their edges coincide (every clk60 edge is a pclk edge)
    CLKDIV u_clkdiv_p (.HCLKIN(fclk),    .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(pclk));
    defparam u_clkdiv_p.DIV_MODE = "8";
    CLKDIV u_clkdiv_60(.HCLKIN(fclk480), .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(clk60));
    defparam u_clkdiv_60.DIV_MODE = "8";
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
    // The two dividers run from different FCLKs (960 / 480 MHz) and can start one 960 MHz period
    // apart, so a clk60 edge may lag "its" pclk edge by ~1 ns: a pclk toggle sampled by clk60 (as
    // usb_phy_gowin_p.v does) is then a same-edge hold race and ph came up inverted on some loads
    // (no HS reception at all). Instead a clk60 toggle is sampled on the pclk falling edge, half a
    // period away from any clk60 edge: it changes in the half cycle after a clk60 edge E, the next
    // pclk rising edge E + T takes it, so the change is seen during [E + T, E + 2T], the cycle that
    // ends on the next clk60 edge.
    reg t60;  always @(posedge clk60) t60 <= ~t60;
    reg t60_n; always @(negedge pclk) t60_n <= t60;
    reg t60_p, t60_p2;
    always @(posedge pclk) begin t60_p <= t60_n; t60_p2 <= t60_p; end
    wire ph = t60_p != t60_p2;

    // ---- oversampling deserializers (1.92 Gsps, Q0 earliest) ----
    wire [15:0] samples, cdp, cdn;
    assign o_samples = samples;
    assign o_cmp_dbg = {cdp, cdn};
    wire rx_dd_ib, rx_dp_ib, rx_dn_ib;
    // the dx pair: OSER16 (D+ level) into an emulated-differential IOBUF whose differential
    // receiver feeds an IDES16; the comparators through true-LVDS input buffers
    wire tx_dx_q; reg tx_dx_oen = 1'b1;
    ELVDS_IOBUF u_iobuf_dx (.O(rx_dd_ib), .IO(usb_dxp_io), .IOB(usb_dxn_io), .I(tx_dx_q), .OEN(tx_dx_oen));
    TLVDS_IBUF u_ibuf_dp (.I(usb_rxdp_p_i), .IB(usb_rxdp_n_i), .O(rx_dp_ib));
    TLVDS_IBUF u_ibuf_dn (.I(usb_rxdn_p_i), .IB(usb_rxdn_n_i), .O(rx_dn_ib));
    IDES16 u_ides_dx(.D(rx_dd_ib), .FCLK(fclk), .PCLK(pclk), .CALIB(1'b0), .RESET(prst),
        .Q0(samples[0]), .Q1(samples[1]), .Q2(samples[2]), .Q3(samples[3]), .Q4(samples[4]), .Q5(samples[5]),
        .Q6(samples[6]), .Q7(samples[7]), .Q8(samples[8]), .Q9(samples[9]), .Q10(samples[10]), .Q11(samples[11]),
        .Q12(samples[12]), .Q13(samples[13]), .Q14(samples[14]), .Q15(samples[15]));
    IDES16 u_ides_dp(.D(rx_dp_ib), .FCLK(fclk), .PCLK(pclk), .CALIB(1'b0), .RESET(prst),
        .Q0(cdp[0]), .Q1(cdp[1]), .Q2(cdp[2]), .Q3(cdp[3]), .Q4(cdp[4]), .Q5(cdp[5]), .Q6(cdp[6]), .Q7(cdp[7]),
        .Q8(cdp[8]), .Q9(cdp[9]), .Q10(cdp[10]), .Q11(cdp[11]), .Q12(cdp[12]), .Q13(cdp[13]), .Q14(cdp[14]), .Q15(cdp[15]));
    IDES16 u_ides_dn(.D(rx_dn_ib), .FCLK(fclk), .PCLK(pclk), .CALIB(1'b0), .RESET(prst),
        .Q0(cdn[0]), .Q1(cdn[1]), .Q2(cdn[2]), .Q3(cdn[3]), .Q4(cdn[4]), .Q5(cdn[5]), .Q6(cdn[6]), .Q7(cdn[7]),
        .Q8(cdn[8]), .Q9(cdn[9]), .Q10(cdn[10]), .Q11(cdn[11]), .Q12(cdn[12]), .Q13(cdn[13]), .Q14(cdn[14]), .Q15(cdn[15]));

    // (see usb_hs_os32.v for the reasoning behind the squelch, the mask timing and the hold level)
    // (wire declarations used above: the comparator words and the transmit enable in pclk)
    reg         cmp_r, cmp_r2;
    reg  [15:0] samples_d, samples_d2;
    always @(posedge pclk) begin
        cmp_r <= |cdp | |cdn; cmp_r2 <= cmp_r;
        samples_d <= samples; samples_d2 <= samples_d;
    end
    // own transmission: masked from the driver enable request on, for 13 words after it (the echo
    // lags it by OE_DLY + the IDES16 latency, a few words; the margin is that of usb_hs_os32.v)
    reg  [13:0] drv_sh;
    always @(posedge pclk) drv_sh <= {drv_sh[12:0], w_oe};
    wire tx_mask = |drv_sh | w_oe;
    wire sq = ~(cmp_r | cmp_r2) | tx_mask;       // squelched: idle line or own transmission (aligned with samples_d2)
    reg  hold;
    always @(posedge pclk) if (!sq) hold <= samples_d2[15];
    wire [15:0] samples_m = sq ? {16{hold}} : samples_d2;
    wire sq_open = ~sq;                          // (capture hook)
    reg  [23:0] sq_sh;
    always @(posedge pclk) sq_sh <= {sq_sh[22:0], sq};
    wire reacq   = |sq_sh[23:12];
    wire sq_long = sq & &sq_sh[23:0];            // idle for 25 words (~210 ns)

    // ---- CDR + gearbox ----
    wire [4:0] bits; wire [3:0] nbits;
    reg [1:0] scan_fz_s, scan_ofs_s; reg [1:0] scan_cls_s;
    always @(posedge pclk) begin scan_fz_s <= {scan_fz_s[0], i_scan_freeze}; scan_ofs_s <= {scan_ofs_s[0], i_scan_ofs}; scan_cls_s <= i_scan_class; end
    wire scan_fz = scan_fz_s[1];
    wire [11:0] cdr_cnt;   // 4 classes x 3 bits (0..4 transitions per word)
    wire [1:0]  cdr_phase; wire cdr_slip, cdr_lock;
    OsCdr #(.SAMPLES(16), .OSR(4), .IIR(2), .HYST(2), .ACT_MIN(1), .DLY(9)) u_cdr(
        .i_clk(pclk), .i_rst(prst), .i_samples(samples_m), .i_freeze(scan_fz), .i_reacq(reacq & ~scan_fz),
        .i_phase_force(scan_fz), .i_phase_val(scan_cls_s), .i_phase_ofs(scan_ofs_s[1]), .o_cnt(cdr_cnt), .o_phase(cdr_phase), .o_acq(),
        .o_bits(bits), .o_nbits(nbits), .o_lock(cdr_lock), .o_slip(cdr_slip), .o_acc_first(), .o_acc_last());
    // Activity window: the gearbox is held cleared while the line is idle. The CDR keeps producing
    // (hold-level) bits in idle at exactly the rate the PHY consumes, so nothing is lost by dropping
    // them, and a packet then starts with an empty accumulator (no stale bits ahead of its SYNC).
    // The window opens with the first word carrying transitions (the SYNC; the CDR/gearbox output
    // lags the input by DLY 9 + ~5 words, so the clear ends long before the SYNC bits arrive) and
    // closes once idle has lasted 25 words, i.e. after the packet tail has left the pipeline.
    wire toggling = (samples_m != 16'h0) && (samples_m != 16'hffff);
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
    function [4:0] popcnt16(input [15:0] v);
        integer k; begin popcnt16 = 0; for (k = 0; k < 16; k = k + 1) popcnt16 = popcnt16 + v[k]; end
    endfunction
    wire [15:0] se0_raw = ~cdp & ~cdn;
    // majority over 96 samples (50 ns, as the original's three 60 MHz words) surrounding the 3-word-delayed level
    reg  [4:0] se0_c [0:5];
    reg  [2:0] dd_d; wire dd_d2 = dd_d[2];
    integer si;
    always @(posedge pclk) begin
        se0_c[0] <= popcnt16(se0_raw);
        for (si = 1; si < 6; si = si + 1) se0_c[si] <= se0_c[si-1];
        dd_d <= {dd_d[1:0], samples[0]};
    end
    reg  [6:0] se0_sum;
    always @(posedge pclk) se0_sum <= se0_c[0] + se0_c[1] + se0_c[2] + se0_c[3] + se0_c[4] + se0_c[5];
    wire se0_f = se0_sum >= 7'd48;
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
    // ending at E + 2T, nibble 1 in the one after; each bit goes out 4 times at 1.92 Gbps
    // (the PHY's line outputs are re-registered in clk60 first, so the crossing into pclk is
    // register-to-register as well; one clk60 of extra transmit latency)
    reg [7:0] t_dp8, t_dn8; reg t_oe;
    always @(posedge clk60) begin t_dp8 <= tx_dp8; t_dn8 <= tx_dn8; t_oe <= tx_oe; end
    reg [7:0] w_dp, w_dn; reg w_oe;
    always @(posedge pclk) if (!ph) begin w_dp <= t_dp8; w_dn <= t_dn8; w_oe <= t_oe; end
    wire [3:0] tx_dp = ph ? w_dp[3:0] : w_dp[7:4];
    wire [3:0] tx_dn = ph ? w_dn[3:0] : w_dn[7:4];
    // line bits to the serialiser: while the driver is off the last bit is held, so the driver can
    // be enabled early / released late without a glitch (FS: the J before SYNC / after the EOP)
    reg        last_bit;
    always @(posedge pclk) if (w_oe) last_bit <= tx_dp[3];
    wire [3:0] ser_bits = w_oe ? tx_dp : {4{last_bit}};
    // driver enable per word: transmitting and not SE0 (the pair cannot drive both lines low; an
    // SE0 word is made by the termination pins instead). A word handed over in the cycle ending at E
    // leaves the OSER16 at E + ~1.9 T; oe_sh[OE_DLY-1] puts its enable on the pad at E + 2 T, and the
    // neighbouring slots stretch it by one word on either side
    wire       w_se0 = w_oe && !(|(tx_dp | tx_dn));
    reg  [OE_DLY:0] oe_sh, se0_sh;
    always @(posedge pclk) begin
        oe_sh  <= {oe_sh[OE_DLY-1:0], w_oe};
        se0_sh <= {se0_sh[OE_DLY-1:0], w_se0};
        tx_dx_oen <= ~((|oe_sh[OE_DLY:OE_DLY-2]) & ~se0_sh[OE_DLY-1]);
    end
    reg se0_drv = 1'b0;
    always @(posedge pclk) se0_drv <= se0_sh[OE_DLY-1];

    // ---- transition histogram (eye diagram of the edges, 1/4 UI bins; see usb_hs_os32.v) ----
    reg [2:0]  hist_s; always @(posedge pclk) hist_s <= {hist_s[1:0], i_hist_run};
    reg        hist_acq;
    always @(posedge pclk) if (sq) hist_acq <= 1'b0; else if (cdr_slip) hist_acq <= 1'b1;
    reg [11:0] cnt_d [0:3]; reg [3:0] drv_d; reg [1:0] ph_d [0:3];
    integer di;
    always @(posedge pclk) begin
        cnt_d[0] <= cdr_cnt; ph_d[0] <= cdr_phase; drv_d <= {drv_d[2:0], cmp_r2 & ~sq & hist_acq};
        for (di = 1; di < 4; di = di + 1) begin cnt_d[di] <= cnt_d[di-1]; ph_d[di] <= ph_d[di-1]; end
    end
    wire        hist_ok = &drv_d && (cmp_r2 & ~sq);
    wire [11:0] hist_cnt = cnt_d[3];
    wire [1:0]  hist_ph  = ph_d[3];
    reg [23:0] hist [0:3];
    genvar hc;
    generate for (hc = 0; hc < 4; hc = hc + 1) begin : g_hist
        wire [1:0] src = hc + hist_ph;
        always @(posedge pclk) begin
            if (hist_s[1] & ~hist_s[2]) hist[hc] <= 24'd0;
            else if (hist_s[2] && hist_ok) hist[hc] <= hist[hc] + hist_cnt[src*3 +: 3];
        end
        assign o_hist[hc*24 +: 24] = hist[hc];
    end endgenerate

    // ---- serialiser: 4 line bits per pclk, each sent 4 times at 1.92 Gbps ----
    OSER16 u_oser_dx(
        .D0(ser_bits[0]), .D1(ser_bits[0]), .D2(ser_bits[0]), .D3(ser_bits[0]),
        .D4(ser_bits[1]), .D5(ser_bits[1]), .D6(ser_bits[1]), .D7(ser_bits[1]),
        .D8(ser_bits[2]), .D9(ser_bits[2]), .D10(ser_bits[2]), .D11(ser_bits[2]),
        .D12(ser_bits[3]), .D13(ser_bits[3]), .D14(ser_bits[3]), .D15(ser_bits[3]),
        .FCLK(fclk), .PCLK(pclk), .RESET(prst), .Q(tx_dx_q));

    // ---- terminations / pull-up ----
    assign usb_pullup_en_o = pullup_dp_en;
    assign usb_term_dp_o   = (term_dp_en | se0_drv) ? 1'b0 : 1'bz;
    assign usb_term_dn_o   = (term_dn_en | se0_drv) ? 1'b0 : 1'bz;
endmodule
