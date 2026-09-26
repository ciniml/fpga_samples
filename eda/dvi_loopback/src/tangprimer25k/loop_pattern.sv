// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file loop_pattern.sv
 * @brief Raster timing + static, symbol-rich test pattern for the DVI
 *        loopback.
 *
 *   The picture is a pure function of the active-area coordinates, so
 *   every frame is identical (the receiver compares per-frame sums
 *   against the transmitter's). Unlike colour bars, the three channels
 *   walk through every byte value with mixed run lengths, exercising all
 *   TMDS data symbols and both disparity branches of the encoder. The
 *   channels differ from each other, so swapped lanes change the sum.
 *
 *   Defaults are CEA-861 1920x1080p60 (148.5 MHz), positive syncs.
 */
`default_nettype none
module loop_pattern #(
    parameter int HSYNC   = 44,
    parameter int HBACK   = 148,
    parameter int HACTIVE = 1920,
    parameter int HFRONT  = 88,
    parameter int VSYNC   = 5,
    parameter int VBACK   = 36,
    parameter int VACTIVE = 1080,
    parameter int VFRONT  = 4
) (
    input  wire         clock,
    input  wire         reset,
    output logic [23:0] video_data,
    output logic        video_de,
    output logic        video_hsync,
    output logic        video_vsync
);
    localparam int HTOTAL = HSYNC + HBACK + HACTIVE + HFRONT;
    localparam int VTOTAL = VSYNC + VBACK + VACTIVE + VFRONT;

    logic [11:0] hcount;
    logic [11:0] vcount;
    logic [11:0] x;      // active-area coordinates
    logic [11:0] y;

    wire h_active = hcount >= HSYNC + HBACK && hcount < HSYNC + HBACK + HACTIVE;
    wire v_active = vcount >= VSYNC + VBACK && vcount < VSYNC + VBACK + VACTIVE;

    always_ff @(posedge clock) begin
        if (reset) begin
            hcount      <= '0;
            vcount      <= '0;
            x           <= '0;
            y           <= '0;
            video_data  <= '0;
            video_de    <= 1'b0;
            video_hsync <= 1'b0;
            video_vsync <= 1'b0;
        end else begin
            if (hcount == HTOTAL - 1) begin
                hcount <= '0;
                x      <= '0;
                if (v_active) y <= y + 1'd1;
                if (vcount == VTOTAL - 1) begin
                    vcount <= '0;
                    y      <= '0;
                end else begin
                    vcount <= vcount + 1'd1;
                end
            end else begin
                hcount <= hcount + 1'd1;
                if (h_active) x <= x + 1'd1;
            end

            video_de    <= h_active && v_active;
            video_hsync <= hcount < HSYNC;
            video_vsync <= vcount < VSYNC;
            // {R, G, B}
            video_data  <= {x[7:0] ^ y[7:0],
                            x[10:3] + y[7:0],
                            x[8:1] ^ {y[3:0], y[7:4]}};
        end
    end
endmodule
`default_nettype wire
