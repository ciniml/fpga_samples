// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// USB HS serial path with the EasyCDR-style 4-phase oversampler: the
// differential receiver drives an OSIDES32 (4-phase FCLK 480 MHz, two
// IODELAY taps -> 8 sample instants per FCLK period = 3.84 Gsps = 8 samples
// per HS bit), 32 samples per PCLK (FCLK/4 = 120 MHz) word. OsCdr (OSR 8)
// recovers 3..5 bits per word, BitGearbox packs bytes, an async FIFO
// carries them to the 60 MHz UTMI domain (one byte per clock, o_valid = 0
// on a clock without one). The 480 MHz comes from a PLL fed by
// the 60 MHz UTMI clock (VCO 960 = 60 x 16), so both domains are frequency
// locked; the CDR only tracks the host's +/-500 ppm.
// The transmitter shares the FCLK/PCLK (one HCLK group per bank pair): each
// HS bit is sent twice through an OSER8 at 960 Mbps (= 480 Mbps exactly), the
// 8-sample TX words cross from 60 MHz to PCLK through a small FIFO read at
// exactly half rate (4 samples per PCLK).
//
// Idle / squelch comes from the single-ended comparators sampled at 960 Msps
// by two IDES8 on the same clocks (one comparator high in this or the next
// 8-sample word = line active):
// the data samples are forced to J while squelched (the differential
// receiver has no squelch of its own), the CDR re-acquires the phase on
// every word with transitions while idle was flagged within the last 12
// words (i_reacq: covers the SYNC even though the squelch lifts a word or
// two into it; the jump is applied from the SYNC's first word through the
// OsCdr DLY data-path delay), and words recovered in steady idle are not
// queued (the FIFO would never drain: the idle bit rate equals the drain
// rate exactly). The 60 MHz i_se0 (both comparators low for 16 clocks) only
// drops leftovers on the read side in long idle.
// Clocking / reset sequencing follows eda/easycdr_bert oscdr_phy_gw5a.v
// (DHCE gating of the four phases, CLKDIV /4, PCLK reset).
`timescale 1ns/1ps
module usb_hs_os32 #(
    parameter DLY0 = 0,
    parameter DLY1 = 20    // second IODELAY tap = half the phase spacing (~260 ps)
) (
    input  wire        clk_ref_i,     // 50 MHz (PLL reference, reset sequencing)
    input  wire        rstn_ref_i,
    input  wire        pll_lock_i,
    input  wire        fclk0_i,       // 4-phase oversampling clocks from the PLL
    input  wire        fclk90_i,
    input  wire        fclk180_i,
    input  wire        fclk270_i,
    input  wire        serial_i,      // TLVDS_IBUF output of the D+/D- receiver
    input  wire        cmp_dp_i,      // single-ended comparators (IDES8 at 960 Msps: squelch / idle)
    input  wire        cmp_dn_i,

    input  wire        clk_i,         // 60 MHz UTMI clock
    input  wire        rst_i,
    input  wire        i_se0,         // both comparators low, one sample per 60 MHz clock (raw)
    input  wire        i_scan_freeze, // eye scan: freeze the CDR at class i_scan_class (60 MHz domain, quasi-static)
    input  wire        i_scan_ofs,    // eye scan: acquire each packet at (best + i_scan_class), no tracking
    input  wire [2:0]  i_scan_class,
    input  wire        i_hist_run,    // transition histogram window (60 MHz): cleared on the rising edge, accumulates while high
    output wire [191:0] o_hist,       // 8 x 24-bit transitions per sample class (stable while i_hist_run is low)
    output reg  [7:0]  o_byte,
    output reg         o_valid,
    output wire        o_dd_level,    // one line sample per 60 MHz clock (FS J/K, synchronised)
    output wire        o_pclk,
    output wire        o_lock,
    output wire [31:0] o_samples,     // raw word (debug)
    output wire [15:0] o_cmp_dbg,     // {cdp, cdn} comparator words (debug)

    // transmitter (60 MHz side: 8 samples per clock as UsbPhy produces them)
    input  wire [7:0]  i_tx_dp,
    input  wire [7:0]  i_tx_dn,
    input  wire        i_tx_oe,
    output wire        o_tx_dp,       // pad data / output enables (TBUF at the caller)
    output wire        o_tx_dn,
    output wire        o_tx_dp_oen,
    output wire        o_tx_dn_oen
);
    // ---- clocking / reset (PCLK domain) ----
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
    wire fclkp, fclkqp, fclkn, fclkqn, pclk;
    DHCE u_dhce_0  (.CLKIN(fclk0_i),   .CEN(cen), .CLKOUT(fclkp));
    DHCE u_dhce_90 (.CLKIN(fclk90_i),  .CEN(cen), .CLKOUT(fclkqp));
    DHCE u_dhce_180(.CLKIN(fclk180_i), .CEN(cen), .CLKOUT(fclkn));
    DHCE u_dhce_270(.CLKIN(fclk270_i), .CEN(cen), .CLKOUT(fclkqn));
    CLKDIV u_clkdiv(.HCLKIN(fclkp), .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(pclk));
    defparam u_clkdiv.DIV_MODE = "4";
    assign o_pclk = pclk;
    reg [2:0] rst_sync;
    always @(posedge pclk or negedge resetn_div) begin
        if (!resetn_div) rst_sync <= 3'b111; else rst_sync <= {rst_sync[1:0], 1'b0};
    end
    wire prst = rst_sync[2];

    // ---- oversampling deserializer (static taps, as the Gowin IP) ----
    wire [31:0] samples;
    assign o_samples = samples;
    assign o_cmp_dbg = {cdp, cdn};
    OSIDES32 #(
        .C_STATIC_DLY_0(DLY0), .DYN_DLY_EN_0("FALSE"), .ADAPT_EN_0("FALSE"),
        .C_STATIC_DLY_1(DLY1), .DYN_DLY_EN_1("FALSE"), .ADAPT_EN_1("FALSE")
    ) u_osides32(
        .Q(samples), .DF0(), .DF1(), .D(serial_i), .PCLK(pclk),
        .FCLKP(fclkp), .FCLKQP(fclkqp), .FCLKN(fclkn), .FCLKQN(fclkqn), .RESET(prst),
        .SDTAP0(1'b0), .VALUE0(1'b0), .DLYSTEP0(8'd0), .SDTAP1(1'b0), .VALUE1(1'b0), .DLYSTEP1(8'd0));

    // ---- squelch from the single-ended comparators (PCLK domain) ----
    // The differential receiver has no squelch: it toggles on low-amplitude
    // bus noise (< the 132 mV comparator threshold; seen ~80 ns after SOFs
    // and ACKs, probably coupling from the other hub ports) and while the
    // line rings down after a driver turns off. The comparators, sampled at
    // 960 Msps, see a HS packet as at least one line high in every 8-sample
    // word; with no comparator high for 3 words (~25 ns) the data samples
    // are forced to idle (J).
    wire [7:0] cdp, cdn;    // (o_cmp_dbg)
    IDES8 u_ides_dp(.D(cmp_dp_i), .FCLK(fclkp), .PCLK(pclk), .CALIB(1'b0), .RESET(prst),
        .Q0(cdp[0]), .Q1(cdp[1]), .Q2(cdp[2]), .Q3(cdp[3]), .Q4(cdp[4]), .Q5(cdp[5]), .Q6(cdp[6]), .Q7(cdp[7]));
    IDES8 u_ides_dn(.D(cmp_dn_i), .FCLK(fclkp), .PCLK(pclk), .CALIB(1'b0), .RESET(prst),
        .Q0(cdn[0]), .Q1(cdn[1]), .Q2(cdn[2]), .Q3(cdn[3]), .Q4(cdn[4]), .Q5(cdn[5]), .Q6(cdn[6]), .Q7(cdn[7]));
    // A HS packet keeps one comparator high in every 8-sample word (both are
    // low only at the transitions); they are silent while the line is at SE0,
    // including the ring-down after a driver turns off (the SOF EOP is 40 bit
    // times long, §7.1.13.2.2, and its ring-down used to look like a short
    // packet). The data word is delayed one word so the mask sees one word
    // ahead: samples pass when the comparators are active in this word or the
    // next, so nothing of the SYNC is lost and the ring-down is masked from
    // its first word (to the last level seen, keeping the EOP flat).
    // (registered twice: the IDES8 outputs -> 16-input OR -> 32-bit mask -> CDR
    // transition counters was the critical path at 120 MHz)
    reg         cmp_r, cmp_r2;
    reg  [31:0] samples_d, samples_d2;
    always @(posedge pclk) begin
        cmp_r <= |cdp | |cdn; cmp_r2 <= cmp_r;
        samples_d <= samples; samples_d2 <= samples_d;
    end
    // Our own transmission is squelched too: the receiver pipeline is ~250 ns
    // deep, so the echo of our ACK / DATA would otherwise come out of it after
    // tx_oe has fallen and be taken for a host packet. tx_oe is synchronised
    // (it leads the first line bit by the transmitter's own latency) and
    // stretched 12 words past its end for the last byte and the ring-down.
    reg  [1:0]  txoe_s;
    reg  [11:0] txoe_sh;
    always @(posedge pclk) begin txoe_s <= {txoe_s[0], i_tx_oe}; txoe_sh <= {txoe_sh[10:0], txoe_s[1]}; end
    wire tx_mask = txoe_s[1] | |txoe_sh;
    wire sq = ~(cmp_r | cmp_r2) | tx_mask;       // squelched: idle line or own transmission (aligned with samples_d2)
    // Masked words hold the last level seen, not a fixed J: the HS EOP is a
    // transition followed by a flat run (the bit-stuff violation the decoder
    // looks for), and a packet ending on K would otherwise get a spurious
    // transition where the mask starts, hiding its EOP.
    reg  hold;
    always @(posedge pclk) if (!sq) hold <= samples_d2[31];
    wire [31:0] samples_m = sq ? {32{hold}} : samples_d2;
    wire sq_open = ~sq;                          // (capture hook)
    // Re-acquisition window: the CDR extracts DLY = 9 words behind the
    // histogram, so a phase jump made right after the line goes idle would
    // land on the previous packet's tail (its EOP). Enable it only once idle
    // has lasted 12 words, and keep it for 12 more words after idle ends so
    // it covers the next SYNC (whose jump is decided 7 words in). After a
    // gap shorter than ~100 ns the phase is simply tracked on.
    reg  [23:0] sq_sh;
    always @(posedge pclk) sq_sh <= {sq_sh[22:0], sq};
    wire reacq = |sq_sh[23:12];
    // The write window closes only once the packet tail has left the CDR /
    // gearbox pipeline (DLY 9 + histogram/extraction 5 + gearbox 2 words).
    wire sq_long = sq & &sq_sh[23:0];            // idle for 25 words (~210 ns)

    // ---- idle detection: SE0 on SE0_N consecutive 60 MHz samples (~270 ns).
    // The comparators toggle at the bit rate during packets, so single
    // samples read SE0 about a quarter of the time; HS idle is a solid SE0.
    localparam SE0_N = 16;
    reg [4:0] se0_cnt; reg se0_60;
    always @(posedge clk_i) begin
        if (rst_i) begin se0_cnt <= 0; se0_60 <= 1'b1; end
        else if (!i_se0) begin se0_cnt <= 0; se0_60 <= 1'b0; end
        else if (se0_cnt == SE0_N - 1) se0_60 <= 1'b1;
        else se0_cnt <= se0_cnt + 1'b1;
    end
    wire se0 = sq;                               // (name kept for the capture hooks)

    // ---- CDR + gearbox (PCLK) ----
    wire [4:0] bits; wire [3:0] nbits;
    // ACT_MIN 1: one word of SYNC (4 transitions) acquires; DLY 9 = the acquisition latency, so the
    // phase found on the first SYNC word is applied from that word on (no bit duplicated/lost in the
    // SYNC, which would trip the SYNC detector). Re-acquisition (jump to the best class every word)
    // is enabled while se0 is still high, i.e. the ~80 ns idle-detector lag into every packet.
    reg [1:0] scan_fz_s, scan_ofs_s; reg [2:0] scan_cls_s;
    always @(posedge pclk) begin scan_fz_s <= {scan_fz_s[0], i_scan_freeze}; scan_ofs_s <= {scan_ofs_s[0], i_scan_ofs}; scan_cls_s <= i_scan_class; end
    wire scan_fz = scan_fz_s[1];
    wire [23:0] cdr_cnt;   // 8 classes x 3 bits (0..4 transitions per word)
    OsCdr #(.SAMPLES(32), .OSR(8), .IIR(2), .HYST(2), .ACT_MIN(1), .DLY(9)) u_cdr(
        .i_clk(pclk), .i_rst(prst), .i_samples(samples_m), .i_freeze(scan_fz), .i_reacq(reacq & ~scan_fz),
        .i_phase_force(scan_fz), .i_phase_val(scan_cls_s), .i_phase_ofs(scan_ofs_s[1]), .o_cnt(cdr_cnt), .o_phase(cdr_phase), .o_acq(),
        .o_bits(bits), .o_nbits(nbits), .o_lock(o_lock), .o_slip(cdr_slip), .o_acc_first(), .o_acc_last());
    wire        gb_valid; wire [7:0] gb_word;    // bytes, not 16-bit words: half the gearbox wait, no byte split
    BitGearbox #(.IN_MAX(5), .OUT_W(8)) u_gb(
        .i_clk(pclk), .i_rst(prst), .i_bits({4'b0, bits}), .i_nbits(nbits), .o_valid(gb_valid), .o_word(gb_word));

    // ---- async FIFO PCLK -> clk_i (16-bit words, 16 deep, gray pointers) ----
    // The gray-coded pointers and their synchronisers must stay real flops:
    // a gray pointer is a pure function of its binary counter, and the Gowin
    // synthesizer replaces such a register by logic from the counter, which
    // then glitches (several counter bits change at once) into the other
    // clock domain's synchroniser.
    reg  [7:0]  fmem [0:15];
    reg  [4:0]  wp_bin, rp_bin;
    reg  [4:0]  wp_gray /* synthesis syn_preserve=1 */, rp_gray /* synthesis syn_preserve=1 */;
    reg  [4:0]  wp_gray_r1 /* synthesis syn_preserve=1 */, wp_gray_r2 /* synthesis syn_preserve=1 */;
    reg  [4:0]  rp_gray_w1 /* synthesis syn_preserve=1 */, rp_gray_w2 /* synthesis syn_preserve=1 */;
    function [4:0] b2g(input [4:0] b); b2g = b ^ (b >> 1); endfunction
    wire w_full = (wp_gray == {~rp_gray_w2[4:3], rp_gray_w2[2:0]});
    always @(posedge pclk) begin
        if (prst) begin wp_bin <= 0; wp_gray <= 0; rp_gray_w1 <= 0; rp_gray_w2 <= 0; end
        else begin
            rp_gray_w1 <= rp_gray; rp_gray_w2 <= rp_gray_w1;
            // Idle words are not queued: the CDR keeps producing (idle-J) bits at exactly the
            // rate the 60 MHz side drains, so anything queued during idle would stay queued
            // forever (backlog -> full FIFO -> packet bytes lost). The window opens with the
            // first word that carries transitions (the SYNC itself; se0 lags the line by ~80 ns,
            // which would eat most of the SYNC) and closes when se0 arrives, long after the
            // packet tail has been written.
            if (gb_valid && !w_full && act) begin fmem[wp_bin[3:0]] <= gb_word; wp_bin <= wp_bin + 1'b1; wp_gray <= b2g(wp_bin + 1'b1); end
        end
    end
    // activity window (see above)
    wire toggling = (samples_m != 32'h0) && (samples_m != 32'hffffffff);
    reg  act;
    always @(posedge pclk) begin
        if (prst) act <= 1'b0;
        else if (toggling) act <= 1'b1;
        else if (sq_long) act <= 1'b0;
    end
    wire r_empty = (rp_gray == wp_gray_r2);   // one byte per 60 MHz clock = exactly the HS byte rate
    reg  [7:0] se0_sh; always @(posedge clk_i) se0_sh <= {se0_sh[6:0], se0_60};
    wire       idle_steady = se0_sh[7] & se0_60;
    always @(posedge clk_i) begin
        if (rst_i) begin rp_bin <= 0; rp_gray <= 0; wp_gray_r1 <= 0; wp_gray_r2 <= 0; o_valid <= 1'b0; o_byte <= 8'd0; end
        else begin
            wp_gray_r1 <= wp_gray; wp_gray_r2 <= wp_gray_r1;
            o_valid <= 1'b0;
            if (!r_empty) begin
                rp_bin <= rp_bin + 1'b1; rp_gray <= b2g(rp_bin + 1'b1);
                if (!idle_steady) begin o_byte <= fmem[rp_bin[3:0]]; o_valid <= 1'b1; end
            end
        end
    end

    // ---- transition histogram (eye diagram of the edges, 1/8 UI bins) ----
    // Bins are relative to the data sample class in use (bin 0 = the sampling instant, bin 4 = half
    // a UI away), so the histogram is the edge jitter distribution around the eye centre rather than
    // the (random) packet phases.
    reg [2:0]  hist_s; always @(posedge pclk) hist_s <= {hist_s[1:0], i_hist_run};
    wire [2:0] cdr_phase; wire cdr_slip;
    reg        hist_acq;            // the CDR has jumped to this packet's phase (first jump after idle)
    always @(posedge pclk) if (sq) hist_acq <= 1'b0; else if (cdr_slip) hist_acq <= 1'b1;
    // The counts are taken 4 words late and only if the line is still driven 4 words later: the
    // ring-down after a packet (the driver switching off) still trips the comparators for a few
    // words and its random transitions would otherwise put a uniform floor under the histogram.
    reg [23:0] cnt_d [0:3]; reg [3:0] drv_d; reg [2:0] ph_d [0:3];
    integer di;
    always @(posedge pclk) begin
        cnt_d[0] <= cdr_cnt; ph_d[0] <= cdr_phase; drv_d <= {drv_d[2:0], cmp_r2 & ~sq & hist_acq};
        for (di = 1; di < 4; di = di + 1) begin cnt_d[di] <= cnt_d[di-1]; ph_d[di] <= ph_d[di-1]; end
    end
    wire        hist_ok = &drv_d && (cmp_r2 & ~sq);    // this word and the 4 after it are driven, acquired
    wire [23:0] hist_cnt = cnt_d[3];
    wire [2:0]  hist_ph  = ph_d[3];
    reg [23:0] hist [0:7];
    genvar hc;
    generate for (hc = 0; hc < 8; hc = hc + 1) begin : g_hist
        wire [2:0] src = hc + hist_ph;        // class feeding bin hc (mod 8)
        always @(posedge pclk) begin
            if (hist_s[1] & ~hist_s[2]) hist[hc] <= 24'd0;
            else if (hist_s[2] && hist_ok) hist[hc] <= hist[hc] + hist_cnt[src*3 +: 3];
        end
        assign o_hist[hc*24 +: 24] = hist[hc];
    end endgenerate

    // ---- FS: one synchronised line sample per 60 MHz clock ----
    reg [1:0] lvl_s;
    always @(posedge clk_i) lvl_s <= {lvl_s[0], samples[0]};
    assign o_dd_level = lvl_s[1];

    // ---- transmitter: 60 MHz words -> PCLK (exactly 2x), 4 samples per PCLK, each bit sent twice ----
    // 8 entries: the reader judges the occupancy through a two-flop synchroniser, i.e. 2-3 PCLK
    // (1-1.5 words) behind the writer, so it starts only once it sees 4 words queued; the real
    // occupancy then sits around 5 and neither the synchroniser lag (placement dependent: some
    // builds inserted a tri-state gap into every packet and lost the handshakes) nor the exact
    // 2:1 rate can run it empty or full.
    reg  [16:0] tmem [0:7];
    reg  [3:0]  twp /* synthesis syn_preserve=1 */, trp /* synthesis syn_preserve=1 */;   // gray-coded pointers (8 entries)
    reg  [3:0]  twp_r1 /* synthesis syn_preserve=1 */, twp_r2 /* synthesis syn_preserve=1 */;
    reg  [3:0]  trp_w1 /* synthesis syn_preserve=1 */, trp_w2 /* synthesis syn_preserve=1 */;
    function [3:0] g3(input [3:0] b); g3 = b ^ (b >> 1); endfunction
    reg  [3:0]  twp_bin, trp_bin;
    always @(posedge clk_i) begin
        if (rst_i) begin twp_bin <= 0; twp <= 0; trp_w1 <= 0; trp_w2 <= 0; end
        else begin
            trp_w1 <= trp; trp_w2 <= trp_w1;
            tmem[twp_bin[2:0]] <= {i_tx_oe, i_tx_dn, i_tx_dp};
            twp_bin <= twp_bin + 1'b1; twp <= g3(twp_bin + 1'b1);
        end
    end
    // read side: one word every 2 PCLK cycles once at least 2 words are queued (fixed 2:1 ratio -> constant occupancy)
    reg        thalf;       // 0: low half (samples 0..3), 1: high half (4..7)
    reg [16:0] tword;
    reg        tstarted;
    wire       t_empty = (trp == twp_r2);
    function [3:0] g2b4(input [3:0] g); g2b4 = {g[3], g[3]^g[2], g[3]^g[2]^g[1], g[3]^g[2]^g[1]^g[0]}; endfunction
    wire [2:0] t_occ = g2b4(twp_r2) - trp_bin;     // words queued as seen through the synchroniser (mod 8)
    wire       t_ready = t_occ >= 3'd4;
    always @(posedge pclk) begin
        if (prst) begin trp_bin <= 0; trp <= 0; twp_r1 <= 0; twp_r2 <= 0; thalf <= 1'b0; tword <= 17'h10000; tstarted <= 1'b0; end
        else begin
            twp_r1 <= twp; twp_r2 <= twp_r1;
            if (!tstarted) begin
                if (t_ready) tstarted <= 1'b1;
                tword <= 17'h10000;              // tri-state until data flows
            end else if (!thalf) begin
                thalf <= 1'b1;
            end else begin
                thalf <= 1'b0;
                if (!t_empty) begin tword <= tmem[trp_bin[2:0]]; trp_bin <= trp_bin + 1'b1; trp <= g3(trp_bin + 1'b1); end
                else tword <= 17'h10000;
            end
        end
    end
    wire [3:0] tdp4 = thalf ? tword[7:4]  : tword[3:0];
    wire [3:0] tdn4 = thalf ? tword[15:12] : tword[11:8];
    wire       toen = ~tword[16];
    OSER8 u_oser_dp(
        .D0(tdp4[0]), .D1(tdp4[0]), .D2(tdp4[1]), .D3(tdp4[1]), .D4(tdp4[2]), .D5(tdp4[2]), .D6(tdp4[3]), .D7(tdp4[3]),
        .TX0(toen), .TX1(toen), .TX2(toen), .TX3(toen), .FCLK(fclkp), .PCLK(pclk), .RESET(prst),
        .Q0(o_tx_dp), .Q1(o_tx_dp_oen));
    OSER8 u_oser_dn(
        .D0(tdn4[0]), .D1(tdn4[0]), .D2(tdn4[1]), .D3(tdn4[1]), .D4(tdn4[2]), .D5(tdn4[2]), .D6(tdn4[3]), .D7(tdn4[3]),
        .TX0(toen), .TX1(toen), .TX2(toen), .TX3(toen), .FCLK(fclkp), .PCLK(pclk), .RESET(prst),
        .Q0(o_tx_dn), .Q1(o_tx_dn_oen));
endmodule
