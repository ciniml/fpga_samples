// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file tb_loop.sv
 * @brief Logic-level test of the DVI loopback checker and reporter.
 *
 *   loop_pattern -> dvi_out -> 10-bit words (bit-slip model, starts
 *   3 bits off) -> dvi_in -> loop_check -> loop_report -> UART, decoded
 *   here. Small raster and short report timings; the PHY (OSER10, IDES10,
 *   IODELAY, PLLs) is not modelled.
 *
 *   1. lock, cumulative "R" line: L1, frames counted, B0, E0, N = pixels
 *   2. one flipped bit in an active pixel -> exactly one mismatched frame
 *   3. "c" clears the counters, "+" moves the offset
 *   4. "s" prints 64 "S" lines (offsets 00..FC) and restores the offset
 *   5. RX clock stopped -> "X" (snapshot timeout), recovers when restarted
 */
`timescale 1ns/1ps
`default_nettype none
module tb_loop;
    // Small raster: 84 x 40 total, 64 x 32 active (0x800 pixels)
    localparam int HSYNC = 4, HBACK = 8, HACTIVE = 64, HFRONT = 8;
    localparam int VSYNC = 2, VBACK = 4, VACTIVE = 32, VFRONT = 2;
    localparam int BAUD = 8;

    logic tx_clk = 0, rx_clk = 0, sys_clk = 0;
    logic rx_clk_en = 1;
    always #3.4 tx_clk = ~tx_clk;
    initial begin
        #2;
        forever begin
            #3.4;
            if (rx_clk_en) rx_clk = ~rx_clk;
        end
    end
    always #10 sys_clk = ~sys_clk;

    logic reset = 1;
    logic rx_reset = 1;   // board: follows the recovery PLL lock

    // ---------------- TX ----------------
    logic [23:0] tx_data;
    logic        tx_de, tx_hs, tx_vs;
    loop_pattern #(
        .HSYNC(HSYNC), .HBACK(HBACK), .HACTIVE(HACTIVE), .HFRONT(HFRONT),
        .VSYNC(VSYNC), .VBACK(VBACK), .VACTIVE(VACTIVE), .VFRONT(VFRONT)
    ) u_pattern (
        .clock(tx_clk), .reset(reset),
        .video_data(tx_data), .video_de(tx_de), .video_hsync(tx_hs), .video_vsync(tx_vs)
    );

    logic [9:0] w_clk, w0, w1, w2;
    dvi_out u_dvi_out (
        .clock(tx_clk), .reset(reset),
        .video_data(tx_data), .video_de(tx_de), .video_hsync(tx_hs), .video_vsync(tx_vs),
        .dvi_clock(w_clk), .dvi_data0(w0), .dvi_data1(w1), .dvi_data2(w2)
    );

    logic [31:0] tx_s1, tx_s2, tx_count, ref_s1, ref_s2, ref_count;
    logic        tx_complete, tx_stb, ref_valid = 0;
    frame_sum u_tx_sum (
        .clock(tx_clk), .reset(reset), .i_valid(1'b1),
        .i_data(tx_data), .i_de(tx_de), .i_vsync(tx_vs),
        .o_s1(tx_s1), .o_s2(tx_s2), .o_count(tx_count), .o_complete(tx_complete), .o_stb(tx_stb)
    );
    always_ff @(posedge tx_clk) begin
        if (tx_stb && tx_complete) begin
            ref_s1 <= tx_s1; ref_s2 <= tx_s2; ref_count <= tx_count; ref_valid <= 1;
        end
    end

    // ---------------- link (bit-slip model + error injection) ----------------
    function automatic logic [9:0] rot(input logic [9:0] w, input logic [3:0] sh);
        logic [19:0] d;
        d = {w, w};
        return d[sh +: 10];
    endfunction

    logic [3:0] slip = 4'd3;
    logic       shift_req;
    logic       inject = 0;     // flip bit 4 of lane 1 on the next active word
    logic       injected = 0;
    logic [9:0] rx_w [0:2];
    // Pattern DE leads the TMDS words by the encoder latency: only inject
    // once DE has been high for a while, i.e. in the middle of a line.
    int de_run = 0;
    always_ff @(posedge tx_clk) de_run <= u_pattern.video_de ? de_run + 1 : 0;
    always_ff @(posedge rx_clk) begin
        if (shift_req) slip <= (slip == 4'd9) ? 4'd0 : slip + 4'd1;
        rx_w[0] <= rot(w0, slip);
        rx_w[2] <= rot(w2, slip);
        if (inject && !injected && de_run >= 16) begin
            rx_w[1]  <= rot(w1 ^ 10'b0000010000, slip);
            injected <= 1;
        end else begin
            rx_w[1] <= rot(w1, slip);
        end
    end

    // ---------------- RX ----------------
    logic [23:0] rx_data;
    logic        rx_de, rx_hs, rx_vs, rx_valid, rx_locked;
    logic [3:0]  rx_ctl;
    logic [2:0]  rx_err;
    dvi_in u_dvi_in (
        .clock(rx_clk), .reset(rx_reset),
        .i_word_data(rx_w), .i_word_valid(1'b1),
        .o_video_data(rx_data), .o_video_de(rx_de), .o_video_hsync(rx_hs), .o_video_vsync(rx_vs),
        .o_video_ctl(rx_ctl), .o_video_valid(rx_valid), .o_decode_err(rx_err),
        .o_locked(rx_locked), .o_align_shift_req(shift_req),
        .o_delay_inc(), .o_delay_dec(), .o_delay_load(), .o_delay_tap()
    );

    logic        snap_req, snap_done, snap_locked, clear_req, frame_bad;
    logic [31:0] snap_frames, snap_bad, snap_derr, snap_count;
    logic [15:0] snap_unlock;
    logic [7:0]  sys_offset, rx_offset;
    logic [23:0] lane_err [0:2];
    logic [31:0] rx_cycles, pix_err, bit_err;
    logic        words_req, words_done;
    logic [9:0]  words [0:2][0:11];
    loop_check u_check (
        .rx_clk(rx_clk), .rx_reset(rx_reset),
        .i_video_data(rx_data), .i_video_de(rx_de), .i_video_vsync(rx_vs), .i_video_valid(rx_valid),
        .i_decode_err(rx_err), .i_locked(rx_locked),
        .i_word0(rx_w[0]), .i_word1(rx_w[1]), .i_word2(rx_w[2]), .o_rx_offset(rx_offset), .o_frame_bad(frame_bad),
        .i_tx_s1(ref_s1), .i_tx_s2(ref_s2), .i_tx_count(ref_count), .i_tx_ref_valid(ref_valid),
        .sys_clk(sys_clk), .sys_snap_req(snap_req), .sys_snap_done(snap_done),
        .sys_locked(snap_locked), .sys_frames(snap_frames), .sys_bad(snap_bad), .sys_derr(snap_derr),
        .sys_unlock(snap_unlock), .sys_last_count(snap_count), .sys_lane_err(lane_err), .sys_rx_cycles(rx_cycles), .sys_pix_err(pix_err), .sys_bit_err(bit_err), .sys_clear(clear_req),
        .sys_words_req(words_req), .sys_words_done(words_done), .sys_words(words), .sys_offset(sys_offset)
    );

    logic uart_to_dut = 1, uart_from_dut;
    loop_report #(
        .BAUD_DIVIDER(BAUD), .PERIOD_CYCLES(40_000), .SETTLE_CYCLES(2_000),
        .DWELL_CYCLES(10_000), .SNAP_TIMEOUT(1_000)
    ) u_report (
        .clock(sys_clk), .reset(reset), .uart_rxd(uart_to_dut), .uart_txd(uart_from_dut),
        .o_offset(sys_offset), .o_snap_req(snap_req), .i_snap_done(snap_done), .i_locked(snap_locked),
        .i_frames(snap_frames), .i_bad(snap_bad), .i_derr(snap_derr), .i_unlock(snap_unlock),
        .i_last_count(snap_count), .i_lane_err(lane_err), .i_rx_cycles(rx_cycles), .i_pix_err(pix_err), .i_bit_err(bit_err), .i_pll_lock(1'b1), .o_clear(clear_req),
        .o_words_req(words_req), .i_words_done(words_done), .i_words(words)
    );

    // ---------------- UART decode / encode ----------------
    string lines[$];
    string cur = "";
    initial begin
        forever begin
            logic [7:0] c;
            @(negedge uart_from_dut);
            repeat (BAUD / 2) @(posedge sys_clk);
            for (int i = 0; i < 8; i++) begin
                repeat (BAUD) @(posedge sys_clk);
                c[i] = uart_from_dut;
            end
            repeat (BAUD) @(posedge sys_clk);
            if (c == 8'h0A) begin
                lines.push_back(cur);
                $display("[uart] %s", cur);
                cur = "";
            end else if (c != 8'h0D) begin
                cur = {cur, string'(c)};
            end
        end
    end

    task automatic send_char(input logic [7:0] c);
        uart_to_dut = 0;
        repeat (BAUD) @(posedge sys_clk);
        for (int i = 0; i < 8; i++) begin
            uart_to_dut = c[i];
            repeat (BAUD) @(posedge sys_clk);
        end
        uart_to_dut = 1;
        repeat (BAUD * 2) @(posedge sys_clk);
    endtask

    // Parsed fields of a line: K L F B E U N O
    typedef struct {
        byte  kind;
        byte  lock;
        int unsigned f, b, e, e0, e1, e2, u, n, o, x, y;
    } rep_t;

    function automatic int unsigned hexval(input string s);
        int unsigned v = 0;
        for (int i = 0; i < s.len(); i++) begin
            byte ch = s[i];
            v = v * 16 + ((ch >= "0" && ch <= "9") ? ch - "0" : ch - "A" + 10);
        end
        return v;
    endfunction

    function automatic rep_t parse(input string s);
        rep_t r;
        r.kind = s[0];
        r.lock = s[3];
        r.f = hexval(s.substr(6, 13));
        r.b = hexval(s.substr(16, 23));
        r.e = hexval(s.substr(26, 33));
        if (r.kind == "W") return r;
        r.e0 = hexval(s.substr(37, 42));
        r.e1 = hexval(s.substr(46, 51));
        r.e2 = hexval(s.substr(55, 60));
        r.u = hexval(s.substr(63, 66));
        r.n = hexval(s.substr(69, 76));
        r.o = hexval(s.substr(79, 80));
        r.x = hexval(s.substr(96, 103));
        r.y = hexval(s.substr(106, 113));
        return r;
    endfunction

    task automatic next_raw(output string l);
        while (lines.size() == 0) @(posedge sys_clk);
        l = lines.pop_front();
    endtask

    task automatic next_line(output rep_t r);
        while (lines.size() == 0) @(posedge sys_clk);
        r = parse(lines.pop_front());
    endtask

    int errors = 0;
    task automatic check(input bit cond, input string what);
        if (!cond) begin
            errors++;
            $display("[tb_loop] FAIL: %s", what);
        end
    endtask

    // ---------------- sequence ----------------
    initial begin
        rep_t r;
        int unsigned prev_f;
        repeat (20) @(posedge sys_clk);
        reset = 0;
        rx_reset = 0;

        // 1. lock and count
        do next_line(r); while (!(r.kind == "R" && r.lock == "1" && r.f >= 3));
        check(r.b == 0 && r.e == 0 && r.x == 0 && r.y == 0, $sformatf("clean frames after lock (X=%0d Y=%0d)", r.x, r.y));
        check(r.n == HACTIVE * VACTIVE, $sformatf("pixel count %0d", r.n));
        check(r.o == 8'h20, "default offset 0x20");
        check(slip == 0, $sformatf("bit slip converged to 0 (is %0d)", slip));

        // 2. single-bit error in one active pixel
        @(posedge rx_clk) inject = 1;
        next_line(r);
        next_line(r);
        check(r.kind == "R" && r.b == 1, $sformatf("one mismatched frame after injection (B=%0d)", r.b));
        check(r.x == 1 && r.y >= 1, $sformatf("one wrong pixel after injection (X=%0d Y=%0d)", r.x, r.y));
        check(r.lock == "1" && r.u == 0, "still locked after a data error");

        // 3. clear, offset +4
        prev_f = r.f;
        send_char("c");
        send_char("+");
        next_line(r);
        next_line(r);
        check(r.b == 0 && r.f < prev_f, $sformatf("counters cleared (F=%0d B=%0d)", r.f, r.b));
        check(r.o == 8'h24, $sformatf("offset after + is %02h", r.o));

        // 4. scan
        send_char("s");
        for (int i = 0; i < 64; i++) begin
            do next_line(r); while (r.kind == "R");
            check(r.kind == "S" && r.o == i * 4, $sformatf("scan line %0d offset %02h", i, r.o));
            check(r.lock == "1" && r.f > 0 && r.b == 0 && r.e == 0, $sformatf("scan line %0d counts", i));
        end
        next_line(r);
        check(r.kind == "R" && r.o == 8'h24, $sformatf("offset restored after scan (%02h)", r.o));

        // 4b. raw words: 3 lines, lane 0 starts with a control symbol
        begin
            string l;
            send_char("w");
            do next_raw(l); while (l[0] != "W");
            check(l.substr(0, 1) == "W0", $sformatf("W line order (%s)", l));
            check(l.substr(3, 5) == "354" || l.substr(3, 5) == "0AB" || l.substr(3, 5) == "154" || l.substr(3, 5) == "2AB",
                  $sformatf("W0 starts with a control symbol (%s)", l));
            check(l.len() == 51, $sformatf("W line length %0d", l.len()));
            next_raw(l); check(l.substr(0, 1) == "W1", "W1 line");
            next_raw(l); check(l.substr(0, 1) == "W2", "W2 line");
        end

        // 5. RX clock absent -> X, then recovery
        prev_f = r.b;
        rx_clk_en = 0;
        rx_reset  = 1;
        do next_line(r); while (r.lock != "X");
        rx_clk_en = 1;
        repeat (8) @(posedge rx_clk);
        rx_reset = 0;
        do next_line(r); while (!(r.lock == "1" && r.f > 0));
        next_line(r);
        check(r.kind == "R" && r.lock == "1", "recovered after RX clock restart");
        check(r.b == prev_f && r.u == 1, $sformatf("no bad frame across the clock loss, one unlock (B=%0d U=%0d)", r.b, r.u));

        if (errors != 0) $fatal(1, "[tb_loop] %0d errors", errors);
        $display("[tb_loop] PASS");
        $finish;
    end

    initial begin
        #100_000_000;
        $fatal(1, "[tb_loop] timeout");
    end
endmodule
`default_nettype wire
