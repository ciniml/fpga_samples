// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file frame_sum.sv
 * @brief Per-frame Fletcher-style sum of the active pixels.
 *
 *   s1 += pixel, s2 += s1 (both 32 bit) and a DE pixel count, over the
 *   pixels between two VSYNC rising edges. Any single corrupted pixel
 *   changes s1; s2 makes the sum position dependent; the count catches
 *   DE errors. Two 32-bit adders per clock instead of a 24-bit-wide CRC
 *   XOR tree, which did not close at 148.5 MHz in dvi_capture (121 MHz).
 *
 *   o_stb pulses for one clock at each VSYNC rising edge with the sums
 *   of the frame that just ended. o_complete says that frame was seen
 *   from its start with i_valid high throughout.
 */
`default_nettype none
module frame_sum (
    input  wire         clock,
    input  wire         reset,
    input  wire         i_valid,
    input  wire  [23:0] i_data,
    input  wire         i_de,
    input  wire         i_vsync,
    output logic [31:0] o_s1,
    output logic [31:0] o_s2,
    output logic [31:0] o_count,
    output logic        o_complete,
    output logic        o_stb
);
    logic [23:0] d_q;
    logic        de_q;
    logic        vs_q;
    logic        vs_prev;
    logic [31:0] s1;
    logic [31:0] s2;
    logic [31:0] count;
    logic        seen_start;  // a VSYNC edge opened the current frame
    logic        valid_all;   // i_valid never dropped in the current frame

    always_ff @(posedge clock) begin
        if (reset) begin
            d_q        <= '0;
            de_q       <= 1'b0;
            vs_q       <= 1'b0;
            vs_prev    <= 1'b0;
            s1         <= '0;
            s2         <= '0;
            count      <= '0;
            seen_start <= 1'b0;
            valid_all  <= 1'b0;
            o_s1       <= '0;
            o_s2       <= '0;
            o_count    <= '0;
            o_complete <= 1'b0;
            o_stb      <= 1'b0;
        end else begin
            o_stb   <= 1'b0;
            d_q     <= i_data;
            de_q    <= i_valid && i_de;
            vs_q    <= i_valid && i_vsync;
            vs_prev <= vs_q;
            if (!i_valid) valid_all <= 1'b0;

            if (vs_q && !vs_prev) begin
                o_s1       <= s1;
                o_s2       <= s2;
                o_count    <= count;
                o_complete <= seen_start && valid_all;
                o_stb      <= 1'b1;
                s1         <= '0;
                s2         <= '0;
                count      <= '0;
                seen_start <= 1'b1;
                valid_all  <= i_valid;
            end else if (de_q) begin
                s1    <= s1 + {8'd0, d_q};
                s2    <= s2 + s1;
                count <= count + 1'd1;
            end
        end
    end
endmodule
`default_nettype wire
