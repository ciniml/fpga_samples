/**
 * @file debounce.sv
 * @brief Debounce filter for bouncy switch input.
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module debounce #(
    parameter int FILTER_COUNTER_MAX = 3, 
    parameter int SYNCHRONIZE_FF_DEPTH = 2
) (
    input logic clock,
    input logic reset,

    input logic  sampling_trigger,
    input logic  async_in,
    output logic sync_out
);

// Synchronize the async input to the clock.
logic [SYNCHRONIZE_FF_DEPTH-1:0] synchronize_reg = 0;
always_ff @(posedge clock) begin
    if( reset ) begin
        synchronize_reg[SYNCHRONIZE_FF_DEPTH-1:0] <= 0;
    end
    else begin
        synchronize_reg[SYNCHRONIZE_FF_DEPTH-1:0] <= {async_in, synchronize_reg[SYNCHRONIZE_FF_DEPTH-1:1]};
    end
end

// Debounce filter
localparam int FILTER_COUNTER_BITS = $clog2(FILTER_COUNTER_MAX+1);
logic [FILTER_COUNTER_BITS-1:0] filter_counter = 0;
logic last_out = 0;
assign sync_out = last_out;
always_ff @(posedge clock) begin
    if( reset ) begin
        filter_counter <= 0;
    end
    else begin
        if( sampling_trigger ) begin 
            if( last_out != synchronize_reg[0] ) begin  // If the input is the opposite value of the last output, increment the counter by 1.
                if( filter_counter < FILTER_COUNTER_MAX ) begin
                    filter_counter <= filter_counter + 1;
                end
                else begin
                    last_out <= !last_out;  // Flip the output if the counter is reached to the maximum value.
                    filter_counter <= 0;    // Clear the counter.
                end
            end
            else begin
                filter_counter <= 0;        // Othersie, clear the counter.
            end
        end
    end
end

endmodule