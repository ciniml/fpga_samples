/**
 * @file top.sv
 * @brief Top module for lifegame with FRAM
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
    output logic seven_seg,

    output logic spi_cs_n,
    output logic spi_wp_n,
    output logic spi_hold_n,
    output logic spi_sck,
    output logic spi_si,
    input  wire  spi_so,

    input wire initialize
);

assign led = 0;
assign seven_seg = 0;
logic [15:0] reset_seq;
initial begin
  reset_seq = '1;
end
always_ff @(posedge clock) begin
  reset_seq <= reset_seq >> 1;
end
logic reset;
assign reset = reset_seq[0];

logic [2:0] initialize_reg = 0;
always_ff @(posedge clock) begin
  if( reset ) begin
    initialize_reg <= 0;
  end
  else begin
    initialize_reg <= {initialize_reg[1:0], !initialize};
  end
end

LifeGameFram lifegame_i(
  .data(d),
  .row(row),
  .reset(reset),
  .initialize(initialize_reg[2]),
  .*
);

endmodule