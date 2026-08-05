// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file oser10_lane.sv
 * @brief Gowin OSER10 wrapper that takes a 10-bit symbol clocked at PCLK
 *        (= byte clock) and serialises it to a 1-bit DDR output at
 *        5×PCLK (effective bit rate = 10×PCLK). For DP RBR this means
 *        PCLK = 162 MHz, FCLK = 810 MHz, bit rate = 1.62 Gbps.
 *
 *        The OSER10 primitive sends D0 first, D9 last, matching the
 *        encoder_8b10b convention (bit 0 = 'a' = first transmitted).
 *
 *        `i_symbol_valid` is sampled in the PCLK domain. The DP main
 *        link runs continuously with one symbol per PCLK once
 *        CONTINUOUS_BYTE_TICK = 1 in dp_source_top, so we drive D0..D9
 *        unconditionally; if i_symbol_valid is low we shift out zeros.
 */
`default_nettype none

module oser10_lane (
    input  wire        i_pclk,    // parallel-side clock (= byte clock)
    input  wire        i_fclk,    // serial-side clock = 5 × i_pclk (DDR)
    input  wire        i_reset,   // synchronous reset (active high)

    input  wire        i_symbol_valid,
    input  wire [9:0]  i_symbol,

    output wire        o_serial   // single-ended serial bit at 10 × i_pclk
);

    wire [9:0] data = i_symbol_valid ? i_symbol : 10'b0;

    OSER10 oser_inst (
        .Q    (o_serial),
        .D0   (data[0]),
        .D1   (data[1]),
        .D2   (data[2]),
        .D3   (data[3]),
        .D4   (data[4]),
        .D5   (data[5]),
        .D6   (data[6]),
        .D7   (data[7]),
        .D8   (data[8]),
        .D9   (data[9]),
        .FCLK (i_fclk),
        .PCLK (i_pclk),
        .RESET(i_reset)
    );

endmodule

`default_nettype wire
