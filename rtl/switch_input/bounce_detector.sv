/**
 * @file bounce_detector.sv
 * @brief Bounce detector to determine debounce filter parameter.
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module bounce_detector #(
    parameter longint CLOCK_HZ = 12_000_000,
    parameter int INPUT_RATE_HZ = 100,
    parameter int SYNCHRONIZE_FF_DEPTH = 2,
    localparam int MAX_COUNTER_VALUE = CLOCK_HZ/INPUT_RATE_HZ - 1,
    localparam int COUNTER_BITS = $clog2(MAX_COUNTER_VALUE + 1)
) (
    input logic clock,
    input logic reset,

    input logic async_in,
    output logic bounce_detected,

    output logic [COUNTER_BITS-1:0] cycles_to_stabilize
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

logic running = 0;
logic current_input_state = 0;
logic [COUNTER_BITS-1:0] counter = 0;
logic [COUNTER_BITS-1:0] count_at_last_edge = 0;
logic sync_in_prev = 0;

assign bounce_detected = count_at_last_edge != 0;
assign cycles_to_stabilize = count_at_last_edge;

always_ff @(posedge clock) begin
    if( reset ) begin
        counter <= 0;
        running <= 0;
    end
    else begin
        sync_in_prev <= synchronize_reg[0];    // Store the last synchronized input to detect edges.
        if( !running ) begin
            if( synchronize_reg[0] != current_input_state ) begin
                running <= 1;
                count_at_last_edge <= 0;
            end
        end
        else begin
            if( sync_in_prev != synchronize_reg[0] ) begin
                count_at_last_edge <= counter;  // Store current count to calculate number of cycles before the input gets steady.
            end
            if( counter < MAX_COUNTER_VALUE) begin
                counter <= counter + 1;
            end
            else begin  // Timed out. return to idle state.
                counter <= 0;
                running <= 0;
                current_input_state <= synchronize_reg[0];
            end    
        end
        
    end
end

endmodule