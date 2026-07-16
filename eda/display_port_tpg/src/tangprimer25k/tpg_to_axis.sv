// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file tpg_to_axis.sv
 * @brief Adapt `test_pattern_generator` (DE / HSYNC / VSYNC + 24bpp
 *        parallel video) into the AXI-Stream pixel input expected by
 *        `displayport_dp_source_top`, pacing the TPG on demand.
 *
 *        The DP main link consumes at most one pixel per three byte
 *        clocks (24bpp over an 8-bit symbol lane), while the TPG would
 *        produce one pixel per clock if free-running on the byte clock —
 *        3x too fast. Instead of dropping pixels, this adapter drives the
 *        TPG's `enable` input:
 *
 *          - during blanking (DE low) the raster free-runs, so blanking
 *            is traversed at full clock rate;
 *          - during DE the raster only advances when the current pixel
 *            has been accepted downstream (skid-free: the TPG's
 *            registered outputs hold the pixel while stalled).
 *
 *        Production is therefore demand-paced and never drops pixels;
 *        because blanking traversal is faster than the link's blanking,
 *        the TPG stays ahead of the framer and the DP IP's internal
 *        pixel FIFO stays filled after the first frame. The TPG frame
 *        rate is decoupled from the DP raster (no genlock) — fine for a
 *        static test pattern.
 */
`default_nettype none

module tpg_to_axis (
    input  wire        clock,
    input  wire        reset,

    // TPG side
    input  wire [23:0] video_data,
    input  wire        video_de,
    output wire        tpg_enable,

    // DP IP side
    output logic        m_axis_tvalid,
    input  wire         m_axis_tready,
    output logic [23:0] m_axis_tdata
);

    // Accept a new pixel when the output register is free (or being
    // freed this cycle).
    logic can_accept;
    assign can_accept = !m_axis_tvalid || m_axis_tready;

    // Free-run through blanking; stall the raster on an unaccepted
    // active pixel.
    assign tpg_enable = !video_de || can_accept;

    always_ff @(posedge clock) begin
        if (reset) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= 24'h000000;
        end else begin
            if (m_axis_tvalid && m_axis_tready) begin
                m_axis_tvalid <= 1'b0;
            end
            if (video_de && can_accept) begin
                m_axis_tvalid <= 1'b1;
                m_axis_tdata  <= video_data;
            end
        end
    end

endmodule

`default_nettype wire
