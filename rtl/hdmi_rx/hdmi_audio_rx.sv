// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file hdmi_audio_rx.sv
 * @brief HDMI audio (2ch LPCM) and AVI InfoFrame from hdmi_packet_rx.
 *
 * Packets used (header and subpacket parity must check):
 *   0x01 Audio Clock Regeneration: N, CTS (subpacket 0)
 *   0x02 Audio Sample, layout 0: up to 4 stereo samples, 24 bit each
 *   0x82 AVI InfoFrame: colour space, RGB quantization range, VIC
 *
 * Playback rate: fs = f_TMDS * N / (128 * CTS). A 40-bit NCO in the pixel
 * clock domain adds P = 2^33 * N / CTS per clock (P is recomputed by a
 * serial divider whenever N / CTS change) and pops one sample from the
 * FIFO per wrap, so the output follows the source's audio clock without
 * a local audio PLL. Between two samples the output is linearly
 * interpolated with the NCO phase at each i_out_en: holding samples would
 * quantize the sample instants to the DAC update period (161 ns at
 * 6.19 MHz), a jitter that limits a 10 kHz tone to ~50 dB SNR.
 *
 * FIFO: 2^FIFO_BITS x {L[23:6], R[23:6]} (one BSRAM at 512 x 36).
 * Playback starts once it holds START_LEVEL samples and re-primes (output
 * 0) after an underrun; samples arriving while it is full are dropped.
 */
`default_nettype none
module hdmi_audio_rx #(
    parameter int FIFO_BITS   = 9,
    parameter int START_LEVEL = 256
) (
    input  wire               clk,              // pixel (TMDS character) clock
    input  wire               rst,
    input  wire               i_locked,         // flush and mute while unlocked

    input  wire               i_pkt_valid,
    input  wire  [23:0]       i_hb,
    input  wire  [55:0]       i_sb [0:3],
    input  wire               i_hb_ok,
    input  wire  [3:0]        i_sb_ok,

    // Interpolated samples, updated on each i_out_en
    input  wire               i_out_en,
    output logic signed [17:0] o_left,
    output logic signed [17:0] o_right,

    // AVI InfoFrame
    output logic              o_avi_seen,
    output logic [1:0]        o_avi_y,          // colour space (0 = RGB)
    output logic [1:0]        o_avi_q,          // RGB quantization range (0 default, 1 limited, 2 full)
    output logic [6:0]        o_avi_vic,
    output logic              o_limited_range,  // RGB with limited (16-235) range

    // Status
    output logic [19:0]       o_n,
    output logic [19:0]       o_cts,
    output logic              o_running,
    output logic [FIFO_BITS:0] o_level,
    output logic [15:0]       o_pkt_count,
    output logic [7:0]        o_hdr_err,        // packets with a bad header
    output logic [7:0]        o_sub_err,        // audio / ACR / AVI packets with a bad subpacket
    output logic [5:0]        o_underrun,
    output logic [5:0]        o_overflow,

    // Debug: every sample taken from the FIFO
    output logic              o_pop,
    output logic [35:0]       o_pop_data
);
    // =================================================================
    // Packet parsing
    // =================================================================
    wire [7:0] hb0 = i_hb[7:0];
    wire [7:0] hb1 = i_hb[15:8];
    wire [7:0] hb2 = i_hb[23:16];
    // subpacket bytes SB0..SB6
    logic [7:0] sb0 [0:6];
    logic [7:0] sb1 [0:6];
    always_comb for (int n = 0; n < 7; n++) begin
        sb0[n] = i_sb[0][n*8 +: 8];
        sb1[n] = i_sb[1][n*8 +: 8];
    end

    // AVI checksum: HB0..HB2 + PB0..PB13 (subpackets 0 and 1) == 0
    logic [7:0] avi_sum;
    always_comb begin
        avi_sum = hb0 + hb1 + hb2;
        for (int n = 0; n < 7; n++) avi_sum = avi_sum + sb0[n] + sb1[n];
    end

    logic [3:0]  push_mask;     // samples of the last audio packet still to be written
    logic [3:0]  push_flat;
    logic [35:0] push_word [0:3];

    always_ff @(posedge clk) begin
        if (rst) begin
            o_avi_seen  <= 1'b0;
            o_avi_y     <= '0;
            o_avi_q     <= '0;
            o_avi_vic   <= '0;
            o_n         <= '0;
            o_cts       <= '0;
            o_pkt_count <= '0;
            o_hdr_err   <= '0;
            o_sub_err   <= '0;
        end else if (i_pkt_valid) begin
            o_pkt_count <= o_pkt_count + 1'd1;
            if (!i_hb_ok) begin
                o_hdr_err <= o_hdr_err + 1'd1;
            end else begin
                case (hb0)
                    8'h01: if (i_sb_ok[0]) begin
                        o_cts <= {sb0[1][3:0], sb0[2], sb0[3]};
                        o_n   <= {sb0[4][3:0], sb0[5], sb0[6]};
                    end else o_sub_err <= o_sub_err + 1'd1;
                    8'h02: if ((i_sb_ok | ~hb1[3:0]) != 4'hF) o_sub_err <= o_sub_err + 1'd1;
                    8'h82: if (i_sb_ok[1:0] == 2'b11 && avi_sum == 8'd0) begin
                        o_avi_seen <= 1'b1;
                        o_avi_y    <= sb0[1][6:5];
                        o_avi_q    <= sb0[3][3:2];
                        o_avi_vic  <= sb0[4][6:0];
                    end else o_sub_err <= o_sub_err + 1'd1;
                    default: ;
                endcase
            end
        end
    end
    // RGB, and Q = limited, or Q = default with a CE format (VIC != 0)
    assign o_limited_range = o_avi_seen && o_avi_y == 2'd0
                          && (o_avi_q == 2'd1 || (o_avi_q == 2'd0 && o_avi_vic != 7'd0));

    // =================================================================
    // Sample FIFO
    // =================================================================
    localparam int DEPTH = 1 << FIFO_BITS;
    (* syn_ramstyle = "block_ram" *) logic [35:0] mem [0:DEPTH-1];
    logic [FIFO_BITS:0] wr_ptr, rd_ptr;
    wire  [FIFO_BITS:0] level = wr_ptr - rd_ptr;
    wire                full  = level == DEPTH[FIFO_BITS:0];
    assign o_level = level;

    // pick the lowest pending sample of the packet (one write per clock;
    // packets are 32 clocks apart)
    logic [1:0] push_idx;
    always_comb begin
        push_idx = 2'd0;
        for (int i = 3; i >= 0; i--) if (push_mask[i]) push_idx = 2'(i);
    end
    wire        push      = |push_mask;
    wire [35:0] push_data = push_flat[push_idx] ? 36'd0 : push_word[push_idx];

    logic pop;
    wire  mem_we = !rst && i_locked && push && !full;
    always_ff @(posedge clk) if (mem_we) mem[wr_ptr[FIFO_BITS-1:0]] <= push_data;
    always_ff @(posedge clk) begin
        if (rst || !i_locked) begin
            push_mask  <= '0;
            wr_ptr     <= '0;
            o_overflow <= '0;
        end else begin
            if (i_pkt_valid && i_hb_ok && hb0 == 8'h02 && !hb1[4]) begin
                // layout 0: subpacket i = one stereo sample if present
                push_mask <= hb1[3:0] & i_sb_ok;
                push_flat <= hb2[3:0];
                for (int i = 0; i < 4; i++)
                    push_word[i] <= {i_sb[i][23:6], i_sb[i][47:30]};
            end else if (push) begin
                push_mask[push_idx] <= 1'b0;
            end
            if (push) begin
                if (!full) begin
                    wr_ptr <= wr_ptr + 1'd1;
                end else if (o_overflow != '1) begin
                    o_overflow <= o_overflow + 1'd1;
                end
            end
        end
    end

    logic [35:0] rd_data;
    always_ff @(posedge clk) rd_data <= mem[rd_ptr[FIFO_BITS-1:0]];

    // =================================================================
    // Rate: P = 2^33 * N / CTS (restoring divider, 53 steps)
    // =================================================================
    logic [19:0] div_n, div_cts;     // operands of the last division
    logic        div_busy;
    logic [5:0]  div_step;
    logic [52:0] div_num;            // dividend, shifted out MSB first
    logic [20:0] div_rem;
    logic [39:0] div_q;
    logic [39:0] step;               // NCO increment
    wire  [20:0] rem_sh  = {div_rem[19:0], div_num[52]};
    wire  [21:0] rem_sub = {1'b0, rem_sh} - {2'b0, div_cts};
    always_ff @(posedge clk) begin
        if (rst) begin
            div_busy <= 1'b0;
            div_n    <= '0;
            div_cts  <= '0;
            step     <= '0;
        end else if (!div_busy) begin
            if ((o_n != div_n || o_cts != div_cts) && o_cts != 0) begin
                div_busy <= 1'b1;
                div_n    <= o_n;
                div_cts  <= o_cts;
                div_num  <= {o_n, 33'd0};
                div_rem  <= '0;
                div_q    <= '0;
                div_step <= 6'd52;
            end
        end else begin
            div_num <= div_num << 1;
            if (!rem_sub[21]) begin
                div_rem <= rem_sub[20:0];
                div_q   <= {div_q[38:0], 1'b1};
            end else begin
                div_rem <= rem_sh;
                div_q   <= {div_q[38:0], 1'b0};
            end
            if (div_step == 0) div_busy <= 1'b0;
            div_step <= div_step - 1'd1;
        end
        if (div_busy && div_step == 0)
            step <= {div_q[38:0], !rem_sub[21]};
    end

    // =================================================================
    // NCO, playback, interpolation
    // =================================================================
    logic [39:0] phase;
    logic        tick;
    logic        pop_q;
    logic signed [17:0] prev_l, prev_r, cur_l, cur_r;
    assign pop = tick && o_running && level != 0;

    always_ff @(posedge clk) begin
        if (rst || !i_locked) begin
            phase      <= '0;
            tick       <= 1'b0;
            rd_ptr     <= '0;
            o_running  <= 1'b0;
            o_underrun <= '0;
            pop_q      <= 1'b0;
            prev_l <= '0; prev_r <= '0; cur_l <= '0; cur_r <= '0;
        end else begin
            {tick, phase} <= {1'b0, phase} + {1'b0, step};
            pop_q <= pop;
            if (!o_running) begin
                if (level >= START_LEVEL[FIFO_BITS:0]) o_running <= 1'b1;
            end else if (tick && level == 0) begin
                o_running <= 1'b0;                    // underrun: mute and re-prime
                prev_l <= '0; prev_r <= '0; cur_l <= '0; cur_r <= '0;
                if (o_underrun != '1) o_underrun <= o_underrun + 1'd1;
            end
            if (pop) rd_ptr <= rd_ptr + 1'd1;
            if (pop_q) begin                          // rd_data is the popped word
                prev_l <= cur_l;
                prev_r <= cur_r;
                cur_l  <= rd_data[35:18];
                cur_r  <= rd_data[17:0];
            end
        end
    end
    assign o_pop      = pop_q;
    assign o_pop_data = rd_data;

    // out = prev + (cur - prev) * phase fraction (the NCO phase runs from 0
    // at the pop of `cur` to 1 at the next pop). `cur` is loaded two clocks
    // after the NCO wraps (FIFO read), so the phase is delayed to match:
    // otherwise an update in between would use the new phase with the old
    // samples, a jump of one sample step.
    logic [15:0] frac_d1, frac;
    always_ff @(posedge clk) begin
        frac_d1 <= phase[39:24];
        frac    <= frac_d1;
    end
    wire signed [18:0]  diff_l = cur_l - prev_l;
    wire signed [18:0]  diff_r = cur_r - prev_r;
    wire signed [35:0]  mul_l  = diff_l * $signed({1'b0, frac});
    wire signed [35:0]  mul_r  = diff_r * $signed({1'b0, frac});
    always_ff @(posedge clk) begin
        if (rst || !i_locked) begin
            o_left  <= '0;
            o_right <= '0;
        end else if (i_out_en) begin
            o_left  <= prev_l + 18'(mul_l >>> 16);
            o_right <= prev_r + 18'(mul_r >>> 16);
        end
    end
endmodule
`default_nettype wire
