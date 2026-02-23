/**
 * @file top.sv
 * @brief Top module for DVI test pattern generator design.
 */
// Copyright 2022 Kenta IDA
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

logic clock_dvi;
logic clock_dvi_ser;
logic pll_lock;
logic pll_lock_27;

logic reset_27;
logic reset_ext;
reset_seq reset_seq_27(
  .clock(clock_27),
  .reset_in(!pll_lock_27 || reset_button),
  .reset_out(reset_27)
);

reset_seq reset_seq_ext(
  .clock(clock_dvi),
  .reset_in(!pll_lock_27 || !pll_lock),
  .reset_out(reset_ext)
);

logic clock_27;
gowin_pll_27 pll_27(
    .clkout0(clock_27), //output clkout
    .lock(pll_lock_27), //output lock
    .clkin(clock) //input clkin
);
gowin_pll pll_dvi(
    .clkout0(clock_dvi),
    .clkout1(clock_dvi_ser),
    .lock(pll_lock), //output lock
    .clkin(clock_27) //input clkin
);

// 1280x720 60
// localparam int HSYNC = 40;
// localparam int HBACK = 220;
// localparam int HACTIVE = 1280;
// localparam int HFRONT = 110;
// localparam int VSYNC = 5;
// localparam int VBACK = 20;
// localparam int VACTIVE = 720;
// localparam int VFRONT = 5;

// 1920x1080 60
// localparam int HSYNC = 44;
// localparam int HBACK = 148;
// localparam int HACTIVE = 1920;
// localparam int HFRONT = 88;
// localparam int VSYNC = 5;
// localparam int VBACK = 36;
// localparam int VACTIVE = 1080;
// localparam int VFRONT = 4;

// 1600x1200 60
localparam int HSYNC = 192;
localparam int HBACK = 304;
localparam int HACTIVE = 1600;
localparam int HFRONT = 64;
localparam int VSYNC = 3;
localparam int VBACK = 46;
localparam int VACTIVE = 1200;
localparam int VFRONT = 1;

logic reset_dvi;
reset_seq #( .RESET_DELAY_CYCLES(4) ) reset_seq_dvi(
  .clock(clock_dvi),
  .reset_in(reset_ext),
  .reset_out(reset_dvi)
);

always_comb begin
  ml_lane_0_p = 1'b0;
  ml_lane_0_n = 1'b0;
  ml_lane_1_p = 1'b0;
  ml_lane_1_n = 1'b0;
  ml_lane_2_p = 1'b0;
  ml_lane_2_n = 1'b0;
  ml_lane_3_p = 1'b0;
  ml_lane_3_n = 1'b0;
end

logic aux_ch_in;
logic aux_ch_out;
logic aux_ch_out_enable;
logic       maxis_serial_out_tvalid;
logic       maxis_serial_out_tready;
logic [7:0] maxis_serial_out_tdata;
displayport_aux_ch_subsystem #(
    .CLOCK_HZ(32'd27_000_000),
    .MANCHESTER_CLOCK_HZ(32'd1_000_000),
    .PRECHARGE_CYCLES(16),
    .BUFFER_SIZE(256),
    .DEBUG_OUT(0),
    .PROCESSOR_ID(0),
    .PROCESSOR_ROM_SIZE(16384),
    .PROCESSOR_ROM_FILE("/home/kenta/repos/fpga_samples/rtl/displayport/test/sw-rs/bootrom-rs.hex"),
    .PROCESSOR_RAM_SIZE(8192)
) aux_ch_subsystem_inst (
    .clock  (clock_27),
    .aresetn(!reset_27),
    .aux_ch_in(aux_ch_in || aux_ch_out_enable),
    .aux_ch_out(aux_ch_out),
    .aux_ch_out_enable(aux_ch_out_enable),
    .cpu_io_out(),
    .maxis_serial_out_tvalid(maxis_serial_out_tvalid),
    .maxis_serial_out_tready(maxis_serial_out_tready),
    .maxis_serial_out_tdata(maxis_serial_out_tdata)
);

TLVDS_IOBUF aux_ch_elvds_tbuf (
    .I   (aux_ch_out),
    .OEN (!aux_ch_out_enable),
    .O   (aux_ch_in),
    .IO  (aux_ch_p),
    .IOB (aux_ch_n)
);

assign aux_ch_received = aux_ch_in;

uart_tx #(
    .NUMBER_OF_BITS(8),
    .BAUD_DIVIDER(32'd27_000_000/32'd115_200)
) debug_uart_tx_inst (
    .clock(clock_27),
    .reset(reset_27),

    .data_valid(maxis_serial_out_tvalid),
    .data_ready(maxis_serial_out_tready),
    .data_bits(maxis_serial_out_tdata),

    .tx(uart_tx)
);

endmodule
`default_nettype wire