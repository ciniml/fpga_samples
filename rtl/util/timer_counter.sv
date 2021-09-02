/**
 * @file timer_counter.sv
 * @brief Timer Counter with compare match.
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module timer_counter #(
    parameter int MAX_COUNTER_VALUE = 255,
    localparam int COUNTER_BITS = $clog2(MAX_COUNTER_VALUE+1)
) (
    input logic clock,
    input logic reset,

    input logic enable,
    input logic [COUNTER_BITS-1:0] top_value,
    input logic [COUNTER_BITS-1:0] compare_value,

    output logic [COUNTER_BITS-1:0] counter_value,

    output logic overflow,
    output logic compare_match
);

logic [COUNTER_BITS-1:0] counter = 0;
assign compare_match = counter == compare_value;
assign counter_value = counter;

always_ff @(posedge clock) begin
    if( reset ) begin
        counter <= 0;
        overflow <= 0;
    end
    else begin
        if( enable ) begin
            overflow <= 0;

            if( counter < top_value ) begin
                counter <= counter + 1;
            end
            else begin
                overflow <= 1;
                counter <= 0;
            end
        end
    end
end

endmodule