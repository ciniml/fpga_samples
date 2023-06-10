/**
* @file top.sv
* @brief Top module for PicoRV32 matrix LED example
*/
// Copyright 2023 Eisuke Mochizuki
//                Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
`default_nettype none

module top (
  input  wire  clock,
  output logic com_ser,
  output logic com_rclk,
  output logic com_srclk,
  output logic com_oe,
  output logic seg_ser,
  output logic seg_rclk,
  output logic seg_srclk,
  output logic seg_oe
);

  // リセット回路 (16サイクル)
  logic reset;
  logic [15:0] reset_reg = '1;
  assign reset = reset_reg[0];
  always_ff @(posedge clock) begin
      reset_reg <= {1'b0, reset_reg[15:1]};
  end
  
  MultiSegmentLed multi_segment_led_inst (
    .resetn(!reset),
    .*
  );
endmodule
`default_nettype wire