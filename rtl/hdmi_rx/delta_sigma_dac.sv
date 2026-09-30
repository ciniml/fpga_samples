// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file delta_sigma_dac.sv
 * @brief Second-order 1-bit delta-sigma modulator for a GPIO + RC DAC.
 *
 * Boser-Wooley structure (two delaying integrators, gains 1/2), noise
 * transfer function (1 - z^-1)^2:
 *   y  = u2 >= 0 ? +FS : -FS
 *   u1 += (x - y) / 2
 *   u2 += (u1 - y) / 2
 * updated once per i_en. The input is scaled by 3/4 so that a full-scale
 * input keeps the loop stable (integrators stay below 2 FS). At 6.19 MHz
 * (74.25 MHz / 12) with linearly interpolated 48 kHz input the in-band
 * (20 Hz - 20 kHz) SNR is ~88 dB for a full-scale sine and the idle noise
 * floor ~-90 dBFS (numerical model), before the analog limits of the pin.
 *
 * o_dac is a register that only changes on i_en: drive the pin from it
 * directly and filter it with the RC network in the README.
 */
`default_nettype none
module delta_sigma_dac #(
    parameter int W = 18                 // input width (signed)
) (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 i_en,
    input  wire signed [W-1:0]  i_x,
    output logic                o_dac
);
    localparam int SW = W + 3;           // integrators: |u| < 2 FS plus margin
    localparam logic signed [SW-1:0] FS = SW'(1) <<< (W - 1);

    logic signed [SW-1:0] u1, u2;
    wire  signed [SW-1:0] x  = SW'(i_x) - (SW'(i_x) >>> 2);
    wire  signed [SW-1:0] y  = o_dac ? FS : -FS;
    wire  signed [SW-1:0] u1_next = u1 + ((x - y) >>> 1);
    wire  signed [SW-1:0] u2_next = u2 + ((u1 - y) >>> 1);

    always_ff @(posedge clk) begin
        if (rst) begin
            u1    <= '0;
            u2    <= '0;
            o_dac <= 1'b1;               // = (u2 >= 0)
        end else if (i_en) begin
            u1    <= u1_next;
            u2    <= u2_next;
            o_dac <= !u2_next[SW-1];
        end
    end
endmodule
`default_nettype wire
