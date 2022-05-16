/**
 * @file top.sv
 * @brief Top module for WS2812 example
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

    output logic [7:0] led_out,
    output logic serial_out
);

assign led_out = 0;

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
logic [$clog2(NUMBER_OF_LEDS*3)-1:0] pixel_address;
logic pixel_request;
logic pixel_ready;
logic pixel_valid = 0;
logic [7:0] pixel_data = 0;

ws2812b #( 
    .CLOCK_HZ(CLOCK_HZ),
    .NUMBER_OF_LEDS(NUMBER_OF_LEDS) 
) ws2812b_inst (
    .*
);

// Intensity control by keys.
logic [7:0] intensity = 0;
logic [$clog2(NUMBER_OF_LEDS*3)-1:0] pixel_address_offset = 0;

always_ff @(posedge clock) begin
    if( reset ) begin
        intensity <= 0;
        pixel_address_offset <= 0;
    end
    else begin
        if( keys_pressed[8] ) begin
            intensity <= intensity + 8'h1;
        end
        else if( keys_pressed[7] ) begin
            intensity <= intensity + 8'h10;
        end
        if( keys_pressed[6] ) begin
            if( pixel_address_offset < (NUMBER_OF_LEDS - 1)*3 ) begin
                pixel_address_offset <= pixel_address_offset + 3;
            end
            else begin
                pixel_address_offset <= 0;
            end
        end
    end
end

assign pixel_ready = !pixel_valid;
always_ff @(posedge clock) begin
    pixel_valid <= 0;
    if( pixel_request && pixel_ready ) begin
        logic [$clog2(NUMBER_OF_LEDS*3):0] address;
        address = pixel_address_offset + pixel_address;
        if( address > NUMBER_OF_LEDS*3 ) address -= NUMBER_OF_LEDS*3;

        pixel_valid <= 1;
        case(address[$bits(address)-2:0])
            6'h00: pixel_data <= 8'h00;
            6'h01: pixel_data <= 8'h00;
            6'h02: pixel_data <= intensity;

            6'h03: pixel_data <= 8'h00;
            6'h04: pixel_data <= intensity;
            6'h05: pixel_data <= intensity;

            6'h06: pixel_data <= 8'h00;
            6'h07: pixel_data <= intensity;
            6'h08: pixel_data <= 8'h00;

            6'h09: pixel_data <= intensity;
            6'h0a: pixel_data <= intensity;
            6'h0b: pixel_data <= 8'h00;

            6'h0c: pixel_data <= intensity;
            6'h0d: pixel_data <= 8'h00;
            6'h0e: pixel_data <= 8'h00;

            6'h0f: pixel_data <= intensity;
            6'h10: pixel_data <= 8'h00;
            6'h11: pixel_data <= intensity;

            6'h12: pixel_data <= intensity;
            6'h13: pixel_data <= intensity;
            6'h14: pixel_data <= intensity;

            default: pixel_data <= 0;
        endcase
    end
end


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
logic [4:0] digits [0:3];
logic [7:0] segment_out;
logic [3:0] digit_selector_out;

always_comb begin
    digits[0] = 0;
    digits[1] = 0;
    digits[2] = {1'b0, intensity[7:4]};
    digits[3] = {1'b0, intensity[3:0]};
    
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