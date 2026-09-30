// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// HDMI word stream -> dvi_in -> hdmi_packet_rx -> hdmi_audio_rx ->
// delta_sigma_dac.
//
// The source is a small raster (200 x 40 words) whose horizontal blanking
// carries one data island per line (preamble, guard bands, up to three
// packets): an AVI InfoFrame once per frame, Audio Clock Regeneration
// every 16 lines and Audio Sample packets with the pending samples of a
// 1 kHz 24-bit sine generated at fs = f_pclk * N / (128 * CTS)
// (N = 6144, CTS = 74250: 48 kHz for a 74.25 MHz pixel clock).
// Video periods have the preamble and guard band; active words are TMDS
// data words from dvi_out.
//
// Checks: every sample leaving the FIFO equals the sent one (in order),
// N / CTS, the AVI range flag (limited, then full), exactly the injected
// header / subpacket parity errors, no FIFO under- / overflow. The
// left DAC bit stream (2^20 updates at pclk / 12) goes to dac_left.txt for
// test/analyze.py (in-band SNR).
`timescale 1ns/1ps
`default_nettype none
module tb_hdmi_audio;
    localparam int H_TOTAL = 200, H_ACT0 = 136, H_SYNC = 8;
    localparam int V_TOTAL = 40,  V_ACT0 = 8,   V_SYNC = 2;
    localparam int ISL0 = 12;                        // island preamble start
    localparam int N_ACR = 6144, CTS = 74250;
    localparam int DAC_DIV = 12;
    localparam int DAC_SAMPLES = 1 << 20;
    localparam real F_TONE = 1000.0, FS_AUDIO = 48000.0, AMP = 0.9;

    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    // ---------------- TMDS symbols ----------------
    localparam logic [9:0] CTRL [0:3] = '{10'b1101010100, 10'b0010101011, 10'b0101010100, 10'b1010101011};
    localparam logic [9:0] GB_02 = 10'b1011001100, GB_1 = 10'b0100110011;
    localparam logic [9:0] TERC4 [0:15] = '{
        10'b1010011100, 10'b1001100011, 10'b1011100100, 10'b1011100010,
        10'b0101110001, 10'b0100011110, 10'b0110001110, 10'b0100111100,
        10'b1011001100, 10'b0100111001, 10'b0110011100, 10'b1011000110,
        10'b1010001110, 10'b1001110001, 10'b0101100011, 10'b1011000011};

    // active-video data words from dvi_out (kept in DE so the encoder
    // produces a continuous stream of data symbols)
    logic [23:0] pix = 0;
    logic [9:0]  enc_clk, enc0, enc1, enc2;
    always_ff @(posedge clk) pix <= pix + 24'h030507;
    dvi_out u_enc (.clock(clk), .reset(rst), .video_data(pix), .video_de(1'b1), .video_hsync(1'b0),
                   .video_vsync(1'b0), .dvi_clock(enc_clk), .dvi_data0(enc0), .dvi_data1(enc1), .dvi_data2(enc2));

    // ---------------- packets ----------------
    function automatic [7:0] ecc_next(input [7:0] ecc, input bit b);
        ecc_next = (ecc >> 1) ^ ((ecc[0] ^ b) ? 8'b1000_0011 : 8'd0);
    endfunction
    // packets of the current line: header + parity, 4 subpackets + parity
    logic [31:0] pk_hdr [0:2];
    logic [63:0] pk_sub [0:2][0:3];
    int          npk = 0;
    task automatic add_packet(input [23:0] hb, input [55:0] sb [0:3]);
        logic [7:0] e;
        e = 0;
        for (int i = 0; i < 24; i++) e = ecc_next(e, hb[i]);
        pk_hdr[npk] = {e, hb};
        for (int s = 0; s < 4; s++) begin
            e = 0;
            for (int i = 0; i < 56; i++) e = ecc_next(e, sb[s][i]);
            pk_sub[npk][s] = {e, sb[s]};
        end
        npk++;
    endtask

    // ---------------- audio source ----------------
    logic [47:0] src_q [$];       // {L, R} generated, not yet packed
    logic [35:0] exp_q [$];       // expected FIFO words
    longint      aacc = 0, n_gen = 0;
    always_ff @(posedge clk) begin
        if (!rst) begin
            aacc = aacc + N_ACR;
            if (aacc >= 128 * CTS) begin
                logic signed [23:0] l, r;
                aacc = aacc - 128 * CTS;
                l = $rtoi(AMP * 8388607.0 * $sin(2.0 * 3.14159265358979 * F_TONE * n_gen / FS_AUDIO));
                r = $rtoi(0.5 * 8388607.0 * $sin(2.0 * 3.14159265358979 * 3.0 * F_TONE * n_gen / FS_AUDIO));
                src_q.push_back({l, r});
                exp_q.push_back({l[23:6], r[23:6]});
                n_gen++;
            end
        end
    end

    // ---------------- word generator ----------------
    int h = 0, v = 0, frame = 0;
    logic [9:0] w0, w1, w2;
    int      inj_hdr = 0, inj_sub = 0;   // injected errors (expected counts)
    bit      inj_hdr_now, inj_sub_now;

    task automatic plan_line(input int vn, input int fr);
        logic [55:0] sb [0:3];
        npk = 0;
        inj_hdr_now = 0;
        inj_sub_now = 0;
        if (vn == 0) begin
            // AVI InfoFrame v2: RGB, Q = limited in frames 0..3, full after, VIC 4
            logic [7:0] pb [0:13];
            logic [7:0] sum;
            logic [23:0] hb;
            hb = {8'h0D, 8'h02, 8'h82};
            pb = '{default: 8'h00};
            pb[2] = 8'h08;
            pb[3] = (fr < 4) ? 8'h04 : 8'h08;
            pb[4] = 8'd4;
            sum = hb[7:0] + hb[15:8] + hb[23:16];
            for (int i = 1; i < 14; i++) sum += pb[i];
            pb[0] = -sum;
            for (int s = 0; s < 4; s++) sb[s] = '0;
            for (int i = 0; i < 7; i++) begin
                sb[0][i*8 +: 8] = pb[i];
                sb[1][i*8 +: 8] = pb[7 + i];
            end
            add_packet(hb, sb);
            inj_hdr_now = (fr == 2);         // one header bit error
        end
        if (vn % 16 == 3) begin
            for (int s = 0; s < 4; s++)
                sb[s] = {N_ACR[7:0], N_ACR[15:8], 4'h0, N_ACR[19:16], CTS[7:0], CTS[15:8], 4'h0, CTS[19:16], 8'h00};
            add_packet(24'h000001, sb);
            inj_sub_now = (fr == 3 && vn == 3);   // one subpacket bit error
        end
        if (src_q.size() > 0) begin
            logic [3:0] sp;
            sp = 0;
            for (int s = 0; s < 4; s++) begin
                sb[s] = '0;
                if (src_q.size() > 0) begin
                    logic [47:0] smp;
                    smp = src_q.pop_front();
                    sp[s] = 1;
                    sb[s] = {8'h00, smp[23:0], smp[47:24]};   // SB0-2 = L, SB3-5 = R
                end
            end
            add_packet({8'h00, 4'h0, sp, 8'h02}, sb);
        end
    endtask

    always_ff @(posedge clk) begin
        if (rst) begin
            h <= 0; v <= 0;
        end else begin
            if (h == H_TOTAL - 1) begin
                h <= 0;
                if (v == V_TOTAL - 1) begin v <= 0; frame <= frame + 1; end
                else v <= v + 1;
            end else h <= h + 1;
        end
    end

    always_comb begin
        automatic bit hs = h < H_SYNC, vs = v < V_SYNC;
        automatic bit act_line = v >= V_ACT0;
        automatic int isl_len = 8 + 2 + 32 * npk + 2;
        automatic int p = h - ISL0 - 10;          // payload word index in the island
        w0 = CTRL[{vs, hs}];
        w1 = CTRL[0];
        w2 = CTRL[0];
        if (act_line && h >= H_ACT0) begin
            w0 = enc0; w1 = enc1; w2 = enc2;
        end else if (act_line && h >= H_ACT0 - 2) begin
            w0 = GB_02; w1 = GB_1; w2 = GB_02;
        end else if (act_line && h >= H_ACT0 - 10) begin
            w1 = CTRL[1];                         // CTL0 = 1: video preamble
        end else if (npk > 0 && h >= ISL0 && h < ISL0 + isl_len) begin
            if (h < ISL0 + 8) begin
                w1 = CTRL[1]; w2 = CTRL[1];       // CTL0 = CTL2 = 1: island preamble
            end else if (p < 0 || p >= 32 * npk) begin
                w0 = TERC4[{2'b11, vs, hs}]; w1 = GB_1; w2 = GB_1;
            end else begin
                automatic int n = p / 32, k = p % 32;
                automatic logic [3:0] n1, n2, n0;
                n0 = {k != 0, pk_hdr[n][k], vs, hs};
                for (int s = 0; s < 4; s++) begin
                    n1[s] = pk_sub[n][s][2*k];
                    n2[s] = pk_sub[n][s][2*k+1];
                end
                if (inj_hdr_now && n == 0 && k == 5)  n0[2] = ~n0[2];
                if (inj_sub_now && pk_hdr[n][7:0] == 8'h01 && k == 9) n1[0] = ~n1[0];
                w0 = TERC4[n0]; w1 = TERC4[n1]; w2 = TERC4[n2];
            end
        end
    end
    // plan the island at the start of each line (after the previous
    // line's words are out)
    always_ff @(posedge clk) begin
        if (!rst && h == H_TOTAL - 1) begin
            if (v == V_TOTAL - 1) plan_line(0, frame + 1);
            else                  plan_line(v + 1, frame);
            if (inj_hdr_now) inj_hdr++;
            if (inj_sub_now) inj_sub++;
        end
    end

    // ---------------- DUT ----------------
    logic [9:0]  word [0:2];
    always_ff @(posedge clk) begin
        word[0] <= w0; word[1] <= w1; word[2] <= w2;
    end
    logic        locked, video_valid, video_de, video_hs, video_vs;
    logic [23:0] video_data;
    logic [3:0]  video_ctl;
    logic [2:0]  derr;
    logic        island, island_first;
    logic [11:0] terc4;
    logic [2:0]  terc4_err;
    dvi_in u_rx (
        .clock(clk), .reset(rst), .i_word_data(word), .i_word_valid(1'b1),
        .o_video_data(video_data), .o_video_de(video_de), .o_video_hsync(video_hs), .o_video_vsync(video_vs),
        .o_video_ctl(video_ctl), .o_video_valid(video_valid), .o_decode_err(derr),
        .o_island(island), .o_island_first(island_first), .o_terc4(terc4), .o_terc4_err(terc4_err),
        .o_locked(locked), .o_align_shift_req(), .o_delay_inc(), .o_delay_dec(), .o_delay_load(), .o_delay_tap());

    logic        pkt_valid, hb_ok, sym_err;
    logic [23:0] hb;
    logic [55:0] sb [0:3];
    logic [3:0]  sb_ok;
    hdmi_packet_rx u_pkt (
        .clk(clk), .rst(rst), .i_valid(video_valid), .i_island(island), .i_island_first(island_first),
        .i_terc4(terc4), .i_terc4_err(terc4_err),
        .o_pkt_valid(pkt_valid), .o_hb(hb), .o_sb(sb), .o_hb_ok(hb_ok), .o_sb_ok(sb_ok), .o_sym_err(sym_err));

    logic [3:0] div = 0;
    wire        out_en = div == DAC_DIV - 1;
    always_ff @(posedge clk) div <= out_en ? 4'd0 : div + 1'd1;

    logic signed [17:0] left, right;
    logic        avi_seen, limited, running, pop;
    logic [1:0]  avi_y, avi_q;
    logic [6:0]  avi_vic;
    logic [19:0] n_rx, cts_rx;
    logic [9:0]  level;
    logic [15:0] pkt_count;
    logic [7:0]  hdr_err, sub_err;
    logic [5:0]  underrun, overflow;
    logic [35:0] pop_data;
    hdmi_audio_rx u_audio (
        .clk(clk), .rst(rst), .i_locked(locked),
        .i_pkt_valid(pkt_valid), .i_hb(hb), .i_sb(sb), .i_hb_ok(hb_ok), .i_sb_ok(sb_ok),
        .i_out_en(out_en), .o_left(left), .o_right(right),
        .o_avi_seen(avi_seen), .o_avi_y(avi_y), .o_avi_q(avi_q), .o_avi_vic(avi_vic), .o_limited_range(limited),
        .o_n(n_rx), .o_cts(cts_rx), .o_running(running), .o_level(level), .o_pkt_count(pkt_count),
        .o_hdr_err(hdr_err), .o_sub_err(sub_err), .o_underrun(underrun), .o_overflow(overflow),
        .o_pop(pop), .o_pop_data(pop_data));

    logic dac_l, dac_r;
    delta_sigma_dac u_dac_l (.clk(clk), .rst(rst), .i_en(out_en), .i_x(left),  .o_dac(dac_l));
    delta_sigma_dac u_dac_r (.clk(clk), .rst(rst), .i_en(out_en), .i_x(right), .o_dac(dac_r));

    // ---------------- checks ----------------
    int errors = 0, pops = 0, sym_errs = 0;
    bit seen_limited = 0, seen_full = 0;
    always_ff @(posedge clk) begin
        if (pop) begin
            if (exp_q.size() == 0) begin
                errors++;
                $display("[tb_hdmi_audio] pop with no expected sample");
            end else begin
                automatic logic [35:0] e = exp_q.pop_front();
                if (pop_data !== e) begin
                    if (errors < 10) $display("[tb_hdmi_audio] sample %0d: got %09h expected %09h", pops, pop_data, e);
                    errors++;
                end
            end
            pops++;
        end
        if (pkt_valid && sym_err) sym_errs++;
        if (avi_seen && limited)  seen_limited = 1;
        if (avi_seen && !limited && seen_limited) seen_full = 1;
    end

    integer fd;
    int     nbits = 0;
    initial begin
        fd = $fopen("dac_left.txt", "w");
        repeat (20) @(posedge clk);
        rst = 0;
        wait (running);
        $display("[tb_hdmi_audio] playback started at %0t (level %0d, N %0d, CTS %0d)", $time, level, n_rx, cts_rx);
        while (nbits < DAC_SAMPLES) begin
            @(posedge clk);
            if (out_en) begin
                $fwrite(fd, "%0d\n", dac_l);
                nbits++;
            end
        end
        $fclose(fd);
        if (n_rx != N_ACR || cts_rx != CTS) begin
            errors++;
            $display("[tb_hdmi_audio] N / CTS = %0d / %0d", n_rx, cts_rx);
        end
        if (!seen_limited || !seen_full || avi_vic != 7'd4) begin
            errors++;
            $display("[tb_hdmi_audio] AVI: limited seen %0d, full seen %0d, VIC %0d", seen_limited, seen_full, avi_vic);
        end
        if (hdr_err != inj_hdr[7:0] || sub_err != inj_sub[7:0] || sym_errs != 0) begin
            errors++;
            $display("[tb_hdmi_audio] parity errors: header %0d (injected %0d), subpacket %0d (injected %0d), symbol %0d",
                     hdr_err, inj_hdr, sub_err, inj_sub, sym_errs);
        end
        if (underrun != 0 || overflow != 0) begin
            errors++;
            $display("[tb_hdmi_audio] underrun %0d overflow %0d", underrun, overflow);
        end
        if (pops < 1000) begin
            errors++;
            $display("[tb_hdmi_audio] only %0d samples played", pops);
        end
        $display("[tb_hdmi_audio] %0d packets, %0d samples played (all matched: %0d), FIFO level %0d, DAC bits %0d",
                 pkt_count, pops, errors == 0, level, nbits);
        if (errors != 0) $fatal(1, "[tb_hdmi_audio] FAIL (%0d errors)", errors);
        $display("[tb_hdmi_audio] PASS");
        $finish;
    end
endmodule
`default_nettype wire
