// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file tpg_to_axis.sv
 * @brief Adapt the legacy `test_pattern_generator` (which produces a
 *        DE / HSYNC / VSYNC + 24bpp parallel video timing) into the
 *        AXI-Stream pixel input expected by `displayport_dp_source_top`
 *        (24bpp RGB, one pixel per beat, only emitted during DE).
 *
 *        The TPG runs in the pixel-clock domain and is upstream of the
 *        DP main-link byte-clock domain. Tang Primer 25K initial bring-up
 *        runs them on the SAME clock so we don't need a CDC FIFO; the
 *        DP IP back-pressures via tready when its internal pixel FIFO
 *        is full, and the TPG simply skips emitting a beat that cycle
 *        (which manifests as a column of unintended stuffing in the
 *        very first frame and resyncs from the next frame onwards).
 *        For high-rate / mismatched-clock operation a small CDC FIFO
 *        should be inserted between this adapter and the DP IP.
 */
`default_nettype none

module tpg_to_axis (
    input  wire        clock,
    input  wire        reset,

    input  wire [23:0] video_data,
    input  wire        video_de,

    output logic        m_axis_tvalid,
    input  wire         m_axis_tready,
    output logic [23:0] m_axis_tdata
);

    always_ff @(posedge clock) begin
        if (reset) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= 24'h000000;
        end else begin
            // Drive a beat for every active pixel. If the sink can't
            // accept it that cycle, the pixel is dropped — see header
            // comment.
            m_axis_tvalid <= video_de;
            m_axis_tdata  <= video_data;
        end
    end

endmodule

`default_nettype wire
