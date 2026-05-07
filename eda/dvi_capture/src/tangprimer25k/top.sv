// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief Tang Primer 25K DVI receiver top.
 *
 *   This is a synthesis-only smoke test: dvi_in_phy is wired to four
 *   differential pads, status bits go to two LEDs, and the existing
 *   gowin_pll IP from display_port_tpg is reused as a stand-in
 *   F_pixel / 5×F_pixel source. For a real DVI capture path, regenerate
 *   the gowin_pll IP for the actual cable pixel rate, and feed it from
 *   the recovered cable clock instead of the on-board 50 MHz oscillator.
 */
`default_nettype none
module top(
    input  wire clock,            // on-board 50 MHz oscillator
    input  wire reset_button,

    // DVI input — four differential pairs (CLK + 3 data).
    input  wire dvi_clk_p,
    input  wire dvi_clk_n,
    input  wire dvi_d0_p,
    input  wire dvi_d0_n,
    input  wire dvi_d1_p,
    input  wire dvi_d1_n,
    input  wire dvi_d2_p,
    input  wire dvi_d2_n,

    // Status indicators on board LEDs.
    output logic led_locked,
    output logic led_decode_err
);

    // -----------------------------------------------------------------
    // Clocking — placeholder (162 MHz PCLK / 810 MHz FCLK from existing
    // gowin_pll IP). For a real DVI capture the PLL CLKIN must come
    // from the recovered cable clock, not the board oscillator.
    // -----------------------------------------------------------------
    logic clock_27;
    logic pll_lock_27;
    gowin_pll_27 pll_27 (
        .clkout0(clock_27),
        .lock   (pll_lock_27),
        .clkin  (clock)
    );

    logic pclk;
    logic fclk;
    logic pll_lock;
    gowin_pll pll_main (
        .clkout0(pclk),
        .clkout1(fclk),
        .lock   (pll_lock),
        .clkin  (clock_27)
    );

    // -----------------------------------------------------------------
    // Reset
    // -----------------------------------------------------------------
    logic reset_pclk;
    reset_seq #(.RESET_DELAY_CYCLES(8)) reset_seq_pclk (
        .clock    (pclk),
        .reset_in (!pll_lock_27 || !pll_lock || reset_button),
        .reset_out(reset_pclk)
    );

    // -----------------------------------------------------------------
    // DVI receiver PHY
    // -----------------------------------------------------------------
    wire [23:0] video_data;
    wire        video_de;
    wire        video_hsync;
    wire        video_vsync;
    wire [3:0]  video_ctl;
    wire        video_valid;
    wire [2:0]  decode_err;
    wire        locked;

    dvi_in_phy u_phy (
        .i_pclk       (pclk),
        .i_fclk       (fclk),
        .i_reset      (reset_pclk),
        .i_clk_p      (dvi_clk_p), .i_clk_n(dvi_clk_n),
        .i_d0_p       (dvi_d0_p),  .i_d0_n (dvi_d0_n),
        .i_d1_p       (dvi_d1_p),  .i_d1_n (dvi_d1_n),
        .i_d2_p       (dvi_d2_p),  .i_d2_n (dvi_d2_n),
        .o_video_data (video_data),
        .o_video_de   (video_de),
        .o_video_hsync(video_hsync),
        .o_video_vsync(video_vsync),
        .o_video_ctl  (video_ctl),
        .o_video_valid(video_valid),
        .o_decode_err (decode_err),
        .o_locked     (locked)
    );

    // -----------------------------------------------------------------
    // Status indicators. Or together the per-lane decode_err pulses so
    // the LED catches any error.
    // -----------------------------------------------------------------
    assign led_locked     = locked;
    assign led_decode_err = |decode_err;

endmodule
`default_nettype wire
