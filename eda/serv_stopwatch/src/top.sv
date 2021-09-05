/**
 * @file top.sv
 * @brief Top module for SERV SoC example
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
`default_nettype wire
module top (
    input logic clock,

    // push switches
    input logic key_1,
    input logic key_2,
    input logic key_3,
    input logic key_4,
    input logic key_5,
    input logic key_6,
    input logic key_7,
    input logic key_8,

    // DIP switches
    input logic sw_1,
    input logic sw_2,
    input logic sw_3,
    input logic sw_4,
    input logic sw_5,
    input logic sw_6,
    input logic sw_7,
    input logic sw_8,
    
    // 4 digit 7 segment with DP LEDs
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

    // single color LEDs
    output logic [7:0] led_out,
    
    // RGB LEDs
    output logic g_led1,
    output logic b_led1,
    output logic r_led1,
    output logic g_led2,
    output logic b_led2,
    output logic r_led2,
    output logic g_led3,
    output logic b_led3,
    output logic r_led3,
    output logic g_led4,
    output logic b_led4,
    output logic r_led4
);

localparam int CLOCK_HZ = 12_000_000;
localparam int NUMBER_OF_LEDS = 16;
localparam int UPDATE_FREQ_HZ = 1000;
localparam int DEBOUNCE_SAMPLING_HZ = 200;

// Timer counter for generate sampling timing.
logic debounce_sampling_trigger;
timer_counter #(
    .MAX_COUNTER_VALUE(CLOCK_HZ/DEBOUNCE_SAMPLING_HZ)
) debounce_timer_inst (
    .clock(clock),
    .reset(1'b0),

    .enable(1'b1),
    .top_value(CLOCK_HZ/DEBOUNCE_SAMPLING_HZ),
    .compare_value(1'b0),

    .counter_value(),

    .overflow(debounce_sampling_trigger),
    .compare_match()
);

// The instance of debouncing filter.
logic [8:1] raw_keys;
assign raw_keys[8:1] = ~{key_8, key_7, key_6, key_5, key_4, key_3, key_2, key_1};
logic [8:1] keys;
logic [8:1] keys_pressed;
for(genvar i = 1; i <= 8; i++) begin: gen_debounce
    debounce #(
        .FILTER_COUNTER_MAX(3)
    ) key_debounce_inst (
        .clock(clock),
        .reset(1'b0),

        .sampling_trigger(debounce_sampling_trigger),
        .async_in(raw_keys[i]),
        .sync_out(keys[i])
    );

    logic key_prev = 0;
    assign keys_pressed[i] = !key_prev && keys[i];
    always_ff @(posedge clock) begin
        key_prev <= keys[i];
    end
end

logic reset;
assign reset = keys[1];

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

    .counter_value(),

    .overflow(reflesh_trigger),
    .compare_match()
);

// Segment LED driver
logic [5:0] digits [0:3];
logic [7:0] segment_out;
logic [3:0] digit_selector_out;

always_comb begin    
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

// Color LEDs
logic [2:0] color_leds[3:0];
always_comb begin
    r_led1 = ~color_leds[0][0];
    g_led1 = ~color_leds[0][1];
    b_led1 = ~color_leds[0][2];
    r_led2 = ~color_leds[1][0];
    g_led2 = ~color_leds[1][1];
    b_led2 = ~color_leds[1][2];
    r_led3 = ~color_leds[2][0];
    g_led3 = ~color_leds[2][1];
    b_led3 = ~color_leds[2][2];
    r_led4 = ~color_leds[3][0];
    g_led4 = ~color_leds[3][1];
    b_led4 = ~color_leds[3][2];
end

// SERV system


logic [2:0] gpio;
serv_system #(
    .INIT_INST_RAM("src/sw/bootrom.hex")
) serv_system_inst (
    .gpio(gpio),
    .*
);

always_ff @(posedge clock) begin
    led_out <= {5'b0, gpio};
end

endmodule