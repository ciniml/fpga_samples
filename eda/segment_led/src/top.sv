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

    output logic seg_a,
    output logic seg_b,
    output logic seg_c,
    output logic seg_d,
    output logic seg_e,
    output logic seg_f,
    output logic seg_g,
    output logic seg_dp,
    output logic seg_dig1,
    output logic seg_dig2,
    output logic seg_dig3,
    output logic seg_dig4,

    output logic [7:0] led_out
);

assign led_out = 0;

localparam int CLOCK_HZ = 12_000_000;
localparam int UPDATE_FREQ_HZ = 200;

// Timer counter for generate digit selection timing.
logic reflesh_trigger;
timer_counter #(
    .MAX_COUNTER_VALUE(CLOCK_HZ/UPDATE_FREQ_HZ)
) digit_refresh_timer_inst (
    .clock(clock),
    .reset(1'b0),

    .enable(1'b1),
    .top_value(CLOCK_HZ/UPDATE_FREQ_HZ),
    .compare_value(1'b0),

    .overflow(reflesh_trigger),
    .compare_match()
);

// Segment LED driver
logic [4:0] digits [0:3];
logic [7:0] segment_out;
logic [3:0] digit_selector_out;

always_comb begin
    digits[0] = 5'h0a;
    digits[1] = 5'h1b;
    digits[2] = 5'h00;
    digits[3] = 5'h19;
    
    seg_a  = segment_out[0];
    seg_b  = segment_out[1];
    seg_c  = segment_out[2];
    seg_d  = segment_out[3];
    seg_e  = segment_out[4];
    seg_f  = segment_out[5];
    seg_g  = segment_out[6];
    seg_dp = segment_out[7];
    seg_dig1 = digit_selector_out[0];
    seg_dig2 = digit_selector_out[1];
    seg_dig3 = digit_selector_out[2];
    seg_dig4 = digit_selector_out[3];
end

seven_segment_with_dp segment_led_inst (
    .reset(1'b0),
    .next_segment(reflesh_trigger),
    .*
);

endmodule