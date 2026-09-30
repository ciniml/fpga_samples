// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief DVI / HDMI input (720p60) -> HUB75 LED matrix, Tang Primer 25K.
 *
 *   pmod0        : Pmod DVI (RX; the eda/dvi_capture PHY, CTLE HIGH)
 *   40-pin header: DDC SCL F1 (pin 15), SDA F2 (pin 16), HPD A1 (pin 17)
 *   pmod1+pmod2  : HUB75 Pmod baseboard -> 64x64 panels (1/32 scan)
 *   USB-UART     : diagnostics / sampling-phase tuning (loop_report)
 *
 *   The top-left DISP_W x DISP_H pixels of the picture are shown 1:1.
 *   Panel rows of 64 are chained: the second band (y 64..127) is wired to
 *   the right of the first in the shift chain (128x128 = 256x64).
 *
 *   pclk (74.25 MHz, recovered)               clock (50 MHz, on-board)
 *   dvi_in_phy -> crop_to_hub75 --async FIFO--> Hub75 (double-buffered
 *                                               VRAM, BCM, 5 bit/colour)
 *
 *   The HUB75 side runs from the board oscillator, so the panel keeps
 *   refreshing (last picture) when the source goes away.
 */
`default_nettype none
`ifndef DISP_W
`define DISP_W 128
`endif
`ifndef DISP_H
`define DISP_H 128
`endif
`ifndef COMPONENT_BITS
`define COMPONENT_BITS 5      // BCM bit planes per colour (make BITS=6)
`endif
`ifndef HUB75_CLKDIV
`define HUB75_CLKDIV 1        // HUB75 CLK = 50 MHz / (2 * (N + 1)) (make HUB75_CLKDIV=0)
`endif
`ifndef HUB75_CLKLOW
`define HUB75_CLKLOW 0        // extra CLK-low ticks per pixel (make HUB75_CLKDIV=0 HUB75_CLKLOW=1: 16.7 MHz)
`endif
module top (
    input  wire clock,            // on-board 50 MHz oscillator
    input  wire reset_button,
    input  wire button_replug,    // S1: drop HPD for 200 ms (EDID re-read)

    // DVI input on pmod0
    input  wire dvi_clk_p,
    input  wire dvi_clk_n,
    input  wire dvi_d0_p,
    input  wire dvi_d0_n,
    input  wire dvi_d1_p,
    input  wire dvi_d1_n,
    input  wire dvi_d2_p,
    input  wire dvi_d2_n,

    // HDMI/DVI side channel (40-pin header; DDC is 5 V: level shifter)
    input  wire  ddc_scl,
    inout  wire  ddc_sda,
    output logic hpd,

    // HUB75 on pmod1 + pmod2
    output logic       hub75_row_a,
    output logic       hub75_row_b,
    output logic       hub75_row_c,
    output logic       hub75_row_d,
    output logic       hub75_row_e,
    output logic [1:0] hub75_r,   // [0] = R1 (rows 0-31 of a panel), [1] = R2 (rows 32-63)
    output logic [1:0] hub75_g,
    output logic [1:0] hub75_b,
    output logic       hub75_oe,
    output logic       hub75_lat,
    output logic       hub75_clk,

    output wire  uart_txd,
    input  wire  uart_rxd,
    output logic led_locked,
    output logic led_decode_err
);
    localparam int DISP_W         = `DISP_W;
    localparam int DISP_H         = `DISP_H;
    localparam int COMPONENT_BITS = `COMPONENT_BITS;
    localparam int CHAIN_LEN      = DISP_W * DISP_H / 64;
    localparam int X_BITS         = $clog2(CHAIN_LEN);
    localparam int ADDR_BITS      = 1 + 5 + X_BITS;
    localparam int PX_BITS        = 3 * COMPONENT_BITS;
    localparam int CMD_BITS       = 1 + ADDR_BITS + PX_BITS;

    // =================================================================
    // Board clock domain: resets, DDC / EDID, HPD
    // =================================================================
    logic reset_sys;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_sys (
        .clock    (clock),
        .reset_in (reset_button),
        .reset_out(reset_sys)
    );

    wire  ddc_sda_in;
    logic ddc_sda_oe;
    IOBUF u_ddc_sda (.O(ddc_sda_in), .IO(ddc_sda), .I(1'b0), .OEN(!ddc_sda_oe));
    logic       ddc_read_strobe;
    logic [7:0] ddc_offset;
    ddc_edid u_ddc (
        .i_clk        (clock),
        .i_rst        (reset_sys),
        .i_scl        (ddc_scl),
        .i_sda        (ddc_sda_in),
        .o_sda_oe     (ddc_sda_oe),
        .o_busy       (),
        .o_read_strobe(ddc_read_strobe),
        .o_offset     (ddc_offset)
    );

    logic [1:0] replug_sync;
    logic       replug_q;
    always_ff @(posedge clock) begin
        replug_sync <= {replug_sync[0], button_replug};
        replug_q    <= replug_sync[1];
    end
    hpd_ctrl u_hpd (
        .i_clk    (clock),
        .i_rst    (reset_sys),
        .i_5v     (1'b1),          // no +5V sense line
        .i_ready  (1'b1),
        .i_replug (replug_sync[1] && !replug_q),
        .o_hpd    (hpd),
        .o_5v_good()
    );

    // =================================================================
    // DVI receiver (eda/dvi_capture's PHY)
    // =================================================================
    wire cable_clk, serial_d0, serial_d1, serial_d2;
    TLVDS_IBUF u_ibuf_clk (.O(cable_clk), .I(dvi_clk_p), .IB(dvi_clk_n));
    TLVDS_IBUF u_ibuf_d0  (.O(serial_d0), .I(dvi_d0_p),  .IB(dvi_d0_n));
    TLVDS_IBUF u_ibuf_d1  (.O(serial_d1), .I(dvi_d1_p),  .IB(dvi_d1_n));
    TLVDS_IBUF u_ibuf_d2  (.O(serial_d2), .I(dvi_d2_p),  .IB(dvi_d2_n));

    logic pclk, fclk, pll_lock;
    gowin_pll_dvi pll_main (
        .clkout0(pclk),
        .clkout1(fclk),
        .lock   (pll_lock),
        .clkin  (cable_clk)
    );

    logic reset_pclk;
    reset_seq #(.RESET_DELAY_CYCLES(8)) reset_seq_pclk (
        .clock    (pclk),
        .reset_in (!pll_lock || reset_button),
        .reset_out(reset_pclk)
    );

    logic [7:0]  rx_offset;
    logic [7:0]  rx_lane_offset [0:2];
    logic [23:0] video_data;
    logic        video_de, video_hsync, video_vsync, video_valid, locked;
    logic [3:0]  video_ctl;
    logic [2:0]  decode_err;
    wire  [9:0]  dbg_word_d0, dbg_word_d1, dbg_word_d2;
    wire         dbg_align_shift;
    dvi_in_phy #(.DELAY_TAP_INIT(24)) u_phy (
        .i_delay_offset     (rx_offset),
        .i_delay_offset_lane(rx_lane_offset),
        .i_pclk             (pclk),
        .i_fclk             (fclk),
        .i_reset            (reset_pclk),
        .i_serial_d0        (serial_d0),
        .i_serial_d1        (serial_d1),
        .i_serial_d2        (serial_d2),
        .o_video_data       (video_data),
        .o_video_de         (video_de),
        .o_video_hsync      (video_hsync),
        .o_video_vsync      (video_vsync),
        .o_video_ctl        (video_ctl),
        .o_video_valid      (video_valid),
        .o_decode_err       (decode_err),
        .o_locked           (locked),
        .o_dbg_word_d0      (dbg_word_d0),
        .o_dbg_word_d1      (dbg_word_d1),
        .o_dbg_word_d2      (dbg_word_d2),
        .o_dbg_align_shift  (dbg_align_shift)
    );

    // =================================================================
    // Crop -> command FIFO -> Hub75
    // =================================================================
    // colour tables (gamma / white balance), written from the UART ("G", "i")
    logic       lut_init, lut_we;
    logic [2:0] lut_mask;
    logic [7:0] lut_addr, lut_data;
    logic                cmd_wen, frame_skipped;
    logic [CMD_BITS-1:0] cmd;
    logic                flip_pending;
    crop_to_hub75 #(
        .DISP_W        (DISP_W),
        .DISP_H        (DISP_H),
        .COMPONENT_BITS(COMPONENT_BITS)
    ) u_crop (
        .i_pclk         (pclk),
        .i_reset        (reset_pclk),
        .i_valid        (video_valid),
        .i_de           (video_de),
        .i_vsync        (video_vsync),
        .i_data         (video_data),
        .i_flip_pending (flip_pending),
        .o_cmd_wen      (cmd_wen),
        .o_cmd          (cmd),
        .o_frame_skipped(frame_skipped),
        .i_clk          (clock),
        .i_rst          (reset_sys),
        .i_lut_init     (lut_init),
        .i_lut_we       (lut_we),
        .i_lut_mask     (lut_mask),
        .i_lut_addr     (lut_addr),
        .i_lut_data     (lut_data),
        .o_lut_busy     ()
    );

    // 128 pixels arrive per line at 74.25 MHz and drain at 50 MHz: ~45
    // entries of backlog at most.
    logic                fifo_full, rd_empty, rd_valid;
    logic [CMD_BITS-1:0] rd_cmd;
    wire                 rd_en = !rd_empty;
    async_fifo #(.WIDTH(CMD_BITS), .DEPTH_BITS(6)) u_fifo (
        .i_wr_clk  (pclk),
        .i_wr_rst  (reset_pclk),
        .i_wr_en   (cmd_wen),
        .i_wr_data (cmd),
        .o_wr_full (fifo_full),
        .i_rd_clk  (clock),
        .i_rd_rst  (reset_sys),
        .i_rd_en   (rd_en),
        .o_rd_data (rd_cmd),
        .o_rd_empty(rd_empty)
    );
    always_ff @(posedge clock) rd_valid <= !reset_sys && rd_en;

    Hub75 #(
        .PANEL_WIDTH   (64),
        .PANEL_HEIGHT  (64),
        .NUM_CHAINED   (CHAIN_LEN / 64),
        .CLOCK_DIVIDER (`HUB75_CLKDIV),
        .CLK_LOW_EXTRA (`HUB75_CLKLOW),
        .COMPONENT_BITS(COMPONENT_BITS),
        .BASE_OE_CYCLES(16)
    ) u_hub75 (
        .i_clk         (clock),
        .i_rst         (reset_sys),
        .i_px_wen      (rd_valid && !rd_cmd[CMD_BITS-1]),
        .i_px_addr     (rd_cmd[CMD_BITS-2 -: ADDR_BITS]),
        .i_px_data     (rd_cmd[PX_BITS-1:0]),
        .i_flip_req    (rd_valid && rd_cmd[CMD_BITS-1]),
        .o_flip_pending(flip_pending),
        .o_row_a       (hub75_row_a),
        .o_row_b       (hub75_row_b),
        .o_row_c       (hub75_row_c),
        .o_row_d       (hub75_row_d),
        .o_row_e       (hub75_row_e),
        .o_r0          (hub75_r[0]),
        .o_g0          (hub75_g[0]),
        .o_b0          (hub75_b[0]),
        .o_r1          (hub75_r[1]),
        .o_g1          (hub75_g[1]),
        .o_b1          (hub75_b[1]),
        .o_oe          (hub75_oe),
        .o_lat         (hub75_lat),
        .o_clk         (hub75_clk)
    );

    // =================================================================
    // Diagnostics over the USB-UART (as eda/dvi_capture). Repurposed
    // fields: X = {SCL falling edges (14), SCL level, SDA level, EDID bytes
    // read (16)}, Y = {HPD, FIFO overflow count (15), skipped frames (8),
    // DDC offset}.
    // =================================================================
    logic        snap_req, snap_done, snap_locked, clear_req;
    logic [31:0] snap_frames, snap_bad, snap_derr, snap_last_count, snap_rx_cycles;
    logic [15:0] snap_unlock;
    logic [23:0] snap_lane_err [0:2];
    logic [7:0]  sys_offset;
    logic [7:0]  sys_lane_offset [0:2];
    logic        words_req, words_done;
    logic [1:0]  words_mode;
    logic [9:0]  words [0:2][0:11];
    logic [15:0] ddc_reads;
    always_ff @(posedge clock) begin
        if (reset_sys)            ddc_reads <= '0;
        else if (ddc_read_strobe) ddc_reads <= ddc_reads + 1'd1;
    end
    // DDC line monitor: synchronized levels and SCL falling edges
    logic [2:0]  scl_s, sda_s;
    logic [13:0] scl_falls;
    always_ff @(posedge clock) begin
        scl_s <= {scl_s[1:0], ddc_scl};
        sda_s <= {sda_s[1:0], ddc_sda_in};
        if (reset_sys)                                 scl_falls <= '0;
        else if (scl_s[2] && !scl_s[1] && scl_falls != '1) scl_falls <= scl_falls + 1'd1;
    end

    // FIFO overflow / skipped frames, counted in pclk and read quasi-statically
    logic [14:0] ovf_cnt;
    logic [7:0]  skip_cnt;
    always_ff @(posedge pclk) begin
        if (reset_pclk) begin
            ovf_cnt  <= '0;
            skip_cnt <= '0;
        end else begin
            if (cmd_wen && fifo_full && ovf_cnt != '1) ovf_cnt <= ovf_cnt + 1'd1;
            if (frame_skipped) skip_cnt <= skip_cnt + 1'd1;
        end
    end

    loop_check #(.EXT_CHECK(1'b1)) u_check (
        .rx_clk          (pclk),
        .rx_reset        (reset_pclk),
        .i_video_data    (video_data),
        .i_video_de      (video_de),
        .i_video_vsync   (video_vsync),
        .i_video_valid   (video_valid),
        .i_decode_err    (decode_err),
        .i_locked        (locked),
        .i_word0         (dbg_word_d0),
        .i_word1         (dbg_word_d1),
        .i_word2         (dbg_word_d2),
        .o_rx_offset     (rx_offset),
        .o_rx_lane_offset(rx_lane_offset),
        .o_frame_bad     (),
        .i_ext_bad       (1'b0),
        .i_tx_s1         ('0),
        .i_tx_s2         ('0),
        .i_tx_count      ('0),
        .i_tx_ref_valid  (1'b0),
        .sys_clk         (clock),
        .sys_snap_req    (snap_req),
        .sys_snap_done   (snap_done),
        .sys_locked      (snap_locked),
        .sys_frames      (snap_frames),
        .sys_bad         (snap_bad),
        .sys_derr        (snap_derr),
        .sys_unlock      (snap_unlock),
        .sys_last_count  (snap_last_count),
        .sys_lane_err    (snap_lane_err),
        .sys_rx_cycles   (snap_rx_cycles),
        .sys_pix_err     (),
        .sys_bit_err     (),
        .sys_lane_bit_err(),
        .sys_clear       (clear_req),
        .sys_words_req   (words_req),
        .sys_words_done  (words_done),
        .sys_words       (words),
        .sys_words_mode  (words_mode),
        .sys_offset      (sys_offset),
        .sys_lane_offset (sys_lane_offset)
    );

    loop_report #(.OFFSET_DEFAULT(8'd60)) u_report (
        .clock         (clock),
        .reset         (reset_sys),
        .uart_rxd      (uart_rxd),
        .uart_txd      (uart_txd),
        .o_offset      (sys_offset),
        .o_lane_offset (sys_lane_offset),
        .o_snap_req    (snap_req),
        .i_snap_done   (snap_done),
        .i_locked      (snap_locked),
        .i_frames      (snap_frames),
        .i_bad         (snap_bad),
        .i_derr        (snap_derr),
        .i_unlock      (snap_unlock),
        .i_last_count  (snap_last_count),
        .i_lane_err    (snap_lane_err),
        .i_rx_cycles   (snap_rx_cycles),
        .i_pll_lock    (pll_lock),
        .i_pix_err     ({scl_falls, scl_s[1], sda_s[1], ddc_reads}),
        .i_bit_err     ({hpd, ovf_cnt, skip_cnt, ddc_offset}),
        .i_lane_bit_err('{default: '0}),
        .o_clear       (clear_req),
        .o_words_req   (words_req),
        .o_words_mode  (words_mode),
        .o_lut_init    (lut_init),
        .o_lut_we      (lut_we),
        .o_lut_mask    (lut_mask),
        .o_lut_addr    (lut_addr),
        .o_lut_data    (lut_data),
        .i_words_done  (words_done),
        .i_words       (words)
    );

    // =================================================================
    // Status indicators (header pins 14 / 13)
    // =================================================================
    logic [22:0] err_stretch;
    always_ff @(posedge pclk) begin
        if (reset_pclk)              err_stretch <= '0;
        else if (|decode_err)        err_stretch <= '1;
        else if (err_stretch[22])    err_stretch <= err_stretch - 1'd1;
    end
    assign led_locked     = locked;
    assign led_decode_err = err_stretch[22];

    wire _unused = &{1'b0, video_hsync, video_ctl, dbg_align_shift};
endmodule
`default_nettype wire
