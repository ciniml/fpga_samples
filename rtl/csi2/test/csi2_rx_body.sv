// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Csi2Rx end-to-end test: a 2-lane D-PHY transmitter model (clock lane +
// D0 + D1 as the differential receiver outputs) sampled at 4 Gsps
// (32 samples per 8 ns word, as OSIDES32 at 500 MHz).
//
// Each packet is one HS burst, as the IMX219 sends them. Data lane:
// LP-11 -> LP-01 -> LP-00 (THS-PREPARE) -> HS-0 (THS-ZERO) -> sync 0xB8 ->
// bytes -> trail (last bit inverted) -> LP-11. Clock lane (non-continuous):
// LP-01 -> LP-00 -> HS-0 (TCLK-ZERO) -> toggling from TCLK-PRE before the
// data lane leaves LP until TCLK-POST after the data trail -> HS-0 -> LP-11.
// CONT_CLK = 1 keeps the clock toggling for the whole run. The receiver has
// no LP detector: LP-11 / LP-00 (0 V differential) are modelled as chatter
// (LP_NOISE = 1: the level flips with probability 0.3 per sample) or a
// constant 0. LP-01 is a solid 0 (Dp low).
//
// Frames: FS, embedded data (DT 0x12), NLINES RAW10 lines (DT 0x2B, WC =
// 5 * WGROUPS), a generic long packet with an odd WC (DT 0x30), FE. The
// checker requires every packet, in order, with the right DT/WC/payload
// and a good CRC; with LP_NOISE extra (garbage) events are counted but
// tolerated.
`timescale 1ns/1ps
module csi2_rx_body #(
    parameter real UI_NS    = 2.193,   // 456 Mbps
    parameter real PPM      = 0.0,
    parameter real JITTER   = 0.0,     // peak sampling-time jitter in UI
    parameter real SKEW1_NS = 0.0,     // lane 1 delay
    parameter bit  CONT_CLK = 0,
    parameter bit  LP_NOISE = 1,
    parameter int  OFS0     = 8,
    parameter int  OFS1     = 8,
    parameter int  NFRAMES  = 2,
    parameter int  NLINES   = 6,
    parameter int  WGROUPS  = 16,      // RAW10 line = 4 * WGROUPS pixels
    parameter int  SEED     = 1,
    parameter bit  RUN      = 0,
    parameter bit  DBG      = 0
) ();
    localparam int  SAMPLES = 32;
    localparam real SP_NS   = 0.25;
    localparam real CLK_NS  = SP_NS * SAMPLES;
    localparam int  MAXSEG  = 4096;
    localparam int  MAXBITS = 1 << 18;
    localparam int  MAXPKT  = 256;
    localparam int  MAXEXP  = 1 << 16;

    real ui;
    // ---- waveform segments per lane (0 = clock, 1 = D0, 2 = D1) ----
    // kind: 0 constant, 1 chatter, 2 HS bits, 3 clock toggling (1 first)
    real  seg_t0 [3][MAXSEG];
    real  seg_t1 [3][MAXSEG];
    int   seg_kind[3][MAXSEG];
    logic seg_val [3][MAXSEG];
    int   seg_base[3][MAXSEG];
    int   nseg [3];
    logic hsbits[3][MAXBITS];
    int   nbit [3];

    function automatic void add_seg(int l, real t0, real t1, int kind, logic val, int base);
        seg_t0[l][nseg[l]] = t0; seg_t1[l][nseg[l]] = t1; seg_kind[l][nseg[l]] = kind;
        seg_val[l][nseg[l]] = val; seg_base[l][nseg[l]] = base;
        nseg[l]++;
    endfunction

    // ---- expected packets ----
    int   exp_dt [MAXPKT];
    int   exp_wc [MAXPKT];
    int   exp_base[MAXPKT];
    logic [7:0] exp_bytes[MAXEXP];
    int   nexp = 0, nexpb = 0;

    function automatic logic [5:0] ecc6(input logic [23:0] d);
        logic [5:0] cols [24] = '{6'h07,6'h0B,6'h0D,6'h0E,6'h13,6'h15,6'h16,6'h19,6'h1A,6'h1C,6'h23,6'h25,
                                  6'h26,6'h29,6'h2A,6'h2C,6'h31,6'h32,6'h34,6'h38,6'h1F,6'h2F,6'h37,6'h3B};
        logic [5:0] e = 0;
        for (int i = 0; i < 24; i++) if (d[i]) e ^= cols[i];
        return e;
    endfunction
    function automatic logic [15:0] crc16(input logic [15:0] c, input logic [7:0] b);
        for (int i = 0; i < 8; i++) begin
            logic fb = c[0] ^ b[i];
            c = {1'b0, c[15:1]};
            if (fb) c ^= 16'h8408;
        end
        return c;
    endfunction

    real tcur;          // time the next burst may start
    real clk_t0;        // continuous clock start

    // one packet = one HS burst on both data lanes
    function automatic void burst(input logic [7:0] pkt[], input int n);
        real tb, tc, td, ts, te, tend;
        int  k, nb [2];
        tb = tcur;
        if (!CONT_CLK) begin
            tc = tb + 50.0 + 60.0 + 300.0;                    // LP-01, LP-00, TCLK-ZERO
            add_seg(0, tb, tb + 50.0, 0, 1'b0, 0);
            add_seg(0, tb + 50.0, tb + 110.0, LP_NOISE ? 1 : 0, 1'b0, 0);
            add_seg(0, tb + 110.0, tc, 0, 1'b0, 0);
        end else begin
            tc = clk_t0;
        end
        td = (CONT_CLK ? tb : tc + 8.0 * ui);                  // TCLK-PRE
        add_seg(1, td, td + 50.0, 0, 1'b0, 0); add_seg(2, td, td + 50.0, 0, 1'b0, 0);
        add_seg(1, td + 50.0, td + 110.0, LP_NOISE ? 1 : 0, 1'b0, 0);
        add_seg(2, td + 50.0, td + 110.0, LP_NOISE ? 1 : 0, 1'b0, 0);
        // sync start: clock edges at the data bit centres, >= 150 ns of HS-0
        k  = int'($ceil((td + 260.0 - tc) / ui));
        ts = tc + (k + 0.5) * ui;
        add_seg(1, td + 110.0, ts, 0, 1'b0, 0); add_seg(2, td + 110.0, ts, 0, 1'b0, 0);
        for (int l = 0; l < 2; l++) begin
            int base = nbit[l + 1];
            logic last;
            for (int i = 0; i < 8; i++) hsbits[l + 1][nbit[l + 1]++] = 8'hB8 >> i;
            for (int j = l; j < n; j += 2)
                for (int i = 0; i < 8; i++) hsbits[l + 1][nbit[l + 1]++] = pkt[j][i];
            nb[l] = nbit[l + 1] - base;
            last = hsbits[l + 1][nbit[l + 1] - 1];
            add_seg(l + 1, ts, ts + nb[l] * ui, 2, 1'b0, base);
            add_seg(l + 1, ts + nb[l] * ui, ts + nb[l] * ui + 70.0, 0, ~last, 0);   // THS-TRAIL
        end
        te = ts + nb[0] * ui + 70.0;
        if (!CONT_CLK) begin
            tend = te + 60.0 + 52.0 * ui;                      // TCLK-POST
            tend = tc + $ceil((tend - tc) / ui) * ui;
            add_seg(0, tc, tend, 3, 1'b0, 0);
            add_seg(0, tend, tend + 60.0, 0, 1'b0, 0);         // TCLK-TRAIL
            tend = tend + 60.0;
        end else begin
            tend = te;
        end
        tcur = tend + 200.0 + ($urandom() % 1300);
        // LP-11 until the next burst
        if (!CONT_CLK) add_seg(0, tend, tcur, LP_NOISE ? 1 : 0, 1'b0, 0);
        add_seg(1, te, tcur + (CONT_CLK ? 0.0 : 8.0 * ui + 410.0), LP_NOISE ? 1 : 0, 1'b0, 0);
        add_seg(2, te, tcur + (CONT_CLK ? 0.0 : 8.0 * ui + 410.0), LP_NOISE ? 1 : 0, 1'b0, 0);
    endfunction

    function automatic void packet(input int dt, input int wc, input logic [7:0] payload[]);
        logic [7:0] p[];
        logic [23:0] h = {wc[15:0], 2'b00, dt[5:0]};
        int n = (dt < 16) ? 4 : 4 + wc + 2;
        logic [15:0] c = 16'hFFFF;
        p = new[n];
        p[0] = h[7:0]; p[1] = h[15:8]; p[2] = h[23:16]; p[3] = {2'b00, ecc6(h)};
        if (dt >= 16) begin
            for (int i = 0; i < wc; i++) begin p[4 + i] = payload[i]; c = crc16(c, payload[i]); end
            p[4 + wc] = c[7:0]; p[5 + wc] = c[15:8];
        end
        exp_dt[nexp] = dt; exp_wc[nexp] = wc; exp_base[nexp] = nexpb;
        if (dt >= 16) for (int i = 0; i < wc; i++) exp_bytes[nexpb++] = payload[i];
        nexp++;
        burst(p, n);
    endfunction

    function automatic void long_rand(input int dt, input int wc);
        logic [7:0] pl[];
        pl = new[wc];
        for (int i = 0; i < wc; i++) pl[i] = $urandom();
        packet(dt, wc, pl);
    endfunction

    real t_end;
    initial begin
        logic [7:0] none[];
        void'($urandom(SEED));
        ui = UI_NS * (1.0 + PPM / 1e6);
        for (int l = 0; l < 3; l++) begin nseg[l] = 0; nbit[l] = 0; end
        tcur = 300.0;
        clk_t0 = 100.0;
        // idle until the first burst
        add_seg(1, 0.0, 300.0 + (CONT_CLK ? 0.0 : 8.0 * ui + 410.0), LP_NOISE ? 1 : 0, 1'b0, 0);
        add_seg(2, 0.0, 300.0 + (CONT_CLK ? 0.0 : 8.0 * ui + 410.0), LP_NOISE ? 1 : 0, 1'b0, 0);
        if (!CONT_CLK) add_seg(0, 0.0, 300.0, LP_NOISE ? 1 : 0, 1'b0, 0);
        else           add_seg(0, 0.0, clk_t0, 0, 1'b0, 0);
        for (int f = 0; f < NFRAMES; f++) begin
            packet(6'h00, f + 1, none);                       // FS (frame number)
            long_rand(6'h12, 20);                              // embedded data
            for (int y = 0; y < NLINES; y++) long_rand(6'h2B, 5 * WGROUPS);
            long_rand(6'h30, 5 * WGROUPS + 1);                 // odd word count
            packet(6'h01, f + 1, none);                       // FE
        end
        t_end = tcur + 2000.0;
        if (CONT_CLK) add_seg(0, clk_t0, t_end + 100.0, 3, 1'b0, 0);
        for (int l = 0; l < 3; l++) add_seg(l, t_end, 1e9, 0, 1'b0, 0);
    end

    // ---- receiver-side sampling ----
    int   ptr [3] = '{0, 0, 0};
    logic chat[3] = '{0, 0, 0};
    function automatic logic level(input int l, input real t);
        int s;
        while (ptr[l] + 1 < nseg[l] && t >= seg_t1[l][ptr[l]]) ptr[l]++;
        while (ptr[l] > 0 && t < seg_t0[l][ptr[l]]) ptr[l]--;
        s = ptr[l];
        // segments of different lanes were appended out of order: search locally
        if (t < seg_t0[l][s] || t >= seg_t1[l][s]) begin
            for (int i = 0; i < nseg[l]; i++)
                if (t >= seg_t0[l][i] && t < seg_t1[l][i]) begin s = i; ptr[l] = i; break; end
        end
        case (seg_kind[l][s])
            0: return seg_val[l][s];
            1: begin if (($urandom() % 10) < 3) chat[l] = ~chat[l]; return chat[l]; end
            2: return hsbits[l][seg_base[l][s] + int'($floor((t - seg_t0[l][s]) / ui))];
            default: return (int'($floor((t - seg_t0[l][s]) / ui)) % 2) == 0;
        endcase
    endfunction

    logic clk = 0, rst = 1;
    always #(CLK_NS / 2) clk = ~clk;
    real tnow = 0.0;
    logic [SAMPLES-1:0] cs;
    logic [1:0][SAMPLES-1:0] ds;
    always @(posedge clk) begin
        for (int j = 0; j < SAMPLES; j++) begin
            real t = tnow + SP_NS * j;
            if (JITTER != 0.0) t += JITTER * ui * (2.0 * ($urandom() / 4294967296.0) - 1.0);
            cs[j]    <= level(0, t);
            ds[0][j] <= level(1, t);
            ds[1][j] <= level(2, t - SKEW1_NS);
        end
        tnow <= tnow + CLK_NS;
    end

    // ---- DUT ----
    logic hdr, short_, dvld, pend, crc_ok, ecc_corr, ecc_err, abort_;
    logic [1:0] vc, be; logic [5:0] dt; logic [15:0] wc, data;
    logic [3:0] nbits; logic ovf, drop; logic [1:0] sync, active;
    Csi2Rx #(.SAMPLES(SAMPLES)) dut (
        .i_clk(clk), .i_rst(rst), .i_cs(cs), .i_ds(ds), .i_inv(2'b00), .i_ofs({4'(OFS1), 4'(OFS0)}),
        .o_hdr(hdr), .o_short(short_), .o_vc(vc), .o_dt(dt), .o_wc(wc), .o_data(data), .o_data_be(be),
        .o_data_vld(dvld), .o_end(pend), .o_crc_ok(crc_ok), .o_ecc_corr(ecc_corr), .o_ecc_err(ecc_err),
        .o_abort(abort_), .o_dbg_nbits(nbits), .o_dbg_ovf(ovf), .o_dbg_sync(sync), .o_dbg_drop(drop),
        .o_dbg_active(active));

    // ---- debug trace ----
    always @(posedge clk) if (!rst && $time < 4000000 && DBG) begin
        if (sync[0] || sync[1]) $display("[%0t] sync %b", $time, sync);
        if (dut.vld0 || dut.vld1) $display("[%0t] byte l0 %0d %02h f%0d | l1 %0d %02h f%0d", $time, dut.vld0, dut.byte0, dut.fst0, dut.vld1, dut.byte1, dut.fst1);
        if (dut.bvld) $display("[%0t] beat %04h sot %0d", $time, dut.beat, dut.bsot);
        if (dut.hunt) $display("[%0t] hunt", $time);
    end
    // ---- checker ----
    int idx = 0, ok = 0, fails = 0, extra = 0, n_ecc_err = 0, n_corr = 0, n_abort = 0, n_drop = 0, n_ovf = 0;
    int n_sync = 0;
    bit in_long = 0, cur_match = 0; int got = 0; bit bad = 0;
    always @(posedge clk) if (!rst) begin
        if (ecc_err) n_ecc_err++;
        if (ecc_corr) n_corr++;
        if (abort_) begin n_abort++; in_long = 0; end
        if (drop) n_drop++;
        if (ovf) n_ovf++;
        n_sync += sync[0] + sync[1];
        if (hdr) begin
            cur_match = (idx < nexp) && dt == exp_dt[idx] && wc == exp_wc[idx];
            if (!cur_match) begin
                extra++;
                $display("[%0t] extra header dt=%02h wc=%0d (expected #%0d dt=%02h wc=%0d)", $time, dt, wc, idx, exp_dt[idx], exp_wc[idx]);
            end
            if (short_) begin
                if (cur_match) begin ok++; idx++; end
            end else begin
                in_long = 1; got = 0; bad = 0;
            end
        end
        if (dvld && in_long && cur_match) begin
            for (int k = 0; k < 2; k++) if (be[k]) begin
                if (got >= exp_wc[idx] || data[8*k +: 8] != exp_bytes[exp_base[idx] + got]) bad = 1;
                got++;
            end
        end
        if (pend && in_long) begin
            in_long = 0;
            if (cur_match) begin
                if (bad || got != exp_wc[idx] || !crc_ok) begin
                    fails++;
                    $display("[%0t] packet #%0d dt=%02h: bad=%0d got=%0d/%0d crc_ok=%0d", $time, idx, dt, bad, got, exp_wc[idx], crc_ok);
                end else ok++;
                idx++;
            end
        end
    end

    initial if (RUN) begin
        repeat (8) @(posedge clk);
        @(negedge clk) rst = 0;
        wait (tnow > t_end && t_end > 0.0);
        repeat (16) @(posedge clk);
        $display("csi2_rx: UI %.3f ns ppm %.0f jitter %.2f skew %.2f cont %0d noise %0d: packets %0d/%0d ok, fails %0d, extra %0d, ecc_err %0d, ecc_corr %0d, abort %0d, drop %0d, ovf %0d, syncs %0d",
                 UI_NS, PPM, JITTER, SKEW1_NS, CONT_CLK, LP_NOISE, ok, nexp, fails, extra, n_ecc_err, n_corr, n_abort, n_drop, n_ovf, n_sync);
        if (ok != nexp || fails != 0 || (!LP_NOISE && (extra != 0 || n_ecc_err != 0 || n_ovf != 0)))
            $fatal(1, "csi2_rx: FAIL");
        $display("csi2_rx: PASS");
        $finish;
    end
endmodule
