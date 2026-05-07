// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file iser10_lane.sv
 * @brief Gowin GW5A DVI / TMDS receiver lane wrapper.
 *
 *   differential pad ── TLVDS_IBUF ── IODELAY ── IDES10 ── 10-bit Q[9:0]
 *                                       ↑          ↑
 *                                  delay_tap   i_calib (CALIB)
 *
 *   Mirrors `oser10_lane.sv` (the OSER10 transmit wrapper). For DVI:
 *     PCLK = pixel clock                     (= recovered cable clock)
 *     FCLK = 5 × PCLK                        (DDR sampling clock)
 *     Bit rate at the differential pair = 10 × PCLK
 *
 *   IDES10's CALIB pulse advances the bit-slip boundary by one position
 *   per assertion, matching `dvi_in.o_align_shift_req` semantics: when
 *   the receiver decides the captured 10-bit word is on the wrong
 *   boundary, it raises i_calib for one PCLK and the next sampled word
 *   is shifted by 1 bit.
 *
 *   The IODELAY is configured with DYN_DLY_EN = "TRUE", ADAPT_EN =
 *   "FALSE", so DLYSTEP[7:0] is the live tap value. We maintain an
 *   internal 8-bit tap register here:
 *     - i_delay_load high latches i_delay_tap (zero-extended) into the
 *       register on the next PCLK edge,
 *     - i_delay_inc / i_delay_dec saturating-+1 / -1 the register.
 *   This converts dvi_in's mixed load + inc/dec interface into the
 *   single DLYSTEP value the primitive expects.
 *
 *   The Q-side output bit ordering matches OSER10's input convention:
 *   Q0 is the first bit received in time. Combined with dvi_in's
 *   LSB-first assumption, the 10-bit word can be wired straight into
 *   `i_word_data[*]` without any reversal.
 */
`default_nettype none

module iser10_lane #(
    parameter int DELAY_TAP_INIT = 8'd16  // initial tap (mid of 0..255 range)
) (
    input  wire        i_pclk,
    input  wire        i_fclk,
    input  wire        i_reset,        // active-high synchronous reset

    input  wire        i_pad_p,
    input  wire        i_pad_n,

    // From dvi_in. All single-cycle pulses except i_delay_tap which is
    // sampled when i_delay_load is high.
    input  wire        i_calib,        // o_align_shift_req
    input  wire        i_delay_load,   // o_delay_load
    input  wire [4:0]  i_delay_tap,    // o_delay_tap (5 bit)
    input  wire        i_delay_inc,    // o_delay_inc
    input  wire        i_delay_dec,    // o_delay_dec

    // Optional saturation flag from IODELAY (high when tap pinned).
    output wire        o_delay_saturate,

    // 10-bit deserialized word. Q0 is the first bit received in time.
    output wire [9:0]  o_word
);

    // ------------------------------------------------------------------
    // Differential receive
    // ------------------------------------------------------------------
    wire serial_se;     // single-ended after TLVDS_IBUF
    wire serial_delayed;

    TLVDS_IBUF u_ibuf (
        .O (serial_se),
        .I (i_pad_p),
        .IB(i_pad_n)
    );

    // ------------------------------------------------------------------
    // Programmable input delay. Tap register is driven by dvi_in's load
    // / inc / dec interface, with simple saturation at 0..255.
    // ------------------------------------------------------------------
    logic [7:0] delay_tap_reg;

    always_ff @(posedge i_pclk) begin
        if (i_reset) begin
            delay_tap_reg <= 8'(DELAY_TAP_INIT);
        end else if (i_delay_load) begin
            delay_tap_reg <= {3'b000, i_delay_tap};
        end else if (i_delay_inc && !i_delay_dec) begin
            if (delay_tap_reg != 8'd255)
                delay_tap_reg <= delay_tap_reg + 8'd1;
        end else if (i_delay_dec && !i_delay_inc) begin
            if (delay_tap_reg != 8'd0)
                delay_tap_reg <= delay_tap_reg - 8'd1;
        end
    end

    IODELAY #(
        .C_STATIC_DLY(DELAY_TAP_INIT),
        .DYN_DLY_EN  ("TRUE"),
        .ADAPT_EN    ("FALSE")
    ) u_iodelay (
        .DI     (serial_se),
        .DLYSTEP(delay_tap_reg),
        .SDTAP  (1'b0),
        .VALUE  (1'b0),
        .DO     (serial_delayed),
        .DF     (o_delay_saturate)
    );

    // ------------------------------------------------------------------
    // 1:10 Deserializer. CALIB advances the word boundary by one bit
    // per pulse — wired directly to dvi_in.o_align_shift_req.
    // ------------------------------------------------------------------
    IDES10 u_ides10 (
        .D    (serial_delayed),
        .CALIB(i_calib),
        .PCLK (i_pclk),
        .FCLK (i_fclk),
        .RESET(i_reset),
        .Q0   (o_word[0]),
        .Q1   (o_word[1]),
        .Q2   (o_word[2]),
        .Q3   (o_word[3]),
        .Q4   (o_word[4]),
        .Q5   (o_word[5]),
        .Q6   (o_word[6]),
        .Q7   (o_word[7]),
        .Q8   (o_word[8]),
        .Q9   (o_word[9])
    );

endmodule

`default_nettype wire
