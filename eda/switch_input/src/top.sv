/**
 * @file top.sv
 * @brief Top module for debounce example
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module top (
    input logic clock,

    input logic key_1,
    input logic key_2,
    input logic key_3,
    input logic key_4,
    input logic key_5,
    input logic key_6,
    input logic key_7,
    input logic key_8,

    input logic sw_1,   // DIP SW to select filter is enabled or not.

    output logic [7:0] led_out
);

localparam int CLOCK_HZ = 12_000_000;

logic [1:0] sync_reg = 0;
always_ff @(posedge clock) begin
    sync_reg <= {!key_8, sync_reg[1]}; 
end

// Bounce detector to measure bouncing period of the switch.
bounce_detector #(
    .CLOCK_HZ(CLOCK_HZ),
    .INPUT_RATE_HZ(30)
) bounce_detector_inst (
    .clock(clock),
    .reset(1'b0),

    .async_in(!key_8),           // KEY_8
    .bounce_detected(),
    .cycles_to_stabilize()
);

// The instance of debouncing filter.
logic debounce_out;
debounce #(
    .CLOCK_HZ(CLOCK_HZ),
    .FILTER_HZ(10000),
    .FILTER_COUNTER_MAX(3)
) debounce_0 (
    .clock(clock),
    .reset(1'b0),

    .async_in(!key_8),           // KEY_8
    .sync_out(debounce_out)
);

// Check the filtered output with bounce detector.
bounce_detector #(
    .CLOCK_HZ(CLOCK_HZ)
) bounce_detector_filtered (
    .clock(clock),
    .reset(1'b0),

    .async_in(debounce_out),     // KEY_8
    .bounce_detected(),
    .cycles_to_stabilize()
);

logic [7:0] led_out_reg = 0;
assign led_out = {sw_1, led_out_reg[6:0]};

logic key_in;
logic key_in_prev = 0;

assign key_in = sw_1 ? sync_reg[0] : debounce_out;
//assign key_in = debounce_out;

always_ff @(posedge clock) begin
    key_in_prev <= key_in;
    if( !key_in_prev && key_in ) begin  // Key pressed.
        //led_out_reg <= {led_out_reg[6:0], led_out_reg[7]};  // Rotate left
        led_out_reg <= led_out_reg + 1;
    end
end

endmodule