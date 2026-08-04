// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file dvi_in_phy.sv
 * @brief Tang Primer 25K (Gowin GW5A) DVI receiver PHY.
 *
 *   Wraps the four DVI lanes (CLK + 3 data) into a single block that
 *   exposes the recovered video stream out of `dvi_in`.
 *
 *           ┌─────────── i_pclk  (= cable clock @ F_pixel) ─────────────┐
 *           │ ┌───────── i_fclk  (= 5 × F_pixel, same PLL)   ───────────┤
 *           │ │ ┌─ i_reset                                              │
 *           ▼ ▼ ▼                                                       │
 *  i_serial_d0  ─► iser10_lane ─► word_d0 [10] ─┬─► dvi_in ─► RGB/DE/HV │
 *  i_serial_d1  ─► iser10_lane ─► word_d1 [10] ─┤                       │
 *  i_serial_d2  ─► iser10_lane ─► word_d2 [10] ─┘                       │
 *
 *  Inputs are single-ended, post-TLVDS_IBUF (IBUFs live in the board
 *  top). The clock pair is NOT deserialized — its IBUF output feeds the
 *  recovery PLL, and a pad whose buffer fans out to the PLL cannot also
 *  drive the IODELAY/IDES10 chain (observed on GW5A: such a lane's
 *  deserializer stays silent). dvi_in aligns on data-lane-0 control
 *  symbols instead; its o_align_shift_req fans out to all three CALIB
 *  inputs.
 *
 *   i_pclk / i_fclk must be generated externally from the cable clock
 *   (single PLLA, CLKOUT0 = F_pixel, CLKOUT1 = 5 × F_pixel from the
 *   same VCO). This module assumes they are already valid.
 *
 *   o_delay_inc/dec/load/tap from `dvi_in` fan out to all four lanes
 *   simultaneously: the cable's source-synchronous timing means all
 *   four lanes share the same eye centre, so they share one delay
 *   sweep. (A more elaborate design would calibrate per-lane; this
 *   first pass mirrors the simple receiver in DVI 1.0 §3.3.1.)
 */
`default_nettype none

module dvi_in_phy #(
    parameter int DELAY_TAP_INIT       = 16,
    parameter int LOCK_THRESHOLD       = 16,
    parameter int LOSE_THRESHOLD       = 16,
    parameter int SHIFT_SETTLE_CYCLES  = 4,
    parameter int TAP_MAX              = 31,
    parameter int TAP_DWELL            = 256,
    parameter bit SIMULATION_FAST_LOCK = 0
) (
    input  wire        i_pclk,
    input  wire        i_fclk,
    input  wire        i_reset,

    // Single-ended serial inputs, post-TLVDS_IBUF (the IBUFs live in the
    // board top). The clock pair is NOT deserialized: its buffer output
    // must feed the recovery PLL, and a pad whose IBUF fans out to the
    // PLL cannot also drive the IODELAY/IDES10 chain. Word alignment
    // uses data-lane-0 control symbols inside dvi_in instead.
    input  wire        i_serial_d0,
    input  wire        i_serial_d1,
    input  wire        i_serial_d2,

    // Bring-up: static sampling-phase offset added to every lane's
    // IODELAY tap (full 8-bit DLYSTEP range).
    input  wire [7:0]  i_delay_offset,

    // Recovered video
    output wire [23:0] o_video_data,
    output wire        o_video_de,
    output wire        o_video_hsync,
    output wire        o_video_vsync,
    output wire [3:0]  o_video_ctl,
    output wire        o_video_valid,
    output wire [2:0]  o_decode_err,
    output wire        o_locked,

    // Bring-up debug taps (scope outputs; safe to leave unconnected).
    output wire [9:0]  o_dbg_word_d0,
    output wire        o_dbg_align_shift
);

    // ------------------------------------------------------------------
    // Per-lane deserializers. All four CALIB inputs are tied together
    // so a single align_shift_req from dvi_in slips every lane in
    // lockstep.
    // ------------------------------------------------------------------
    wire [9:0] word_d0;
    wire [9:0] word_d1;
    wire [9:0] word_d2;

    wire        align_shift_req;
    assign o_dbg_word_d0     = word_d0;
    assign o_dbg_align_shift = align_shift_req;
    wire        delay_load;
    wire [4:0]  delay_tap;
    wire        delay_inc;
    wire        delay_dec;
    wire [3:0]  delay_saturate;     // per-lane DF (unused for now)

    iser10_lane #(.DELAY_TAP_INIT(DELAY_TAP_INIT)) u_d0_lane (
        .i_pclk          (i_pclk),
        .i_fclk          (i_fclk),
        .i_reset         (i_reset),
        .i_serial        (i_serial_d0),
        .i_calib         (align_shift_req),
        .i_delay_load    (delay_load),
        .i_delay_tap     (delay_tap),
        .i_delay_inc     (delay_inc),
        .i_delay_dec     (delay_dec),
        .i_delay_offset  (i_delay_offset),
        .o_delay_saturate(delay_saturate[0]),
        .o_word          (word_d0)
    );
    iser10_lane #(.DELAY_TAP_INIT(DELAY_TAP_INIT)) u_d1_lane (
        .i_pclk          (i_pclk),
        .i_fclk          (i_fclk),
        .i_reset         (i_reset),
        .i_serial        (i_serial_d1),
        .i_calib         (align_shift_req),
        .i_delay_load    (delay_load),
        .i_delay_tap     (delay_tap),
        .i_delay_inc     (delay_inc),
        .i_delay_dec     (delay_dec),
        .i_delay_offset  (i_delay_offset),
        .o_delay_saturate(delay_saturate[1]),
        .o_word          (word_d1)
    );
    iser10_lane #(.DELAY_TAP_INIT(DELAY_TAP_INIT)) u_d2_lane (
        .i_pclk          (i_pclk),
        .i_fclk          (i_fclk),
        .i_reset         (i_reset),
        .i_serial        (i_serial_d2),
        .i_calib         (align_shift_req),
        .i_delay_load    (delay_load),
        .i_delay_tap     (delay_tap),
        .i_delay_inc     (delay_inc),
        .i_delay_dec     (delay_dec),
        .i_delay_offset  (i_delay_offset),
        .o_delay_saturate(delay_saturate[2]),
        .o_word          (word_d2)
    );

    // ------------------------------------------------------------------
    // dvi_in core. Generated SV uses port name `clock`/`reset` (r#-
    // escaped in the Veryl source) and module name `dvi_in`
    // (omit_project_prefix = true).
    // ------------------------------------------------------------------
    wire [9:0] word_data_array [0:2];
    assign word_data_array[0] = word_d0;
    assign word_data_array[1] = word_d1;
    assign word_data_array[2] = word_d2;

    dvi_in #(
        .LOCK_THRESHOLD      (LOCK_THRESHOLD),
        .LOSE_THRESHOLD      (LOSE_THRESHOLD),
        .SHIFT_SETTLE_CYCLES (SHIFT_SETTLE_CYCLES),
        .TAP_MAX             (TAP_MAX),
        .TAP_DWELL           (TAP_DWELL),
        .DELAY_TAP_FIXED     (DELAY_TAP_INIT),
        .SIMULATION_FAST_LOCK(SIMULATION_FAST_LOCK)
    ) u_core (
        .clock            (i_pclk),
        .reset            (i_reset),
        .i_word_data      (word_data_array),
        .i_word_valid     (1'b1),
        .o_video_data     (o_video_data),
        .o_video_de       (o_video_de),
        .o_video_hsync    (o_video_hsync),
        .o_video_vsync    (o_video_vsync),
        .o_video_ctl      (o_video_ctl),
        .o_video_valid    (o_video_valid),
        .o_decode_err     (o_decode_err),
        .o_locked         (o_locked),
        .o_align_shift_req(align_shift_req),
        .o_delay_inc      (delay_inc),
        .o_delay_dec      (delay_dec),
        .o_delay_load     (delay_load),
        .o_delay_tap      (delay_tap)
    );

endmodule

`default_nettype wire
