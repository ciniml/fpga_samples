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

    // DVI
    output logic tmds_clk_p,
    output logic tmds_clk_n,
    output logic [2:0] tmds_data_p,
    output logic [2:0] tmds_data_n
);

logic clock_dvi;
logic pll_lock;
logic clock_dvi_ser;
logic pll_lock_ser;

logic reset_ext;
reset_seq reset_seq_ext(
  .clock(clock_dvi),
  .reset_in(!pll_lock || !pll_lock_ser),
  .reset_out(reset_ext)
);

gowin_pllvr_dvi pllvr_dvi(
    .clkout(clock_dvi), //output clkout
    .lock(pll_lock), //output lock
    .clkin(clock) //input clkin
);
gowin_pllvr_ser pllvr_ser(
    .clkout(clock_dvi_ser), //output clkout
    .lock(pll_lock_ser), //output lock
    .clkin(clock) //input clkin
);

logic reset_dvi;
reset_seq #( .RESET_DELAY_CYCLES(4) ) reset_seq_dvi(
  .clock(clock_dvi),
  .reset_in(reset_ext),
  .reset_out(reset_dvi)
);

logic [9:0] dvi_clock;
logic [9:0] dvi_data0;
logic [9:0] dvi_data1;
logic [9:0] dvi_data2;
logic video_de;
logic video_hsync;
logic video_vsync;
logic [23:0] video_data;

test_pattern_generator #(
  .BOUNCE_LOGO(1),
  .LOGO_PATH("../cq_logo.hex"),
  .LOGO_WIDTH(250),
  .LOGO_HEIGHT(50),
  .LOGO_COLOR(24'h000000)  
) tpg_inst (
  .clock(clock_dvi),
  .reset(reset_dvi),
  .*
);

dvi_out dvi_out_inst (
  .clock(clock_dvi),
  .reset(reset_dvi),
  .*
);

logic tmds_clk;
logic tmds_data[2:0];

OSER10 oser_dvi_clock(
  .Q(tmds_clk),
  .D0(dvi_clock[0]),
  .D1(dvi_clock[1]),
  .D2(dvi_clock[2]),
  .D3(dvi_clock[3]),
  .D4(dvi_clock[4]),
  .D5(dvi_clock[5]),
  .D6(dvi_clock[6]),
  .D7(dvi_clock[7]),
  .D8(dvi_clock[8]),
  .D9(dvi_clock[9]),
  .FCLK(clock_dvi_ser),
  .PCLK(clock_dvi),
  .RESET(reset_dvi)
);
OSER10 oser_dvi_data0(
  .Q(tmds_data[0]),
  .D0(dvi_data0[0]),
  .D1(dvi_data0[1]),
  .D2(dvi_data0[2]),
  .D3(dvi_data0[3]),
  .D4(dvi_data0[4]),
  .D5(dvi_data0[5]),
  .D6(dvi_data0[6]),
  .D7(dvi_data0[7]),
  .D8(dvi_data0[8]),
  .D9(dvi_data0[9]),
  .FCLK(clock_dvi_ser),
  .PCLK(clock_dvi),
  .RESET(reset_dvi)
);
OSER10 oser_dvi_data1(
  .Q(tmds_data[1]),
  .D0(dvi_data1[0]),
  .D1(dvi_data1[1]),
  .D2(dvi_data1[2]),
  .D3(dvi_data1[3]),
  .D4(dvi_data1[4]),
  .D5(dvi_data1[5]),
  .D6(dvi_data1[6]),
  .D7(dvi_data1[7]),
  .D8(dvi_data1[8]),
  .D9(dvi_data1[9]),
  .FCLK(clock_dvi_ser),
  .PCLK(clock_dvi),
  .RESET(reset_dvi)
);
OSER10 oser_dvi_data2(
  .Q(tmds_data[2]),
  .D0(dvi_data2[0]),
  .D1(dvi_data2[1]),
  .D2(dvi_data2[2]),
  .D3(dvi_data2[3]),
  .D4(dvi_data2[4]),
  .D5(dvi_data2[5]),
  .D6(dvi_data2[6]),
  .D7(dvi_data2[7]),
  .D8(dvi_data2[8]),
  .D9(dvi_data2[9]),
  .FCLK(clock_dvi_ser),
  .PCLK(clock_dvi),
  .RESET(reset_dvi)
);

ELVDS_OBUF tmds_clk_elvds_obuf (
    .I (tmds_clk),
    .O (tmds_clk_p),
    .OB(tmds_clk_n)
);
generate
    for ( genvar i = 0; i <= 2; i++) begin : tmds_data_blk
        ELVDS_OBUF tmds_data_elvds_obuf (
            .I (tmds_data[i]),
            .O (tmds_data_p[i]),
            .OB(tmds_data_n[i])
        );
    end
endgenerate

endmodule
`default_nettype wire