/**
 * @file top.sv
 * @brief Top module for ethernet ICMP echo reply system.
 */
// Copyright 2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top(
    input wire clock,

    input  wire  [7:0] in_data_a,
    input  wire  [7:0] in_data_b,
    output logic [7:0] out_data
);

logic [7:0] in_data_a_reg;
logic [7:0] in_data_b_reg;

always_ff @(posedge clock) begin
    in_data_a_reg <= in_data_a;
    in_data_b_reg <= in_data_b;
    out_data[0] <= in_data_a_reg[0] ^ in_data_b_reg[0];
    out_data[7:1] <= 0;
end

endmodule
`default_nettype wire