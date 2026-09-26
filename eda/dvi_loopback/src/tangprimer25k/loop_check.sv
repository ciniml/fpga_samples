// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file loop_check.sv
 * @brief Receive-side checker for the DVI loopback, plus its clock
 *        domain crossings.
 *
 *   RX domain (recovered pixel clock):
 *     - frame_sum over the decoded video, compared frame by frame with
 *       the transmitter's sum of the same (static) picture
 *     - counters: frames compared, frames mismatched, clocks with a
 *       decode error, word-lock losses.
 *     - pixel check: the expected pixel is regenerated from the received
 *       DE (x counts DE pixels, y counts lines since VSYNC) with the same
 *       function as loop_pattern, so every active pixel is compared.
 *       Counts wrong pixels and wrong bits (popcount of the XOR); bit
 *       errors / (pixels x 24) is the BER. Not reset by rx_reset (which
 *       follows the recovery PLL, i.e. the cable), only by a clear
 *       request, so a cable glitch stays visible in the counts.
 *
 *   Crossings (all quasi-static or toggle handshakes):
 *     - TX reference sums -> RX: 2FF per bit. The value is rewritten
 *       with the same contents every frame; the valid flag goes through
 *       extra stages so it arrives after the data has settled.
 *     - snapshot: sys toggles req, RX copies the counters and toggles
 *       ack, sys copies the (now static) RX copy. If the RX clock is
 *       absent the ack never comes; the sys side times out.
 *     - clear: sys toggle -> RX edge.
 *     - IODELAY offset: sys register -> 2FF, taken when two consecutive
 *       samples agree.
 */
`default_nettype none
module loop_check (
    // ---- RX domain ----
    input  wire         rx_clk,
    input  wire         rx_reset,
    input  wire  [23:0] i_video_data,
    input  wire         i_video_de,
    input  wire         i_video_vsync,
    input  wire         i_video_valid,
    input  wire  [2:0]  i_decode_err,
    input  wire         i_locked,
    input  wire  [9:0]  i_word0,          // raw deserializer words (diagnostics)
    input  wire  [9:0]  i_word1,
    input  wire  [9:0]  i_word2,
    output logic [7:0]  o_rx_offset,
    output logic [7:0]  o_rx_lane_offset [0:2],
    output logic        o_frame_bad,      // one clock per mismatched frame

    // ---- TX domain (quasi-static) ----
    input  wire  [31:0] i_tx_s1,
    input  wire  [31:0] i_tx_s2,
    input  wire  [31:0] i_tx_count,
    input  wire         i_tx_ref_valid,

    // ---- sys domain ----
    input  wire         sys_clk,
    input  wire         sys_snap_req,     // pulse
    output logic        sys_snap_done,    // pulse; fields below valid
    output logic        sys_locked,
    output logic [31:0] sys_frames,
    output logic [31:0] sys_bad,
    output logic [31:0] sys_derr,
    output logic [15:0] sys_unlock,
    output logic [31:0] sys_last_count,
    output logic [31:0] sys_rx_cycles,    // free-running RX clock count (frequency check)
    output logic [31:0] sys_pix_err,      // active pixels that differ from the pattern
    output logic [31:0] sys_bit_err,      // wrong bits in those pixels
    output logic [31:0] sys_lane_bit_err [0:2], // wrong bits per lane (0 = B, 1 = G, 2 = R)
    output logic [23:0] sys_lane_err [0:2], // decode errors per lane (low 24 bits)
    input  wire         sys_clear,        // pulse
    // Raw word capture: 12 consecutive words of each lane, starting at the
    // first lane-0 control symbol (or after ~7 ms without one).
    input  wire         sys_words_req,    // pulse
    output logic        sys_words_done,   // pulse; sys_words valid
    output logic [9:0]  sys_words [0:2][0:11],
    input  wire  [7:0]  sys_offset,
    input  wire  [7:0]  sys_lane_offset [0:2]
);
    // =================================================================
    // TX reference into the RX domain
    // =================================================================
    logic [95:0] tx_ref_s0 = '0, tx_ref_s1 = '0;
    logic [3:0]  tx_valid_sr = '0;
    always_ff @(posedge rx_clk) begin
        tx_ref_s0   <= {i_tx_s1, i_tx_s2, i_tx_count};
        tx_ref_s1   <= tx_ref_s0;
        tx_valid_sr <= {tx_valid_sr[2:0], i_tx_ref_valid};
    end
    wire tx_ref_ok = tx_valid_sr[3];

    // =================================================================
    // RX sums and counters
    // =================================================================
    logic [31:0] rx_s1, rx_s2, rx_count;
    logic        rx_complete, rx_stb;
    frame_sum u_rx_sum (
        .clock     (rx_clk),
        .reset     (rx_reset),
        .i_valid   (i_video_valid),
        .i_data    (i_video_data),
        .i_de      (i_video_de),
        .i_vsync   (i_video_vsync),
        .o_s1      (rx_s1),
        .o_s2      (rx_s2),
        .o_count   (rx_count),
        .o_complete(rx_complete),
        .o_stb     (rx_stb)
    );

    // sys -> RX control
    logic       clear_t = 1'b0;                 // sys domain
    logic [2:0] clear_sync = '0;                // RX domain
    logic       snap_req_t = 1'b0;              // sys domain
    logic [2:0] snap_req_sync = '0;             // RX domain
    logic       snap_ack_t = 1'b0;              // RX domain
    logic [7:0] ofs_s0 = '0, ofs_s1 = '0;
    logic [23:0] lofs_s0 = '0, lofs_s1 = '0;

    always_ff @(posedge rx_clk) begin
        clear_sync    <= {clear_sync[1:0], clear_t};
        snap_req_sync <= {snap_req_sync[1:0], snap_req_t};
        ofs_s0        <= sys_offset;
        ofs_s1        <= ofs_s0;
        if (ofs_s0 == ofs_s1) o_rx_offset <= ofs_s1;
        lofs_s0 <= {sys_lane_offset[2], sys_lane_offset[1], sys_lane_offset[0]};
        lofs_s1 <= lofs_s0;
        if (lofs_s0 == lofs_s1) {o_rx_lane_offset[2], o_rx_lane_offset[1], o_rx_lane_offset[0]} <= lofs_s1;
    end
    wire rx_clear = clear_sync[2] != clear_sync[1];

    logic [31:0] frames     = '0;
    logic [31:0] bad        = '0;
    logic [31:0] derr       = '0;
    logic [15:0] unlock     = '0;
    logic [31:0] last_count = '0;
    logic [23:0] lane_err [0:2] = '{default: '0};

    // -----------------------------------------------------------------
    // Pixel check against the regenerated pattern (see loop_pattern.sv)
    // -----------------------------------------------------------------
    logic [11:0] px_x = '0, px_y = '0;
    logic        px_de_q = 1'b0, px_vs_q = 1'b0;
    logic        px_armed = 1'b0;   // a VSYNC edge was seen while valid: y is meaningful
    logic        px_cmp = 1'b0, px_cmp_q = 1'b0;
    logic [23:0] px_got = '0, px_exp = '0, px_diff = '0;
    logic [4:0]  px_bits = '0;
    logic [3:0]  px_lbits [0:2] = '{default: '0};
    logic [31:0] lane_bit_err [0:2] = '{default: '0};
    function automatic logic [3:0] popcount8(input logic [7:0] v);
        logic [3:0] n;
        n = '0;
        for (int i = 0; i < 8; i++) n += 4'(v[i]);
        return n;
    endfunction
    logic        px_bad_q = 1'b0;
    logic [31:0] pix_err = '0, bit_err = '0;
    function automatic logic [4:0] popcount24(input logic [23:0] v);
        logic [4:0] n;
        n = '0;
        for (int i = 0; i < 24; i++) n += 5'(v[i]);
        return n;
    endfunction
    always_ff @(posedge rx_clk) begin
        // stage 0: coordinates of the current pixel
        px_de_q <= i_video_valid && i_video_de;
        px_vs_q <= i_video_valid && i_video_vsync;
        if (!i_video_valid) begin
            px_armed <= 1'b0;
        end else if (i_video_vsync && !px_vs_q) begin
            px_armed <= 1'b1;
        end
        if (i_video_valid && i_video_vsync && !px_vs_q) begin
            px_y <= '0;
        end else if (px_de_q && !(i_video_valid && i_video_de)) begin
            px_y <= px_y + 1'd1;
        end
        if (i_video_valid && i_video_de) px_x <= px_x + 1'd1;
        else                             px_x <= '0;
        px_cmp <= i_video_valid && i_video_de && px_armed;
        px_got <= i_video_data;
        px_exp <= {px_x[7:0] ^ px_y[7:0],
                   px_x[10:3] + px_y[7:0],
                   px_x[8:1] ^ {px_y[3:0], px_y[7:4]}};
        // stage 1: difference
        px_cmp_q <= px_cmp;
        px_diff  <= px_cmp ? (px_got ^ px_exp) : '0;
        // stage 2: popcount
        px_bits  <= popcount24(px_diff);
        for (int l = 0; l < 3; l++) px_lbits[l] <= popcount8(px_diff[l * 8 +: 8]);
        px_bad_q <= px_cmp_q && px_diff != '0;
    end
    logic        locked_q   = 1'b0;

    // The frame_sum outputs hold until the next frame: compare the three
    // words in the clock after the strobe, count in the one after that.
    logic       cmp_stb = 1'b0, cmp_stb_q = 1'b0;
    logic [2:0] cmp_eq  = '0;
    always_ff @(posedge rx_clk) begin
        cmp_stb   <= rx_stb && rx_complete && tx_ref_ok;
        cmp_eq    <= {rx_s1 == tx_ref_s1[95:64], rx_s2 == tx_ref_s1[63:32], rx_count == tx_ref_s1[31:0]};
        cmp_stb_q <= cmp_stb;
    end

    always_ff @(posedge rx_clk) begin
        o_frame_bad <= 1'b0;
        locked_q    <= i_locked;
        if (rx_clear) begin
            frames     <= '0;
            bad        <= '0;
            derr       <= '0;
            unlock     <= '0;
            lane_err   <= '{default: '0};
            pix_err    <= '0;
            bit_err    <= '0;
            lane_bit_err <= '{default: '0};
        end else begin
            if (cmp_stb_q) begin
                frames     <= frames + 1'd1;
                last_count <= rx_count;
                if (cmp_eq != 3'b111) begin
                    bad         <= bad + 1'd1;
                    o_frame_bad <= 1'b1;
                end
            end
            if (i_video_valid && |i_decode_err) derr <= derr + 1'd1;
            for (int l = 0; l < 3; l++) begin
                if (i_video_valid && i_decode_err[l]) lane_err[l] <= lane_err[l] + 1'd1;
            end
            // stage 3: accumulate
            if (px_bad_q) begin
                pix_err <= pix_err + 1'd1;
                bit_err <= bit_err + 32'(px_bits);
                for (int l = 0; l < 3; l++) lane_bit_err[l] <= lane_bit_err[l] + 32'(px_lbits[l]);
            end
            if (locked_q && !i_locked && unlock != '1) unlock <= unlock + 1'd1;
        end
    end

    // Snapshot copy, RX side
    logic [144:0] rx_snap = '0;
    logic [23:0]  rx_snap_lane [0:2] = '{default: '0};
    logic [31:0]  rx_cycles = '0;
    logic [31:0]  rx_snap_cycles = '0;
    logic [63:0]  rx_snap_px = '0;
    logic [31:0]  rx_snap_lbits [0:2] = '{default: '0};
    always_ff @(posedge rx_clk) begin
        if (snap_req_sync[2] != snap_req_sync[1]) begin
            rx_snap      <= {i_locked, frames, bad, derr, unlock, last_count};
            rx_snap_lane   <= lane_err;
            rx_snap_cycles <= rx_cycles;
            rx_snap_px     <= {pix_err, bit_err};
            rx_snap_lbits  <= lane_bit_err;
            snap_ack_t     <= ~snap_ack_t;
        end
    end
    always_ff @(posedge rx_clk) rx_cycles <= rx_cycles + 1'd1;

    // Raw word capture, RX side
    logic       words_req_t = 1'b0;             // sys domain
    logic [2:0] words_req_sync = '0;            // RX domain
    logic       words_ack_t = 1'b0;             // RX domain
    logic       words_armed = 1'b0;
    logic [3:0] words_n = '0;                   // words still to capture
    logic [19:0] words_wait = '0;
    logic [9:0] rx_words [0:2][0:11];
    wire w0_is_ctrl = i_word0 == 10'b1101010100 || i_word0 == 10'b0010101011
                   || i_word0 == 10'b0101010100 || i_word0 == 10'b1010101011;
    always_ff @(posedge rx_clk) begin
        words_req_sync <= {words_req_sync[1:0], words_req_t};
        if (words_req_sync[2] != words_req_sync[1]) begin
            words_armed <= 1'b1;
            words_wait  <= '0;
        end else if (words_armed && (w0_is_ctrl || &words_wait)) begin
            words_armed <= 1'b0;
            words_n     <= 4'd11;     // this word + 11 more
        end else if (words_armed) begin
            words_wait <= words_wait + 1'd1;
        end
        if (words_n != 0 || (words_armed && (w0_is_ctrl || &words_wait))) begin
            for (int l = 0; l < 3; l++) begin
                for (int k = 0; k < 11; k++) rx_words[l][k] <= rx_words[l][k + 1];
            end
            rx_words[0][11] <= i_word0;
            rx_words[1][11] <= i_word1;
            rx_words[2][11] <= i_word2;
        end
        if (words_n != 0) begin
            words_n <= words_n - 1'd1;
            if (words_n == 4'd1) words_ack_t <= ~words_ack_t;  // last word enters now
        end
    end

    // =================================================================
    // sys side
    // =================================================================
    logic [2:0] snap_ack_sync = '0;
    always_ff @(posedge sys_clk) begin
        snap_ack_sync <= {snap_ack_sync[1:0], snap_ack_t};
        sys_snap_done <= 1'b0;
        if (sys_snap_req) snap_req_t <= ~snap_req_t;
        if (sys_clear)    clear_t    <= ~clear_t;
        if (snap_ack_sync[2] != snap_ack_sync[1]) begin
            {sys_locked, sys_frames, sys_bad, sys_derr, sys_unlock, sys_last_count} <= rx_snap;
            sys_lane_err  <= rx_snap_lane;
            sys_rx_cycles <= rx_snap_cycles;
            {sys_pix_err, sys_bit_err} <= rx_snap_px;
            sys_lane_bit_err <= rx_snap_lbits;
            sys_snap_done <= 1'b1;
        end
    end

    logic [2:0] words_ack_sync = '0;
    always_ff @(posedge sys_clk) begin
        words_ack_sync <= {words_ack_sync[1:0], words_ack_t};
        sys_words_done <= 1'b0;
        if (sys_words_req) words_req_t <= ~words_req_t;
        if (words_ack_sync[2] != words_ack_sync[1]) begin
            sys_words      <= rx_words;
            sys_words_done <= 1'b1;
        end
    end
endmodule
`default_nettype wire
