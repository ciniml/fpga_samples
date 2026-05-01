/**
 * @file top.sv
 * @brief Top module for the DisplayPort test-pattern-generator design
 *        on the Tang Primer 25K (Sipeed Pmod DP module).
 *
 *        Wires up the full DisplayPort source IP (`dp_source_top`):
 *          - AUX CH subsystem (Manchester-II via TLVDS_IOBUF)
 *          - HPD input (LVCMOS25)
 *          - 1-lane main link (lane 0) serial bit driven via TLVDS_OBUF
 *          - 24bpp test pattern generator (rtl/video) feeding pixel data
 *
 *        IMPORTANT: this is a STRUCTURAL bring-up. The on-chip behavioural
 *        `serializer_10to1` emits one bit per system clock cycle, so the
 *        actual line rate is ~clock_dvi (one bit per cycle), NOT DP RBR
 *        1.62 Gbps. To reach RBR a Gowin OSER10 wrapper is needed; this
 *        TODO is left for a follow-up phase. The current build:
 *          - Confirms the toolchain accepts the full IP
 *          - Lets us validate the AUX CH transactions on real hardware
 *            against a DP monitor or AUX analyzer
 *          - Lane bits will be present but at a non-standard rate that
 *            no real DP sink will lock to
 *
 *        Lanes 1..3 are unused and held low.
 */
// Copyright 2026 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top(
    input wire clock,
    input wire reset_button,

    // DisplayPort Main Link lanes
    output logic ml_lane_0_p,
    output logic ml_lane_0_n,
    output logic ml_lane_1_p,
    output logic ml_lane_1_n,
    output logic ml_lane_2_p,
    output logic ml_lane_2_n,
    output logic ml_lane_3_p,
    output logic ml_lane_3_n,

    inout wire logic aux_ch_p,
    inout wire logic aux_ch_n,

    input wire hotplug,

    output logic uart_tx,
    output logic aux_ch_received
);

    // -----------------------------------------------------------------
    // Clocking
    //
    //   gowin_pll_27 : 50 MHz board clock → 27 MHz (AUX subsystem clk)
    //   gowin_pll    : 27 MHz → clock_dvi (pixel + DP main-link byte clk)
    //                            clock_dvi_ser (5x serial clk, reserved
    //                            for a future OSER10 wrapper)
    // -----------------------------------------------------------------
    logic clock_27;
    logic clock_dvi;
    logic clock_dvi_ser;
    logic pll_lock;
    logic pll_lock_27;

    gowin_pll_27 pll_27 (
        .clkout0(clock_27),
        .lock   (pll_lock_27),
        .clkin  (clock)
    );
    gowin_pll pll_dvi (
        .clkout0(clock_dvi),
        .clkout1(clock_dvi_ser),
        .lock   (pll_lock),
        .clkin  (clock_27)
    );

    // -----------------------------------------------------------------
    // Resets
    // -----------------------------------------------------------------
    logic reset_27;
    reset_seq reset_seq_27 (
        .clock   (clock_27),
        .reset_in(!pll_lock_27 || reset_button),
        .reset_out(reset_27)
    );
    logic reset_dvi;
    reset_seq #(.RESET_DELAY_CYCLES(4)) reset_seq_dvi (
        .clock   (clock_dvi),
        .reset_in(!pll_lock_27 || !pll_lock || reset_button),
        .reset_out(reset_dvi)
    );

    // -----------------------------------------------------------------
    // Test pattern generator (clocked from clock_dvi).
    // 1280x720@60 timing — see test_pattern_generator.sv for active /
    // blanking parameters.
    // -----------------------------------------------------------------
    localparam int HSYNC   = 40;
    localparam int HBACK   = 220;
    localparam int HACTIVE = 1280;
    localparam int HFRONT  = 110;
    localparam int VSYNC   = 5;
    localparam int VBACK   = 20;
    localparam int VACTIVE = 720;
    localparam int VFRONT  = 5;
    localparam int HTOTAL  = HSYNC + HBACK + HACTIVE + HFRONT;
    localparam int VTOTAL  = VSYNC + VBACK + VACTIVE + VFRONT;

    logic [23:0] tpg_video_data;
    logic        tpg_video_de;
    logic        tpg_video_hsync;
    logic        tpg_video_vsync;

    test_pattern_generator #(
        .HSYNC  (HSYNC),
        .HBACK  (HBACK),
        .HACTIVE(HACTIVE),
        .HFRONT (HFRONT),
        .VSYNC  (VSYNC),
        .VBACK  (VBACK),
        .VACTIVE(VACTIVE),
        .VFRONT (VFRONT),
        .BOUNCE_LOGO(0),
        .LOGO_PATH  (""),
        .LOGO_WIDTH (24),
        .LOGO_HEIGHT(24)
    ) tpg_inst (
        .clock     (clock_dvi),
        .reset     (reset_dvi),
        .video_data(tpg_video_data),
        .video_de  (tpg_video_de),
        .video_hsync(tpg_video_hsync),
        .video_vsync(tpg_video_vsync)
    );

    // TPG → AXI-Stream pixel bus (DE-gated, 24bpp RGB).
    logic        pix_tvalid;
    logic        pix_tready;
    logic [23:0] pix_tdata;

    tpg_to_axis tpg_axis (
        .clock        (clock_dvi),
        .reset        (reset_dvi),
        .video_data   (tpg_video_data),
        .video_de     (tpg_video_de),
        .m_axis_tvalid(pix_tvalid),
        .m_axis_tready(pix_tready),
        .m_axis_tdata (pix_tdata)
    );

    // -----------------------------------------------------------------
    // AUX CH differential I/O. The Gowin TLVDS_IOBUF accepts an O drive
    // (when output enabled), and exposes the differential pad on IO/IOB.
    // Bias and ESD network for the DP AUX_P/N pair lives on the Sipeed
    // Pmod DP module.
    // -----------------------------------------------------------------
    logic aux_ch_in_drv;
    logic aux_ch_out;
    logic aux_ch_out_enable;

    TLVDS_IOBUF aux_ch_lvds_iobuf (
        .I  (aux_ch_out),
        .OEN(!aux_ch_out_enable),
        .O  (aux_ch_in_drv),
        .IO (aux_ch_p),
        .IOB(aux_ch_n)
    );
    assign aux_ch_received = aux_ch_in_drv;

    // -----------------------------------------------------------------
    // DisplayPort source IP. Runs on clock_dvi (pixel + byte clock) so
    // the main link, AUX CH, and TPG share one clock domain — easiest
    // for first-build correctness. AUX baud (1 MHz Manchester) is
    // generated from CLOCK_HZ via the on-chip divider.
    // -----------------------------------------------------------------
    localparam int CLOCK_HZ_DVI = 162_000_000;     // adjust to actual gowin_pll output

    logic [31:0] cpu_io_out;

    logic        debug_serial_tvalid;
    logic        debug_serial_tready;
    logic [7:0]  debug_serial_tdata;

    logic        lane0_bit;
    logic        lane0_bit_valid;

    displayport_dp_source_top #(
        .CLOCK_HZ           (CLOCK_HZ_DVI),
        .MANCHESTER_CLOCK_HZ(32'd1_000_000),
        .PRECHARGE_CYCLES   (32'd16),
        .BUFFER_SIZE        (256),
        .DEBUG_OUT          (1'b0),
        .PROCESSOR_ID       (32'd0),
        .PROCESSOR_ROM_SIZE (32'd16384),
        .PROCESSOR_RAM_SIZE (32'd8192),
        .PROCESSOR_ROM_FILE ("/home/kenta/repos/fpga_samples/rtl/displayport/test/sw-rs/bootrom-rs.hex"),
        .SR_PERIOD          (32'd512)
    ) dp_source (
        .i_clk (clock_dvi),
        .i_rstn(!reset_dvi),

        .aux_ch_in        (aux_ch_in_drv),
        .aux_ch_out       (aux_ch_out),
        .aux_ch_out_enable(aux_ch_out_enable),

        .hpd_in           (hotplug),

        .cpu_io_out       (cpu_io_out),

        // No firmware-loader serial input on this board.
        .saxis_serial_in_tvalid(1'b0),
        .saxis_serial_in_tready(),
        .saxis_serial_in_tdata (8'h00),

        .maxis_serial_out_tvalid(debug_serial_tvalid),
        .maxis_serial_out_tready(debug_serial_tready),
        .maxis_serial_out_tdata (debug_serial_tdata),

        .o_lane0_bit      (lane0_bit),
        .o_lane0_bit_valid(lane0_bit_valid),

        .s_axis_video_tvalid(pix_tvalid),
        .s_axis_video_tready(pix_tready),
        .s_axis_video_tdata (pix_tdata)
    );

    // -----------------------------------------------------------------
    // Lane 0 differential output. The behavioural serializer_10to1
    // streams one bit per system clock cycle on `lane0_bit`. We forward
    // it to the DP_LANE0 differential pair via TLVDS_OBUF. Lanes 1..3
    // are unused.
    //
    // NOTE: the on-the-wire bit rate equals clock_dvi here, NOT 1.62
    // Gbps. Replace serializer_10to1 with a Gowin OSER10 wrapper to
    // reach DP RBR. See header.
    // -----------------------------------------------------------------
    logic lane0_drive;
    always_ff @(posedge clock_dvi) begin
        if (reset_dvi) lane0_drive <= 1'b0;
        else           lane0_drive <= lane0_bit_valid ? lane0_bit : 1'b0;
    end

    TLVDS_OBUF lane0_obuf (
        .I (lane0_drive),
        .O (ml_lane_0_p),
        .OB(ml_lane_0_n)
    );

    // Park unused lanes. (Tying both halves of an LVDS pair to 0 is
    // benign for the DP receiver; the link will simply train down to
    // 1 lane via the AUX CH.)
    assign ml_lane_1_p = 1'b0;
    assign ml_lane_1_n = 1'b0;
    assign ml_lane_2_p = 1'b0;
    assign ml_lane_2_n = 1'b0;
    assign ml_lane_3_p = 1'b0;
    assign ml_lane_3_n = 1'b0;

    // -----------------------------------------------------------------
    // UART debug bridge. Firmware $write goes out the lane0 byte
    // serial-out interface; route it to the on-board UART pad.
    // -----------------------------------------------------------------
    uart_tx #(
        .NUMBER_OF_BITS(8),
        .BAUD_DIVIDER(CLOCK_HZ_DVI / 32'd115_200)
    ) debug_uart_tx_inst (
        .clock(clock_dvi),
        .reset(reset_dvi),

        .data_valid(debug_serial_tvalid),
        .data_ready(debug_serial_tready),
        .data_bits (debug_serial_tdata),

        .tx        (uart_tx)
    );

endmodule
`default_nettype wire
