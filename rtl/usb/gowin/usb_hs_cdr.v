// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// USB HS clock/data recovery from three receivers sampled once per bit each
// (480 Msps, 8 samples per 60 MHz word): the differential receiver (dd) and
// the two single-ended comparators (dp, dn) see the same HS data; with the
// comparator paths delayed by 1/3 and 2/3 UI the three words interleave into
// 24 samples per word = 3 per bit. OsCdr (rtl/oscdr, OSR = 3) picks the
// sample phase and tracks the plesiochronous drift, emitting 7..9 bits per
// word; BitGearbox packs 16-bit words; a byte FIFO hands one byte per clock
// to the PHY with o_valid (0 = no byte this clock -> the PHY stalls).
//
// Idle: i_se0 (both comparators low, filtered by the caller) forces the CDR
// input to constant J (phase held, no transitions) so the packet tail still
// in the pipeline drains, followed by idle J bytes; 8 words into the idle the
// gearbox and FIFO are cleared (drops the slip backlog). The single-ended
// view for the PHY (o_dp / o_dn) follows the byte stream: J/K while a byte
// is pending, SE0 otherwise, so the PHY never sees SE0 ahead of the data.
`timescale 1ns/1ps
// Delay tracking (i_track_en): the three IODELAY taps move together so that
// the data transitions fall between the dn and dp samples, which keeps the
// differential receiver (dd, the clean one) 1/3..2/3 UI inside the eye and
// makes the CDR pick it as the data sample; the comparators only time the
// edges. Bang-bang: per transition between dd[k-1] and dd[k], dn[k] already
// showing the new level = edge before dn -> more delay; dp[k] still showing
// the old level = edge after dp -> less delay. +/-1 tap (12.5 ps) per word
// once the votes reach TRACK_TH, base tap 0..BASE_MAX (dn = base + DN_OFF
// must stay <= 255), re-centred to BASE_MAX/2 in steady idle. The blind CDR
// keeps working when the range saturates, just with comparator samples.
module usb_hs_cdr #(
    parameter CDR_IIR  = 2,   // OsCdr histogram smoothing (2^IIR words)
    parameter CDR_HYST = 2,
    parameter DP_OFF   = 60,  // dp tap = base + DP_OFF (+12 intrinsic, +48 = 1/3 UI at the measured ~14.5 ps/tap: 1 UI = 144 taps)
    parameter DN_OFF   = 108, // dn tap = base + DN_OFF (+12, +96 = 2/3 UI)
    parameter BASE_MAX = 128,
    parameter TRACK_TH = 4    // words per tap step (12.5 ps / (4 x 16.7 ns) = 190 ppm max tracking rate; smoother than 2)
) (
    input  wire       clk_i,
    input  wire       rst_i,
    input  wire       i_track_en,  // 1: delay tracking loop, 0: base = i_dly_base
    input  wire [7:0] i_dly_base,
    output reg  [7:0] o_dly_dd,
    output wire [7:0] o_dly_dp,
    output wire [7:0] o_dly_dn,
    input  wire [7:0] i_dd,       // differential receiver, bit 0 first (phase 0)
    input  wire [7:0] i_dp,       // D+ comparator (phase +1/3 UI)
    input  wire [7:0] i_dn,       // D- comparator (phase +2/3 UI, inverted data)
    input  wire       i_se0,      // line idle (filtered), per word
    output wire [7:0] o_byte,     // recovered bits, bit 0 first
    output wire       o_valid,
    output wire [7:0] o_dp,       // single-ended view aligned with o_byte
    output wire [7:0] o_dn,
    output wire       o_lock
);
    wire [23:0] s24;
    genvar k;
    generate
        // An IODELAY delays the signal, so the sample taken from a delayed
        // path shows the line as it was earlier: with dp at +1/3 UI and dn at
        // +2/3 UI of extra delay, sample k of dn is the earliest line time,
        // then dp, then dd (time order [dn, dp, dd], uniformly 1/3 UI apart,
        // followed by dn of sample k+1).
        for (k = 0; k < 8; k = k + 1) begin : g_il
            assign s24[3*k]   = ~i_dn[k];
            assign s24[3*k+1] = i_dp[k];
            assign s24[3*k+2] = i_dd[k];
        end
    endgenerate
    reg [7:0] se0_sh;
    always @(posedge clk_i) se0_sh <= {se0_sh[6:0], i_se0};
    // clear only in steady idle (both the current and the 8-word-old idle
    // flags set): released the moment a packet starts, asserted 8 words
    // after the line went idle so the packet tail drains first
    wire        se0_d8 = se0_sh[7] & i_se0;
    wire [23:0] s24_m  = i_se0 ? 24'hffffff : s24;

    wire [8:0] cdr_bits; wire [3:0] cdr_nbits; wire [5:0] acc_first, acc_last;
    // The CDR tracks continuously across packets (frozen while idle): with 3
    // samples per bit every phase is at most one step from the best class,
    // so the drift accumulated over an idle gap is caught up within a few
    // words of the next SYNC. (Re-acquiring per packet was worse: the
    // registered histogram/argmin pipeline jumps to a stale class.)
    OsCdr #(.SAMPLES(24), .OSR(3), .IIR(CDR_IIR), .HYST(CDR_HYST), .ACT_MIN(2)) u_cdr(
        .i_clk(clk_i), .i_rst(rst_i), .i_samples(s24_m), .i_freeze(i_se0), .i_reacq(1'b0),
        .o_bits(cdr_bits), .o_nbits(cdr_nbits), .o_phase(), .o_lock(o_lock), .o_slip(),
        .o_acc_first(acc_first), .o_acc_last(acc_last));

    wire        gb_valid; wire [15:0] gb_word;
    BitGearbox #(.IN_MAX(9), .OUT_W(16)) u_gb(
        .i_clk(clk_i), .i_rst(rst_i | se0_d8), .i_bits(cdr_bits), .i_nbits(cdr_nbits),
        .o_valid(gb_valid), .o_word(gb_word));

    reg [7:0] bf [0:7];
    reg [2:0] bf_wp, bf_rp;
    wire      bf_empty = (bf_wp == bf_rp);
    always @(posedge clk_i) begin
        if (rst_i | se0_d8) begin bf_wp <= 3'd0; bf_rp <= 3'd0; end
        else begin
            if (gb_valid) begin bf[bf_wp] <= gb_word[7:0]; bf[bf_wp + 3'd1] <= gb_word[15:8]; bf_wp <= bf_wp + 3'd2; end
            if (!bf_empty) bf_rp <= bf_rp + 3'd1;
        end
    end
    // ---- delay tracking loop ----
    // Uses the CDR's smoothed transition histogram (polarity-agnostic, the
    // same data the CDR selects the sample with). In time order [dn, dp, dd]
    // class 0 = transitions between dd[k-1] and dn[k] (edge before dn: the
    // samples see the line too late -> more delay), class 2 = between dp[k]
    // and dd[k] (edge after dp -> less delay); the target is class 1 (edge
    // between dn and dp), which makes dd the CDR's data sample. One tap per
    // TRACK_TH words while the imbalance exceeds the hysteresis.
    reg [7:0] step_cnt;
    wire      edge_early = acc_first > acc_last + 6'd2;
    wire      edge_late  = acc_last  > acc_first + 6'd2;
    always @(posedge clk_i) begin
        if (rst_i) begin o_dly_dd <= BASE_MAX / 2; step_cnt <= 0; end
        else if (!i_track_en) begin o_dly_dd <= i_dly_base; step_cnt <= 0; end
        else if (se0_d8) begin o_dly_dd <= BASE_MAX / 2; step_cnt <= 0; end          // re-centre between packets
        else if (i_se0) step_cnt <= 0;
        else if (step_cnt != TRACK_TH - 1) step_cnt <= step_cnt + 1'b1;
        else begin
            step_cnt <= 0;
            if (edge_early && o_dly_dd < BASE_MAX) o_dly_dd <= o_dly_dd + 1'b1;
            else if (edge_late && o_dly_dd != 0)   o_dly_dd <= o_dly_dd - 1'b1;
        end
    end
    assign o_dly_dp = o_dly_dd + DP_OFF;
    assign o_dly_dn = o_dly_dd + DN_OFF;

    wire [7:0] hs_byte = bf[bf_rp];
    assign o_byte  = hs_byte;
    assign o_valid = !bf_empty;
    assign o_dp    = hs_byte  & {8{!bf_empty}};
    assign o_dn    = ~hs_byte & {8{!bf_empty}};
endmodule
