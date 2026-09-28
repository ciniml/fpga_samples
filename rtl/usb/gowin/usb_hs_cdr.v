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
module usb_hs_cdr #(
    parameter CDR_IIR  = 2,   // OsCdr histogram smoothing (2^IIR words)
    parameter CDR_HYST = 2
) (
    input  wire       clk_i,
    input  wire       rst_i,
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

    wire [8:0] cdr_bits; wire [3:0] cdr_nbits;
    // The CDR tracks continuously across packets (frozen while idle): with 3
    // samples per bit every phase is at most one step from the best class,
    // so the drift accumulated over an idle gap is caught up within a few
    // words of the next SYNC. (Re-acquiring per packet was worse: the
    // registered histogram/argmin pipeline jumps to a stale class.)
    OsCdr #(.SAMPLES(24), .OSR(3), .IIR(CDR_IIR), .HYST(CDR_HYST), .ACT_MIN(2)) u_cdr(
        .i_clk(clk_i), .i_rst(rst_i), .i_samples(s24_m), .i_freeze(i_se0),
        .o_bits(cdr_bits), .o_nbits(cdr_nbits), .o_phase(), .o_lock(o_lock), .o_slip());

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
    wire [7:0] hs_byte = bf[bf_rp];
    assign o_byte  = hs_byte;
    assign o_valid = !bf_empty;
    assign o_dp    = hs_byte  & {8{!bf_empty}};
    assign o_dn    = ~hs_byte & {8{!bf_empty}};
endmodule
