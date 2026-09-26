// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file crop_to_hub75.sv
 * @brief Crop the top-left DISP_W x DISP_H pixels of a video stream into
 *        Hub75 VRAM write commands (1:1, no scaling).
 *
 *   Panel geometry: 64x64 panels (1/32 scan: rows 0-31 on R1G1B1 and rows
 *   32-63 on R2G2B2 at the same row address), DISP_H / 64 panel rows.
 *   Electrically the panel rows are one chain: the second 64-row band is
 *   connected to the right of the first, so the chain is
 *   DISP_W * DISP_H / 64 pixels long (128x128 -> 256x64).
 *
 *     seg     = y / 64            (panel row, 0 or 1)
 *     yy      = y % 64
 *     half    = yy / 32           (0: R1G1B1, 1: R2G2B2)
 *     scan    = yy % 32           (row address A..E)
 *     chain_x = seg * DISP_W + x  (CHAIN_REVERSE: CHAIN_LEN-1 - that)
 *     addr    = {half, scan, chain_x}   (Hub75's VRAM address)
 *
 *   Colour: the top COMPONENT_BITS of each 8-bit channel, packed {R,G,B}.
 *
 *   Commands {flip, addr, pixel} go through an async FIFO to the Hub75
 *   clock domain. FLIP is sent right after the last pixel of the crop
 *   region, so the panel swaps to the new frame without waiting for the
 *   rest of the source frame. If the previous FLIP has not been consumed
 *   yet when a new frame starts (i_flip_pending, asynchronous), that
 *   frame is skipped instead of overwriting the buffer being flipped in.
 */
`default_nettype none

module crop_to_hub75 #(
    parameter int DISP_W         = 128,   // 64 or 128
    parameter int DISP_H         = 128,   // 64 or 128
    parameter int COMPONENT_BITS = 5,
    parameter bit CHAIN_REVERSE  = 1'b0,
    // derived
    parameter int CHAIN_LEN      = DISP_W * DISP_H / 64,
    parameter int X_BITS         = $clog2(CHAIN_LEN),
    parameter int ADDR_BITS      = 1 + 5 + X_BITS,
    parameter int CMD_BITS       = 1 + ADDR_BITS + 3 * COMPONENT_BITS
) (
    input  wire                 i_pclk,
    input  wire                 i_reset,
    input  wire                 i_valid,
    input  wire                 i_de,
    input  wire                 i_vsync,
    input  wire  [23:0]         i_data,          // {R, G, B}
    input  wire                 i_flip_pending,  // Hub75 domain, asynchronous
    output logic                o_cmd_wen,
    output logic [CMD_BITS-1:0] o_cmd,
    output logic                o_frame_skipped  // one pclk per skipped frame
);
    localparam int PX_BITS = 3 * COMPONENT_BITS;

    logic [11:0] x, y;
    logic        de_q, vs_q;
    logic        in_frame;        // a VSYNC edge was seen (x / y are valid)
    logic        skip;            // this frame is not written
    logic [1:0]  pend_s;

    wire [6:0]        yy      = y[6:0] & 7'd63;
    wire              seg     = (DISP_H > 64) && y[6];
    wire [X_BITS-1:0] cx_raw  = X_BITS'(x) + (seg ? X_BITS'(DISP_W) : '0);
    wire [X_BITS-1:0] chain_x = CHAIN_REVERSE ? X_BITS'(CHAIN_LEN - 1) - cx_raw : cx_raw;
    wire [ADDR_BITS-1:0] addr = {yy[5], yy[4:0], chain_x};
    wire [PX_BITS-1:0] px     = {i_data[23 -: COMPONENT_BITS],
                                 i_data[15 -: COMPONENT_BITS],
                                 i_data[7  -: COMPONENT_BITS]};

    wire de      = i_valid && i_de;
    wire vs_rise = i_valid && i_vsync && !vs_q;
    wire de_fall = de_q && !de;

    always_ff @(posedge i_pclk) begin
        if (i_reset) begin
            x               <= '0;
            y               <= '0;
            de_q            <= 1'b0;
            vs_q            <= 1'b0;
            in_frame        <= 1'b0;
            skip            <= 1'b1;
            pend_s          <= '0;
            o_cmd_wen       <= 1'b0;
            o_cmd           <= '0;
            o_frame_skipped <= 1'b0;
        end else begin
            o_cmd_wen       <= 1'b0;
            o_frame_skipped <= 1'b0;
            pend_s          <= {pend_s[0], i_flip_pending};
            de_q            <= de;
            vs_q            <= i_valid && i_vsync;

            if (!i_valid) begin
                in_frame <= 1'b0;             // lock lost: wait for the next frame
            end else if (vs_rise) begin
                x        <= '0;
                y        <= '0;
                in_frame <= 1'b1;
                skip     <= pend_s[1];
                if (pend_s[1]) o_frame_skipped <= 1'b1;
            end else begin
                if (de) begin
                    x <= x + 1'd1;
                    if (in_frame && !skip && x < 12'(DISP_W) && y < 12'(DISP_H)) begin
                        o_cmd_wen <= 1'b1;
                        o_cmd     <= {1'b0, addr, px};
                    end
                end
                if (de_fall) begin
                    x <= '0;
                    y <= y + 1'd1;
                    if (in_frame && !skip && y == 12'(DISP_H - 1)) begin
                        o_cmd_wen <= 1'b1;               // crop region complete
                        o_cmd     <= '0;
                        o_cmd[CMD_BITS-1] <= 1'b1;       // FLIP
                        skip      <= 1'b1;               // (nothing more this frame)
                    end
                end
            end
        end
    end
endmodule

`default_nettype wire
