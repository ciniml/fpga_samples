/**
 * @file top.sv
 * @brief Top module for LED blink example
 */
// Copyright 2021-2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module top (
    input wire clock,

    output logic [5:0] led,
    output logic [7:0] d,
    output logic [7:0] row,
    output logic seven_seg
);

localparam int CLOCK_HZ = 27_000_000;
localparam int REFRESH_INTERVAL = CLOCK_HZ/1000;
localparam int REFRESH_ROW_GUARD = CLOCK_HZ/50000;
localparam int COLUMN_REFRESH_INTERVAL = CLOCK_HZ;

assign led  = '0;

logic [$clog2(REFRESH_INTERVAL)-1:0] refresh_counter = 0;

logic [7:0] pattern[0:7];

initial begin
    pattern[0] <= 8'b10000001;
    pattern[1] <= 8'b01000010;
    pattern[2] <= 8'b00100100;
    pattern[3] <= 8'b00011000;
    pattern[4] <= 8'b00011000;
    pattern[5] <= 8'b00100100;
    pattern[6] <= 8'b01000010;
    pattern[7] <= 8'b10000001;
end

logic [7:0] row_reg = 8'b1;

always_comb begin
  case(row_reg)
    8'b0000_0001: d = pattern[0];
    8'b0000_0010: d = pattern[1];
    8'b0000_0100: d = pattern[2];
    8'b0000_1000: d = pattern[3];
    8'b0001_0000: d = pattern[4];
    8'b0010_0000: d = pattern[5];
    8'b0100_0000: d = pattern[6];
    8'b1000_0000: d = pattern[7];
    default: d = 0;
  endcase
end


logic row_enable;
assign row_enable = refresh_counter < REFRESH_INTERVAL - REFRESH_ROW_GUARD;
assign row = row_enable ? row_reg : '0;
assign seven_seg = 0;

always_ff @(posedge clock) begin
  if( refresh_counter < REFRESH_INTERVAL - REFRESH_ROW_GUARD ) begin
      refresh_counter <= refresh_counter + 1;
  end
  else if( refresh_counter == REFRESH_INTERVAL - REFRESH_ROW_GUARD/2 ) begin
      refresh_counter <= refresh_counter + 1;
      row_reg <= {row_reg[6:0], row_reg[7]};
  end
  else if( refresh_counter < REFRESH_INTERVAL - 1 ) begin
      refresh_counter <= refresh_counter + 1;
  end
  else if( refresh_counter == REFRESH_INTERVAL - 1) begin
      refresh_counter <= 0;
  end
end

endmodule