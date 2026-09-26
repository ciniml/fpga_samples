// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief Tang Primer 25K DVI 1080p60 TX -> RX loopback.
 *
 *   One board transmits and receives: two Sipeed Pmod DVI modules joined
 *   by an HDMI cable.
 *
 *     TX  PMOD2 (banks 6/7): loop_pattern -> dvi_out -> OSER10 x4 ->
 *         ELVDS_OBUF (LVPECL33E). 148.5 MHz / 742.5 MHz from 50 MHz via 27 MHz.
 *     RX  PMOD0 (bank 1, on-die 100 ohm termination): TLVDS_IBUF ->
 *         recovery PLL (cable clock 148.5 MHz -> 148.5 / 742.5 MHz) ->
 *         dvi_in_phy (IODELAY + IDES10 + dvi_in, from eda/dvi_capture).
 *     The two directions use separate HCLK groups (bank 6/7 vs bank 1),
 *     so each deserializer/serializer gets its own FCLK.
 *
 *   Check: both sides compute a per-frame sum of the (static) picture;
 *   the receiver compares every complete frame with the transmitter's.
 *   A wrong pixel, a DE error or swapped lanes all show up as a
 *   mismatched frame. Counters and a sampling-phase scan are reported
 *   over the USB-UART (115200 8N1, see loop_report.sv).
 *
 *   led_locked = word lock, led_error = mismatched frame or decode
 *   error in the last ~0.1 s. dbg (PMOD1): [0] mismatched frame (~110 us
 *   pulse), [1] decode error, [2] RX DE, [3] RX VSYNC.
 */
`default_nettype none
// Build variant: `define RATE_720P (make RATE=720P) runs the same design at
// 1280x720p60 (74.25 MHz, 742.5 Mbps) to check the loopback itself.
`ifdef RATE_720P
`define LOOP_TX_ODIV0 10
`define LOOP_TX_ODIV1 2
`define LOOP_RX_FCLKIN "74.25"
`define LOOP_RX_IDIV 1
`else
`define LOOP_TX_ODIV0 5
`define LOOP_TX_ODIV1 1
`define LOOP_RX_FCLKIN "148.5"
`define LOOP_RX_IDIV 2
`endif
module top (
    input  wire        clock,          // 50 MHz
    input  wire        reset_button,

    // TX (PMOD2)
    output wire        tx_clk_p,
    output wire        tx_clk_n,
    output wire [2:0]  tx_data_p,
    output wire [2:0]  tx_data_n,

    // RX (PMOD0)
    input  wire        rx_clk_p,
    input  wire        rx_clk_n,
    input  wire        rx_d0_p,
    input  wire        rx_d0_n,
    input  wire        rx_d1_p,
    input  wire        rx_d1_n,
    input  wire        rx_d2_p,
    input  wire        rx_d2_n,

    input  wire        uart_rxd,
    output wire        uart_txd,

    output logic       led_locked,
    output logic       led_error,
    output logic [3:0] dbg
);
    // =================================================================
    // Board clock domain (50 MHz)
    // =================================================================
    logic reset_sys;
    reset_seq #(.RESET_DELAY_CYCLES(16)) u_reset_sys (
        .clock    (clock),
        .reset_in (reset_button),
        .reset_out(reset_sys)
    );

    // =================================================================
    // TX
    // =================================================================
    logic clock_27;
    logic pll_27_lock;
    gowin_pll_27 u_pll_27 (
        .clkout0(clock_27),
        .lock   (pll_27_lock),
        .clkin  (clock)
    );

    logic tx_pclk;
    logic tx_fclk;
    logic tx_pll_lock;
    pll_tx_1080p #(.ODIV0(`LOOP_TX_ODIV0), .ODIV1(`LOOP_TX_ODIV1)) u_pll_tx (
        .clkout0(tx_pclk),
        .clkout1(tx_fclk),
        .lock   (tx_pll_lock),
        .clkin  (clock_27)
    );

    logic reset_tx;
    reset_seq #(.RESET_DELAY_CYCLES(8)) u_reset_tx (
        .clock    (tx_pclk),
        .reset_in (!pll_27_lock || !tx_pll_lock || reset_button),
        .reset_out(reset_tx)
    );

    logic [23:0] tx_video_data;
    logic        tx_video_de;
    logic        tx_video_hsync;
    logic        tx_video_vsync;
`ifdef RATE_720P
    loop_pattern #(
        .HSYNC(40), .HBACK(220), .HACTIVE(1280), .HFRONT(110),
        .VSYNC(5),  .VBACK(20),  .VACTIVE(720),  .VFRONT(5)
    ) u_pattern (
`else
    loop_pattern u_pattern (
`endif
        .clock      (tx_pclk),
        .reset      (reset_tx),
        .video_data (tx_video_data),
        .video_de   (tx_video_de),
        .video_hsync(tx_video_hsync),
        .video_vsync(tx_video_vsync)
    );

    logic [9:0] tmds_clock_word;
    logic [9:0] tmds_word [0:2];
    dvi_out u_dvi_out (
        .clock      (tx_pclk),
        .reset      (reset_tx),
        .video_data (tx_video_data),
        .video_de   (tx_video_de),
        .video_hsync(tx_video_hsync),
        .video_vsync(tx_video_vsync),
        .dvi_clock  (tmds_clock_word),
        .dvi_data0  (tmds_word[0]),
        .dvi_data1  (tmds_word[1]),
        .dvi_data2  (tmds_word[2])
    );

    wire [9:0] ser_word [0:3];
    assign ser_word[0] = tmds_word[0];
    assign ser_word[1] = tmds_word[1];
    assign ser_word[2] = tmds_word[2];
    assign ser_word[3] = tmds_clock_word;
    wire [3:0] ser_q;
    generate
`ifdef TX_CLK_ODDR
        // TX on PMOD1: the clock lane pad (L5) is in bank 1, whose HCLK
        // group serves the RX IDES10s at rx_fclk. The TMDS clock word
        // 0000011111 is the pixel clock itself, so send it through an
        // ODDR on tx_pclk instead of an OSER10 on tx_fclk.
        for (genvar i = 0; i < 3; i++) begin : g_oser
`else
        for (genvar i = 0; i < 4; i++) begin : g_oser
`endif
            OSER10 u_oser (
                .Q    (ser_q[i]),
                .D0   (ser_word[i][0]),
                .D1   (ser_word[i][1]),
                .D2   (ser_word[i][2]),
                .D3   (ser_word[i][3]),
                .D4   (ser_word[i][4]),
                .D5   (ser_word[i][5]),
                .D6   (ser_word[i][6]),
                .D7   (ser_word[i][7]),
                .D8   (ser_word[i][8]),
                .D9   (ser_word[i][9]),
                .FCLK (tx_fclk),
                .PCLK (tx_pclk),
                .RESET(reset_tx)
            );
        end
        for (genvar i = 0; i < 3; i++) begin : g_tx_obuf
            ELVDS_OBUF u_obuf (.I(ser_q[i]), .O(tx_data_p[i]), .OB(tx_data_n[i]));
        end
    endgenerate
`ifdef TX_CLK_ODDR
    ODDR u_oddr_clk (.Q0(ser_q[3]), .Q1(), .D0(1'b1), .D1(1'b0), .TX(1'b0), .CLK(tx_pclk));
`endif
    ELVDS_OBUF u_obuf_clk (.I(ser_q[3]), .O(tx_clk_p), .OB(tx_clk_n));

    // Reference sum of the transmitted picture. The picture is static,
    // so the latched value never changes once valid (quasi-static for
    // the RX-domain 2FF in loop_check).
    logic [31:0] tx_s1, tx_s2, tx_count;
    logic        tx_complete, tx_stb;
    frame_sum u_tx_sum (
        .clock     (tx_pclk),
        .reset     (reset_tx),
        .i_valid   (1'b1),
        .i_data    (tx_video_data),
        .i_de      (tx_video_de),
        .i_vsync   (tx_video_vsync),
        .o_s1      (tx_s1),
        .o_s2      (tx_s2),
        .o_count   (tx_count),
        .o_complete(tx_complete),
        .o_stb     (tx_stb)
    );
    logic [31:0] tx_ref_s1, tx_ref_s2, tx_ref_count;
    logic        tx_ref_valid;
    always_ff @(posedge tx_pclk) begin
        if (reset_tx) begin
            tx_ref_valid <= 1'b0;
        end else if (tx_stb && tx_complete) begin
            tx_ref_s1    <= tx_s1;
            tx_ref_s2    <= tx_s2;
            tx_ref_count <= tx_count;
            tx_ref_valid <= 1'b1;
        end
    end

    // =================================================================
    // RX
    // =================================================================
    wire cable_clk;
    wire serial_d0;
    wire serial_d1;
    wire serial_d2;
    TLVDS_IBUF u_ibuf_clk (.O(cable_clk), .I(rx_clk_p), .IB(rx_clk_n));
    TLVDS_IBUF u_ibuf_d0  (.O(serial_d0), .I(rx_d0_p),  .IB(rx_d0_n));
    TLVDS_IBUF u_ibuf_d1  (.O(serial_d1), .I(rx_d1_p),  .IB(rx_d1_n));
    TLVDS_IBUF u_ibuf_d2  (.O(serial_d2), .I(rx_d2_p),  .IB(rx_d2_n));

    logic rx_pclk;
    logic rx_fclk;
    logic rx_pll_lock;
    pll_rx_1080p #(
        .FCLKIN(`LOOP_RX_FCLKIN), .IDIV(`LOOP_RX_IDIV),
        .ODIV0(`LOOP_TX_ODIV0), .ODIV1(`LOOP_TX_ODIV1)
    ) pll_main (
        .clkout0(rx_pclk),
        .clkout1(rx_fclk),
        .lock   (rx_pll_lock),
        .clkin  (cable_clk)
    );

    logic reset_rx;
    reset_seq #(.RESET_DELAY_CYCLES(8)) reset_seq_pclk (
        .clock    (rx_pclk),
        .reset_in (!rx_pll_lock || reset_button),
        .reset_out(reset_rx)
    );

    logic [7:0]  rx_offset;
    logic [23:0] rx_video_data;
    logic        rx_video_de;
    logic        rx_video_hsync;
    logic        rx_video_vsync;
    logic [3:0]  rx_video_ctl;
    logic        rx_video_valid;
    logic [2:0]  rx_decode_err;
    logic        rx_locked;
    wire  [9:0]  dbg_word_d0;
    wire  [9:0]  dbg_word_d1;
    wire  [9:0]  dbg_word_d2;
    wire         dbg_align_shift;

    // DLYSTEP = DELAY_TAP_INIT (24) + rx_offset. At 1.485 Gbps one UI is
    // ~48 taps (~14 ps/tap); use the "s" scan to find the eye.
    dvi_in_phy #(.DELAY_TAP_INIT(24)) u_phy (
        .i_delay_offset   (rx_offset),
        .i_delay_offset_lane(rx_lane_offset),
        .i_pclk           (rx_pclk),
        .i_fclk           (rx_fclk),
        .i_reset          (reset_rx),
        .i_serial_d0      (serial_d0),
        .i_serial_d1      (serial_d1),
        .i_serial_d2      (serial_d2),
        .o_video_data     (rx_video_data),
        .o_video_de       (rx_video_de),
        .o_video_hsync    (rx_video_hsync),
        .o_video_vsync    (rx_video_vsync),
        .o_video_ctl      (rx_video_ctl),
        .o_video_valid    (rx_video_valid),
        .o_decode_err     (rx_decode_err),
        .o_locked         (rx_locked),
        .o_dbg_word_d0    (dbg_word_d0),
        .o_dbg_word_d1    (dbg_word_d1),
        .o_dbg_word_d2    (dbg_word_d2),
        .o_dbg_align_shift(dbg_align_shift)
    );

    // =================================================================
    // Checker, reporter
    // =================================================================
    logic        snap_req, snap_done, snap_locked, clear_req;
    logic [31:0] snap_frames, snap_bad, snap_derr, snap_last_count;
    logic [15:0] snap_unlock;
    logic [7:0]  sys_offset;
    logic        rx_frame_bad;
    logic [23:0] snap_lane_err [0:2];
    logic        words_req, words_done;
    logic [1:0]  words_mode;
    logic [9:0]  words [0:2][0:11];
    logic [31:0] snap_rx_cycles;
    logic [31:0] snap_pix_err, snap_bit_err;
    logic [31:0] snap_lane_bit_err [0:2];
    logic [7:0]  sys_lane_offset [0:2];
    logic [7:0]  rx_lane_offset [0:2];

    loop_check u_check (
        .rx_clk        (rx_pclk),
        .rx_reset      (reset_rx),
        .i_video_data  (rx_video_data),
        .i_video_de    (rx_video_de),
        .i_video_vsync (rx_video_vsync),
        .i_video_valid (rx_video_valid),
        .i_decode_err  (rx_decode_err),
        .i_locked      (rx_locked),
        .i_word0       (dbg_word_d0),
        .i_word1       (dbg_word_d1),
        .i_word2       (dbg_word_d2),
        .o_rx_offset   (rx_offset),
        .o_rx_lane_offset(rx_lane_offset),
        .o_frame_bad   (rx_frame_bad),
        .i_ext_bad     (1'b0),
        .i_tx_s1       (tx_ref_s1),
        .i_tx_s2       (tx_ref_s2),
        .i_tx_count    (tx_ref_count),
        .i_tx_ref_valid(tx_ref_valid),
        .sys_clk       (clock),
        .sys_snap_req  (snap_req),
        .sys_snap_done (snap_done),
        .sys_locked    (snap_locked),
        .sys_frames    (snap_frames),
        .sys_bad       (snap_bad),
        .sys_derr      (snap_derr),
        .sys_unlock    (snap_unlock),
        .sys_last_count(snap_last_count),
        .sys_lane_err  (snap_lane_err),
        .sys_rx_cycles (snap_rx_cycles),
        .sys_pix_err   (snap_pix_err),
        .sys_bit_err   (snap_bit_err),
        .sys_lane_bit_err(snap_lane_bit_err),
        .sys_lane_offset(sys_lane_offset),
        .sys_clear     (clear_req),
        .sys_words_req (words_req),
        .sys_words_done(words_done),
        .sys_words     (words),
        .sys_words_mode(words_mode),
        .sys_offset    (sys_offset)
    );

    loop_report u_report (
        .clock       (clock),
        .reset       (reset_sys),
        .uart_rxd    (uart_rxd),
        .uart_txd    (uart_txd),
        .o_offset    (sys_offset),
        .o_snap_req  (snap_req),
        .i_snap_done (snap_done),
        .i_locked    (snap_locked),
        .i_frames    (snap_frames),
        .i_bad       (snap_bad),
        .i_derr      (snap_derr),
        .i_unlock    (snap_unlock),
        .i_last_count(snap_last_count),
        .i_lane_err  (snap_lane_err),
        .i_rx_cycles (snap_rx_cycles),
        .i_pix_err   (snap_pix_err),
        .i_bit_err   (snap_bit_err),
        .i_lane_bit_err(snap_lane_bit_err),
        .o_lane_offset(sys_lane_offset),
        .i_pll_lock  (rx_pll_lock),
        .o_clear     (clear_req),
        .o_words_req (words_req),
        .o_words_mode(words_mode),
        .i_words_done(words_done),
        .i_words     (words)
    );

    // =================================================================
    // Indicators
    // =================================================================
    logic [23:0] err_stretch;   // ~0.11 s at 148.5 MHz
    logic [13:0] bad_stretch;   // ~110 us
    always_ff @(posedge rx_pclk) begin
        if (reset_rx) begin
            err_stretch <= '0;
            bad_stretch <= '0;
        end else begin
            if (rx_frame_bad || (rx_video_valid && |rx_decode_err)) err_stretch <= '1;
            else if (err_stretch != '0) err_stretch <= err_stretch - 1'd1;
            if (rx_frame_bad) bad_stretch <= '1;
            else if (bad_stretch != '0) bad_stretch <= bad_stretch - 1'd1;
        end
        dbg[0] <= bad_stretch != '0;
        dbg[1] <= rx_video_valid && |rx_decode_err;
        dbg[2] <= rx_video_de;
        dbg[3] <= rx_video_vsync;
    end

    assign led_locked = rx_locked;
    assign led_error  = err_stretch != '0;

    wire _unused = &{1'b0, tx_video_hsync, rx_video_hsync, rx_video_ctl, dbg_align_shift};
endmodule
`default_nettype wire
