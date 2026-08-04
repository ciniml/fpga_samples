// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief Tang Primer 25K DVI receiver top.
 *
 *   Receives 720p60 DVI (F_pixel = 74.25 MHz) through a Sipeed Pmod DVI
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
    input  wire reset_button,

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
    // dbg[0] = frame CRC mismatch, stretched to ~110 us per bad frame.
    //          Pulse rate = corrupted frames per second (static source).
    // dbg[1] = per-line CRC mismatch vs previous frame (~3.4 us pulse
    //          per corrupted line; timing shows WHICH lines are hit)
    // dbg[2] = recovered video DE
    // dbg[3] = recovered video VSYNC (frame reference, 60 Hz)
    output logic [3:0] dbg
);

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
    gowin_pll_dvi pll_main (
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
    wire [7:0] cal_offset = 8'd32;

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
        .i_delay_offset(cal_offset),
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
        .o_dbg_align_shift(dbg_align_shift)
    );

    wire [9:0] dbg_word_d0;
    wire       dbg_align_shift;

    // Raw lane-0 control-symbol hit — the signal dvi_in now aligns on.
    wire dbg_d0_is_ctl = dbg_word_d0 == 10'b1101010100
                      || dbg_word_d0 == 10'b0010101011
                      || dbg_word_d0 == 10'b0101010100
                      || dbg_word_d0 == 10'b1010101011;

    // ------------------------------------------------------------------
    // Frame CRC checker. With a static test pattern on the source, every
    // frame must hash identically; a CRC change means at least one pixel
    // was corrupted in that frame. CRC32 (poly 04C11DB7) over RGB24
    // during DE, snapshotted and compared at each VSYNC rising edge.
    // ------------------------------------------------------------------
    function automatic [31:0] crc32_d24(input [31:0] c, input [23:0] d);
        logic [31:0] x;
        x = c;
        for (int i = 23; i >= 0; i--) begin
            if (x[31] ^ d[i]) x = {x[30:0], 1'b0} ^ 32'h04C11DB7;
            else              x = {x[30:0], 1'b0};
        end
        return x;
    endfunction

    logic [31:0] frame_crc;
    logic [31:0] frame_crc_prev;
    logic [1:0]  crc_warmup;       // skip partial frames right after lock
    logic        vsync_q;
    logic        crc_mismatch;
    logic [12:0] mism_stretch;     // ~110 us so the scope shows it easily

    always_ff @(posedge pclk) begin
        if (reset_pclk || !locked) begin
            frame_crc      <= 32'hFFFFFFFF;
            frame_crc_prev <= '0;
            crc_warmup     <= '0;
            vsync_q        <= 1'b0;
            crc_mismatch   <= 1'b0;
        end else begin
            crc_mismatch <= 1'b0;
            vsync_q      <= video_vsync;
            if (video_valid && video_de) begin
                frame_crc <= crc32_d24(frame_crc, video_data);
            end
            if (video_vsync && !vsync_q) begin
                if (crc_warmup == 2'd3) begin
                    if (frame_crc != frame_crc_prev) begin
                        crc_mismatch <= 1'b1;
                    end
                end else begin
                    crc_warmup <= crc_warmup + 1'd1;
                end
                frame_crc_prev <= frame_crc;
                frame_crc      <= 32'hFFFFFFFF;
            end
        end
    end

    always_ff @(posedge pclk) begin
        if (reset_pclk) begin
            mism_stretch <= '0;
        end else if (crc_mismatch) begin
            mism_stretch <= '1;
        end else if (mism_stretch != '0) begin
            mism_stretch <= mism_stretch - 1'd1;
        end
    end

    // ------------------------------------------------------------------
    // Culprit-word capture. o_video_de has 2 cycles of latency from the
    // raw deserializer words, so pipeline word_d0 by 2 to latch the
    // symbol that actually produced the spurious DE during VSYNC.
    // ------------------------------------------------------------------
    logic [9:0] w0_q1, w0_q2;
    logic [9:0] glitch_word;
    always_ff @(posedge pclk) begin
        if (reset_pclk) begin
            w0_q1       <= '0;
            w0_q2       <= '0;
            glitch_word <= '0;
        end else begin
            w0_q1 <= dbg_word_d0;
            w0_q2 <= w0_q1;
            if (video_valid && video_vsync && video_de) begin
                glitch_word <= w0_q2;
            end
        end
    end

    // ------------------------------------------------------------------
    // Per-line CRC comparison against the previous frame. One BRAM holds
    // last frame's line CRCs; each line end compares and pulses dbg[1]
    // on mismatch, so the LA shows how many lines per frame are hit and
    // at which vertical position.
    // ------------------------------------------------------------------
    logic [31:0] line_crc;
    logic [31:0] line_ram [0:1023];
    logic [31:0] line_ram_q;
    logic [9:0]  line_idx;
    logic        de_q;
    logic        line_cmp_pending;
    logic        frame_seen;
    logic        line_bad;
    logic [7:0]  line_bad_stretch;

    always_ff @(posedge pclk) begin
        if (reset_pclk || !locked) begin
            line_crc         <= 32'hFFFFFFFF;
            line_idx         <= '0;
            de_q             <= 1'b0;
            line_cmp_pending <= 1'b0;
            frame_seen       <= 1'b0;
            line_bad         <= 1'b0;
        end else begin
            line_bad <= 1'b0;
            de_q     <= video_de;
            if (video_valid && video_de) begin
                line_crc <= crc32_d24(line_crc, video_data);
            end
            if (de_q && !video_de) begin
                line_ram_q       <= line_ram[line_idx];
                line_cmp_pending <= 1'b1;
            end else if (line_cmp_pending) begin
                line_cmp_pending <= 1'b0;
                if (frame_seen && line_ram_q != line_crc) begin
                    line_bad <= 1'b1;
                end
                line_ram[line_idx] <= line_crc;
                line_crc           <= 32'hFFFFFFFF;
                line_idx           <= line_idx + 1'd1;
            end
            if (video_vsync && !vsync_q) begin
                if (line_idx != '0) begin
                    frame_seen <= 1'b1;
                end
                line_idx <= '0;
            end
        end
    end

    always_ff @(posedge pclk) begin
        if (reset_pclk) begin
            line_bad_stretch <= '0;
        end else if (line_bad) begin
            line_bad_stretch <= '1;
        end else if (line_bad_stretch != '0) begin
            line_bad_stretch <= line_bad_stretch - 1'd1;
        end
    end

    always_ff @(posedge pclk) begin
        dbg[0]   <= mism_stretch != '0;
        dbg[1]   <= line_bad_stretch != '0;
        dbg[2]   <= video_de;
        dbg[3]   <= video_vsync;
    end

    wire _unused_glitch = &glitch_word;

    wire _unused_dbg = &{dbg_d0_is_ctl, dbg_align_shift, video_hsync, video_ctl};

    // -----------------------------------------------------------------
    // Status indicators. decode_err is a single-pclk pulse per bad
    // symbol; stretch it to ~0.11 s (2^23 / 74.25 MHz) so it is visible.
    // -----------------------------------------------------------------
    logic [22:0] err_stretch;
    always_ff @(posedge pclk) begin
        if (reset_pclk) begin
            err_stretch <= '0;
        end else if (|decode_err) begin
            err_stretch <= '1;
        end else if (err_stretch != '0) begin
            err_stretch <= err_stretch - 1'd1;
        end
    end

    assign led_locked     = locked;
    assign led_decode_err = err_stretch != '0;

endmodule
`default_nettype wire
