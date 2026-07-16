/**
 * @file top.sv
 * @brief Top module for the DisplayPort test-pattern-generator design
 *        on the Tang Primer 25K (Sipeed Pmod DP module).
 *
 *        Wires up the full DisplayPort source IP (`dp_source_top`) with a
 *        Gowin OSER10-based serializer for lane 0:
 *
 *          - AUX CH subsystem (Manchester-II via TLVDS_IOBUF)
 *          - HPD input (LVCMOS25)
 *          - Test pattern generator (rtl/video) → AXI-Stream pixel input
 *          - dp_source_top in CONTINUOUS_BYTE_TICK mode (one symbol per
 *            byte clock) → 10-bit encoder symbol → OSER10 → TLVDS_OBUF
 *
 *        Clocking (DP RBR = 1.62 Gbps target):
 *          gowin_pll_27 : 50 MHz board → 27 MHz (clock_27, AUX subsystem)
 *          gowin_pll    : 27 MHz → clock_byte (162 MHz, OSER10 PCLK)
 *                                   clock_serial (810 MHz, OSER10 FCLK,
 *                                                 DDR → 1.62 Gbps)
 *
 *        Video: 800x600 active in a 1200x750 raster (board firmware
 *        profile, `--features board`). The byte-rate framer makes the
 *        effective pixel clock LS_Clk/3 = 54 MHz, so the frame rate is
 *        exactly 60 Hz. The TPG is demand-paced through tpg_to_axis
 *        (raster advances only when the DP IP accepts a pixel during DE,
 *        free-runs through blanking), so no pixels are ever dropped.
 *
 *        Lanes 1..3 are unused (held low). For multi-lane operation
 *        replicate the OSER10 + TLVDS_OBUF block per lane.
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
    // -----------------------------------------------------------------
    logic clock_27;
    logic clock_byte;     // OSER10 PCLK; main-link byte clock (162 MHz)
    logic clock_serial;   // OSER10 FCLK = 5 × clock_byte (810 MHz)
    logic pll_lock;
    logic pll_lock_27;

    gowin_pll_27 pll_27 (
        .clkout0(clock_27),
        .lock   (pll_lock_27),
        .clkin  (clock)
    );
    gowin_pll pll_dp (
        .clkout0(clock_byte),
        .clkout1(clock_serial),
        .lock   (pll_lock),
        .clkin  (clock_27)
    );

    // -----------------------------------------------------------------
    // Resets
    // -----------------------------------------------------------------
    logic reset_byte;
    reset_seq #(.RESET_DELAY_CYCLES(4)) reset_seq_byte (
        .clock   (clock_byte),
        .reset_in(!pll_lock_27 || !pll_lock || reset_button),
        .reset_out(reset_byte)
    );

    // -----------------------------------------------------------------
    // Test pattern generator, demand-paced on the byte clock: the active
    // area matches the firmware board profile (800x600); the TPG's own
    // blanking is kept minimal since tpg_to_axis stalls the raster
    // whenever the DP IP is not accepting pixels (the DP raster timing
    // lives in the firmware MSA profile, not here).
    // -----------------------------------------------------------------
    localparam int HSYNC   = 8;
    localparam int HBACK   = 8;
    localparam int HACTIVE = 800;
    localparam int HFRONT  = 8;
    localparam int VSYNC   = 2;
    localparam int VBACK   = 2;
    localparam int VACTIVE = 600;
    localparam int VFRONT  = 2;

    logic [23:0] tpg_video_data;
    logic        tpg_video_de;
    logic        tpg_video_hsync;
    logic        tpg_video_vsync;
    logic        tpg_enable;

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
        .clock     (clock_byte),
        .reset     (reset_byte),
        .enable    (tpg_enable),
        .video_data(tpg_video_data),
        .video_de  (tpg_video_de),
        .video_hsync(tpg_video_hsync),
        .video_vsync(tpg_video_vsync)
    );

    logic        pix_tvalid;
    logic        pix_tready;
    logic [23:0] pix_tdata;

    tpg_to_axis tpg_axis (
        .clock        (clock_byte),
        .reset        (reset_byte),
        .video_data   (tpg_video_data),
        .video_de     (tpg_video_de),
        .tpg_enable   (tpg_enable),
        .m_axis_tvalid(pix_tvalid),
        .m_axis_tready(pix_tready),
        .m_axis_tdata (pix_tdata)
    );

    // -----------------------------------------------------------------
    // AUX CH differential I/O.
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
    // DisplayPort source IP. CONTINUOUS_BYTE_TICK = 1 makes the encoder
    // emit one symbol per clock_byte cycle, exactly matching OSER10's
    // PCLK consumption rate.
    // -----------------------------------------------------------------
    localparam int CLOCK_HZ_BYTE = 162_000_000;

    logic [31:0] cpu_io_out;

    logic        debug_serial_tvalid;
    logic        debug_serial_tready;
    logic [7:0]  debug_serial_tdata;

    logic        lane0_bit;
    logic        lane0_bit_valid;
    logic        lane0_symbol_valid;
    logic [9:0]  lane0_symbol;

    displayport_dp_source_top #(
        .CLOCK_HZ           (CLOCK_HZ_BYTE),
        .MANCHESTER_CLOCK_HZ(32'd1_000_000),
        .PRECHARGE_CYCLES   (32'd16),
        .BUFFER_SIZE        (256),
        .DEBUG_OUT          (1'b0),
        .PROCESSOR_ID       (32'd0),
        .PROCESSOR_ROM_SIZE (32'd16384),
        .PROCESSOR_RAM_SIZE (32'd8192),
        .PROCESSOR_ROM_FILE ("/home/kenta/repos/fpga_samples/rtl/displayport/test/sw-rs/bootrom-rs-board.hex"),
        .SR_PERIOD          (32'd512),
        .CONTINUOUS_BYTE_TICK(32'd1)
    ) dp_source (
        .i_clk (clock_byte),
        .i_rstn(!reset_byte),

        .aux_ch_in        (aux_ch_in_drv),
        .aux_ch_out       (aux_ch_out),
        .aux_ch_out_enable(aux_ch_out_enable),

        .hpd_in           (hotplug),

        .cpu_io_out       (cpu_io_out),

        .saxis_serial_in_tvalid(1'b0),
        .saxis_serial_in_tready(),
        .saxis_serial_in_tdata (8'h00),

        .maxis_serial_out_tvalid(debug_serial_tvalid),
        .maxis_serial_out_tready(debug_serial_tready),
        .maxis_serial_out_tdata (debug_serial_tdata),

        // Behavioural serializer outputs are unused on the FPGA path.
        .o_lane0_bit         (lane0_bit),
        .o_lane0_bit_valid   (lane0_bit_valid),

        // Drive OSER10 from the encoder's 10-bit symbol.
        .o_lane0_symbol_valid(lane0_symbol_valid),
        .o_lane0_symbol      (lane0_symbol),

        .s_axis_video_tvalid(pix_tvalid),
        .s_axis_video_tready(pix_tready),
        .s_axis_video_tdata (pix_tdata)
    );

    // -----------------------------------------------------------------
    // Lane 0 OSER10 + LVDS output. Bit rate = 10 × clock_byte = 1.62 Gbps.
    // -----------------------------------------------------------------
    wire lane0_serial;

    oser10_lane lane0_serdes (
        .i_pclk        (clock_byte),
        .i_fclk        (clock_serial),
        .i_reset       (reset_byte),
        .i_symbol_valid(lane0_symbol_valid),
        .i_symbol      (lane0_symbol),
        .o_serial      (lane0_serial)
    );

    TLVDS_OBUF lane0_obuf (
        .I (lane0_serial),
        .O (ml_lane_0_p),
        .OB(ml_lane_0_n)
    );

    // Park unused lanes.
    assign ml_lane_1_p = 1'b0;
    assign ml_lane_1_n = 1'b0;
    assign ml_lane_2_p = 1'b0;
    assign ml_lane_2_n = 1'b0;
    assign ml_lane_3_p = 1'b0;
    assign ml_lane_3_n = 1'b0;

    // -----------------------------------------------------------------
    // UART debug bridge. Firmware $write goes out the byte-serial
    // interface; route it to the on-board UART pad.
    // -----------------------------------------------------------------
    uart_tx #(
        .NUMBER_OF_BITS(8),
        .BAUD_DIVIDER(CLOCK_HZ_BYTE / 32'd115_200)
    ) debug_uart_tx_inst (
        .clock(clock_byte),
        .reset(reset_byte),

        .data_valid(debug_serial_tvalid),
        .data_ready(debug_serial_tready),
        .data_bits (debug_serial_tdata),

        .tx        (uart_tx)
    );

endmodule
`default_nettype wire
