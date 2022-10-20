/**
 * @file top.sv
 * @brief Top module for debounce example
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
`default_nettype none
module top (
  input  wire       clk,
  output wire [7:0] anode,
  output wire [7:0] cathode
);

  logic [7:0] data[7:0];
  assign data[0] = 8'b01100000;
  assign data[1] = 8'b10000000;
  assign data[2] = 8'b10000000;
  assign data[3] = 8'b01100110;
  assign data[4] = 8'b00001001;
  assign data[5] = 8'b00001001;
  assign data[6] = 8'b00000110;
  assign data[7] = 8'b00000001;

  logic [7:0] row, col;
  assign anode   = col;
  assign cathode = ~row;

  matrix_led_driver inst_0 (
    .clk  (clk),
    .data (data),
    .row  (row),
    .col  (col)
  );

endmodule

module matrix_led_driver (
  input  wire       clk,
  input  wire [7:0] data[7:0],
  output wire [7:0] row,
  output wire [7:0] col
);

  logic [2:0] row_cnt = 'd0;
  logic       overflow;

  assign row = 'b00000001 << row_cnt;
  assign col = {data[7][row_cnt],
                data[6][row_cnt],
                data[5][row_cnt],
                data[4][row_cnt],
                data[3][row_cnt],
                data[2][row_cnt],
                data[1][row_cnt],
                data[0][row_cnt]};

  always_ff @ (posedge clk) begin
    if (overflow) begin
      row_cnt <= row_cnt + 'd1;
    end
  end

  timer #(
    .COUNT_MAX (27000)
  ) inst_0 (
    .clk      (clk),
    .overflow (overflow)
  );

endmodule

module timer #(
  parameter COUNT_MAX = 27000000
) (
  input  wire  clk,
  output logic overflow
);

  logic [$clog2(COUNT_MAX+1)-1:0] counter = 'd0;

  always_ff @ (posedge clk) begin
    if (counter == COUNT_MAX) begin
      counter  <= 'd0;
      overflow <= 'd1;
    end else begin
      counter  <= counter + 'd1;
      overflow <= 'd0;
    end
  end

endmodule

`default_nettype wire