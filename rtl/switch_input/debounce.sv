/**
 * @file debounce.sv
 * @brief Debounce filter for bouncy switch input.
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module debounce #(
    parameter longint CLOCK_HZ = 12_000_000,
    parameter int FILTER_HZ = 1000,
    parameter int FILTER_COUNTER_MAX = 3, 
    parameter int PORT_BITS = 1,
    parameter int SYNCHRONIZE_FF_DEPTH = 2
) (
    input logic clock,
    input logic reset,

    input logic [PORT_BITS-1:0] async_in,
    output logic [PORT_BITS-1:0] sync_out
);

localparam longint DIVIDER_COUNT = CLOCK_HZ/FILTER_HZ;
localparam int DIVIDER_BITS = $clog2(DIVIDER_COUNT);

logic [DIVIDER_BITS-1:0] divider_counter = 0;
always_ff @(posedge clock) begin
    if( reset ) begin
        divider_counter <= 0;
    end
    else begin
        if( divider_counter < DIVIDER_COUNT - 1) begin
            divider_counter <= divider_counter + 1;
        end
        else begin
            divider_counter <= 0;
        end
    end
end


generate 
    for(genvar i = 0; i < PORT_BITS; i++) begin : debounce_filter
        // Synchronize the async input to the clock.
        logic [SYNCHRONIZE_FF_DEPTH-1:0] synchronize_reg = 0;
        always_ff @(posedge clock) begin
            if( reset ) begin
                synchronize_reg[SYNCHRONIZE_FF_DEPTH-1:0] <= 0;
            end
            else begin
                synchronize_reg[SYNCHRONIZE_FF_DEPTH-1:0] <= {async_in[i], synchronize_reg[SYNCHRONIZE_FF_DEPTH-1:1]};
            end
        end

        // Debounce filter
        localparam int FILTER_COUNTER_BITS = $clog2(FILTER_COUNTER_MAX+1);
        logic [FILTER_COUNTER_BITS-1:0] filter_counter = 0;
        logic last_out = 0;
        assign sync_out[i] = last_out;
        always_ff @(posedge clock) begin
            if( reset ) begin
                filter_counter <= 0;
            end
            else begin
                if( divider_counter == 0 ) begin    // Divided clock is active.
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
    end 
endgenerate

endmodule