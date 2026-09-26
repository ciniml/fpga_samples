// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief Tang Primer 25K DVI receiver top.
 *
 *   Receives 720p60 DVI (F_pixel = 74.25 MHz; `define RATE_1080P for
 *   1080p60 at 148.5 MHz, make RATE=1080P) through a Sipeed Pmod DVI
 *   module on PMOD1, from a Tang Nano 9K running eda/dvi_out_tpg.
 *
 *   Clocking is source-synchronous: the cable CLK pair is buffered once
 *   (TLVDS_IBUF) and drives both the recovery PLL (74.25 MHz pclk +
 *   371.25 MHz fclk from the same VCO) and the clock-lane deserializer
 *   inside dvi_in_phy, which dvi_in uses for word-boundary lock.
 *
 *   Status: led_locked = dvi_in word lock, led_decode_err = any lane
 *   decode error within the last ~0.1 s (pulse-stretched so the LED is
 *   visible).
 */
`default_nettype none
module top(
    input  wire clock,          // 50 MHz board clock (DDC / HPD side channel)
    input  wire reset_button,
    input  wire button_replug,  // S1: drop HPD for 200 ms (EDID re-read)

    // DVI input — four differential pairs (CLK + 3 data) on PMOD1.
    input  wire dvi_clk_p,
    input  wire dvi_clk_n,
    input  wire dvi_d0_p,
    input  wire dvi_d0_n,
    input  wire dvi_d1_p,
    input  wire dvi_d1_n,
    input  wire dvi_d2_p,
    input  wire dvi_d2_n,

    // Status indicators.
    output logic led_locked,
    output logic led_decode_err,

    // Verification taps on PMOD1 (scope these):
    // dbg[0] = frame differs from the previous one (pixel-sum compare),
    //          stretched. Pulse rate = changed frames per second
    //          (static source: corrupted frames).
    // dbg[1] = a decode error in this clock
    // dbg[2] = recovered video DE
    // dbg[3] = recovered video VSYNC (frame reference, 60 Hz)
    output logic [3:0] dbg,

    // HDMI/DVI side channel (Pmod DVI side-channel pads, wired to pmod2).
    // DDC is a 5 V bus: use a level shifter / clamp between the Pmod and
    // these 3.3 V pins.
    input  wire  ddc_scl,
    inout  wire  ddc_sda,
    output logic hpd,

    // Status line once per second (USB-UART, 115200 8N1; cap_status.sv)
    output wire  uart_txd,
    input  wire  uart_rxd
);

    // -----------------------------------------------------------------
    // Side channel: EDID over DDC and HPD, on the board clock. It has to
    // work before the source drives TMDS (the pixel clock only exists
    // after HPD is up and the EDID has been read).
    // -----------------------------------------------------------------
    logic reset_sys;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_sys (
        .clock    (clock),
        .reset_in (reset_button),
        .reset_out(reset_sys)
    );

    wire  ddc_sda_in;
    logic ddc_sda_oe;
    IOBUF u_ddc_sda (.O(ddc_sda_in), .IO(ddc_sda), .I(1'b0), .OEN(!ddc_sda_oe));

    logic ddc_busy;
    logic ddc_read_strobe;
    logic [7:0] ddc_offset;
`ifdef RATE_1080P
    ddc_edid #(.EDID_1080P(1'b1)) u_ddc (
`else
    ddc_edid u_ddc (
`endif
        .i_clk        (clock),
        .i_rst        (reset_sys),
        .i_scl        (ddc_scl),
        .i_sda        (ddc_sda_in),
        .o_sda_oe     (ddc_sda_oe),
        .o_busy       (ddc_busy),
        .o_read_strobe(ddc_read_strobe),
        .o_offset     (ddc_offset)
    );

    // No +5V sense line on the Pmod: treat +5V as always present; HPD goes
    // high once the side channel is out of reset (after the minimum low
    // time), and S1 forces a replug.
    logic [1:0] replug_sync;
    logic       replug_q;
    always_ff @(posedge clock) begin
        replug_sync <= {replug_sync[0], button_replug};
        replug_q    <= replug_sync[1];
    end
    hpd_ctrl u_hpd (
        .i_clk    (clock),
        .i_rst    (reset_sys),
        .i_5v     (1'b1),
        .i_ready  (1'b1),
        .i_replug (replug_sync[1] && !replug_q),
        .o_hpd    (hpd),
        .o_5v_good()
    );

    wire _unused_ddc = &{1'b0, ddc_busy};

    // -----------------------------------------------------------------
    // Input buffers. The clock-lane IBUF output fans out to both the
    // recovery PLL and dvi_in_phy's clock-lane deserializer, which is
    // why the IBUFs live here rather than inside iser10_lane.
    // -----------------------------------------------------------------
    wire cable_clk;
    wire serial_d0;
    wire serial_d1;
    wire serial_d2;

    TLVDS_IBUF u_ibuf_clk (.O(cable_clk), .I(dvi_clk_p), .IB(dvi_clk_n));
    TLVDS_IBUF u_ibuf_d0  (.O(serial_d0), .I(dvi_d0_p),  .IB(dvi_d0_n));
    TLVDS_IBUF u_ibuf_d1  (.O(serial_d1), .I(dvi_d1_p),  .IB(dvi_d1_n));
    TLVDS_IBUF u_ibuf_d2  (.O(serial_d2), .I(dvi_d2_p),  .IB(dvi_d2_n));

    // -----------------------------------------------------------------
    // Clock recovery: pclk (74.25 MHz) and fclk (5x, 371.25 MHz) are
    // both divided from the same VCO locked to the cable clock, keeping
    // the IDES10 PCLK/FCLK phase relation.
    // -----------------------------------------------------------------
    logic pclk;
    logic fclk;
    logic pll_lock;
`ifdef RATE_1080P
    // 1080p60: 148.5 MHz cable clock -> 148.5 / 742.5 MHz (VCO 742.5,
    // eda/dvi_loopback's pll_rx_1080p)
    pll_rx_1080p pll_main (
`else
    gowin_pll_dvi pll_main (
`endif
        .clkout0(pclk),
        .clkout1(fclk),
        .lock   (pll_lock),
        .clkin  (cable_clk)
    );

    // -----------------------------------------------------------------
    // Reset. Held while the PLL is unlocked (cable absent) so the whole
    // receiver restarts on cable plug-in.
    // -----------------------------------------------------------------
    logic reset_pclk;
    reset_seq #(.RESET_DELAY_CYCLES(8)) reset_seq_pclk (
        .clock    (pclk),
        .reset_in (!pll_lock || reset_button),
        .reset_out(reset_pclk)
    );

    // -----------------------------------------------------------------
    // Automatic sampling-phase calibration. Once word lock is reached,
    // sweep the shared IODELAY offset over the full DLYSTEP range in 32
    // steps (8 taps ≈ 0.1 ns each, ~28 ms dwell per step, errors only
    // counted while locked) and settle on the offset with the fewest
    // decode errors. Total scan ≈ 1 s after lock; reruns on reset.
    // -----------------------------------------------------------------
    // Sampling phase for the PMOD0 slot, from the 2026-08 button-swept
    // eye map (base tap 24, +32 DLYSTEP per step, line-CRC error rate):
    //   +0 edge/storm, +32 CLEAN, +64 storm, +96 low, +128 CLEAN,
    //   +160 storm, +192 low, +224 CLEAN
    // Clean spots repeat every ~96 taps = one bit period (1.35 ns), so
    // one tap is ~14 ps. Effective DLYSTEP = 24 + 32 = 56: the earliest
    // clean spot (minimal delay-line jitter). The dvi_in tap interface
    // is 5 bits wide, hence the extra fixed offset here rather than a
    // larger DELAY_TAP_INIT.
    // (The offset now comes from the UART reporter, default 0x3C; per-lane
    //  trims are added on top.)
    logic [7:0] rx_offset;
    logic [7:0] rx_lane_offset [0:2];

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

    // DELAY_TAP_INIT = 24: slightly later than the minimal 16 — cleans
    // up VSYNC falling-edge jitter observed at tap 16 (2026-08 bring-up).
    dvi_in_phy #(.DELAY_TAP_INIT(24)) u_phy (
        .i_delay_offset(rx_offset),
        .i_delay_offset_lane(rx_lane_offset),
        .i_pclk       (pclk),
        .i_fclk       (fclk),
        .i_reset      (reset_pclk),
        .i_serial_d0  (serial_d0),
        .i_serial_d1  (serial_d1),
        .i_serial_d2  (serial_d2),
        .o_video_data (video_data),
        .o_video_de   (video_de),
        .o_video_hsync(video_hsync),
        .o_video_vsync(video_vsync),
        .o_video_ctl  (video_ctl),
        .o_video_valid(video_valid),
        .o_decode_err (decode_err),
        .o_locked     (locked),
        .o_dbg_word_d0    (dbg_word_d0),
        .o_dbg_word_d1    (dbg_word_d1),
        .o_dbg_word_d2    (dbg_word_d2),
        .o_dbg_align_shift(dbg_align_shift)
    );

    wire [9:0] dbg_word_d0;
    wire [9:0] dbg_word_d1;
    wire [9:0] dbg_word_d2;
    wire       dbg_align_shift;

    // ------------------------------------------------------------------
    // Scope taps. Frame check: loop_check compares each frame's pixel sum
    // with the previous frame's (a static screen gives no pulses).
    // ------------------------------------------------------------------
    logic        frame_bad;
    logic [13:0] bad_stretch;    // ~110 us at 148.5 MHz, ~220 us at 74.25 MHz
    always_ff @(posedge pclk) begin
        if (reset_pclk)                bad_stretch <= '0;
        else if (frame_bad)            bad_stretch <= '1;
        else if (bad_stretch != '0)    bad_stretch <= bad_stretch - 1'd1;
        dbg[0] <= bad_stretch != '0;
        dbg[1] <= video_valid && |decode_err;
        dbg[2] <= video_de;
        dbg[3] <= video_vsync;
    end

    wire _unused_dbg = &{1'b0, dbg_align_shift, video_hsync, video_ctl};

    // -----------------------------------------------------------------
    // Status indicators. decode_err is a single-pclk pulse per bad
    // symbol; stretch it to ~0.11 s (2^23 / 74.25 MHz) so it is visible.
    // -----------------------------------------------------------------
    // (the MSB is the LED: counting down from all ones keeps it lit for
    //  2^22 clocks without a wide zero compare in the enable path)
    logic [22:0] err_stretch;
    always_ff @(posedge pclk) begin
        if (reset_pclk) begin
            err_stretch <= '0;
        end else if (|decode_err) begin
            err_stretch <= '1;
        end else if (err_stretch[22]) begin
            err_stretch <= err_stretch - 1'd1;
        end
    end

    // -----------------------------------------------------------------
    // Diagnostics over the USB-UART: eda/dvi_loopback's checker (without a
    // transmitter reference) and reporter. See README "UART".
    // Repurposed fields: X = EDID bytes read by the source,
    // Y = {HPD, 23'b0, DDC offset}. Z0-Z2 stay 0 (no pixel reference).
    // -----------------------------------------------------------------
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
        .o_frame_bad     (frame_bad),
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

    // Defaults from a notebook PC source over HDMI with CTLE=HIGH:
    //  720p:  offset 0x3C (DLYSTEP 24 + 60), centre of the error-free
    //         window 0x20..0x58; no lane trims needed.
    //  1080p: offset 0x30 with trims B -1 / G +3 / R -7 (the window is
    //         only ~2 steps wide and lane 2 sits ~7 taps early).
`ifdef RATE_1080P
    loop_report #(.OFFSET_DEFAULT(8'h30), .TRIM_DEFAULT(24'hFF03F9)) u_report (
`else
    loop_report #(.OFFSET_DEFAULT(8'd60)) u_report (
`endif
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
        .i_pix_err     ({16'd0, ddc_reads}),
        .i_bit_err     ({hpd, 23'd0, ddc_offset}),
        .i_lane_bit_err('{default: '0}),
        .o_clear       (clear_req),
        .o_words_req   (words_req),
        .o_words_mode  (words_mode),
        .i_words_done  (words_done),
        .i_words       (words)
    );

    assign led_locked     = locked;
    assign led_decode_err = err_stretch[22];

endmodule
`default_nettype wire
