// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file rgb_range_expand.sv
 * @brief Limited-range (16-235) RGB to full range, one clock of latency.
 *
 * out = clamp(round((in - 16) * 255 / 219)) with 255 / 219 ~ 298 / 256,
 * applied per component while i_limited; otherwise a plain register. The
 * control signals are delayed by the same clock.
 */
`default_nettype none
module rgb_range_expand (
    input  wire        clk,
    input  wire        i_limited,
    input  wire [23:0] i_data,
    input  wire        i_de,
    input  wire        i_vsync,
    input  wire        i_valid,
    output logic [23:0] o_data,
    output logic       o_de,
    output logic       o_vsync,
    output logic       o_valid
);
    function automatic [7:0] expand(input [7:0] v);
        logic signed [17:0] t;
        t = ($signed({1'b0, v}) - 18'sd16) * 18'sd298 + 18'sd128;
        if (t < 0)                 expand = 8'd0;
        else if (t >= 18'sd65280)  expand = 8'd255;   // 255 << 8
        else                       expand = t[15:8];
    endfunction

    always_ff @(posedge clk) begin
        o_data  <= i_limited ? {expand(i_data[23:16]), expand(i_data[15:8]), expand(i_data[7:0])} : i_data;
        o_de    <= i_de;
        o_vsync <= i_vsync;
        o_valid <= i_valid;
    end
endmodule
`default_nettype wire
