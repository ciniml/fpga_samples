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

    // Registered pacing with a 2-deep skid queue. The enable seen by
    // the TPG is a REGISTER (the combinational tvalid/tready ->
    // can_accept -> enable cone fanning into every TPG clock-enable
    // was a 162 MHz critical path). Because the stall now lands one
    // cycle late, the raster can advance one extra pixel after the
    // queue fills to one entry; the second queue slot absorbs it, and
    // enable_r only allows advancing while occupancy < 2, so nothing
    // is ever dropped.
    logic        v0, v1;      // head (AXIS output) and skid slot
    logic [23:0] d0, d1;
    logic        enable_r;

    assign m_axis_tvalid = v0;
    assign m_axis_tdata  = d0;
    assign tpg_enable    = !video_de || enable_r;

    // A pixel is consumed from the TPG on every cycle where DE is high
    // and the raster is advancing (enable_r high): its data would be
    // gone next cycle, so it must enter the queue now.
    wire push = video_de && enable_r;
    wire pop  = v0 && m_axis_tready;

    always_ff @(posedge clock) begin
        if (reset) begin
            v0 <= 1'b0;
            v1 <= 1'b0;
            d0 <= 24'h000000;
            d1 <= 24'h000000;
            enable_r <= 1'b0;
        end else begin
            // Queue update.
            if (push) begin
                if (!v0 || (pop && !v1)) begin
                    d0 <= video_data;
                    v0 <= 1'b1;
                end else if (!v1) begin
                    d1 <= video_data;
                    v1 <= 1'b1;
                    if (pop) begin
                        // pop with skid occupied: shift skid to head
                        d0 <= d1;
                    end
                end
                // push with v0&&v1 cannot happen: enable_r blocks it.
            end else if (pop) begin
                if (v1) begin
                    d0 <= d1;
                    v1 <= 1'b0;
                end else begin
                    v0 <= 1'b0;
                end
            end

            // Allow the raster to advance while the queue (after this
            // cycle's push/pop) holds at most one entry.
            enable_r <= ((v0 ? 1 : 0) + (v1 ? 1 : 0)
                         + (push ? 1 : 0) - (pop ? 1 : 0)) < 2;
        end
    end

endmodule

`default_nettype wire
