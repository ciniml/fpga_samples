/**
 * @file top.sv
 * @brief Top module for debounce example
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top (
    input wire   clock,

    input wire   key_1,
    input wire   key_2,
    input wire   key_3,
    input wire   key_4,
    input wire   key_5,
    input wire   key_6,
    input wire   key_7,
    input wire   key_8,

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

// Timer counter for generate timer 1/10 sec timing.
logic counter_reset = 0;
logic counter_enable;
logic subsec_trigger;
timer_counter #(
    .MAX_COUNTER_VALUE(CLOCK_HZ/10)
) subsec_timer_inst (
    .clock(clock),
    .reset(counter_reset),

    .enable(counter_enable),
    .top_value(CLOCK_HZ/10),
    .compare_value(1'b0),

    .counter_value(),

    .overflow(subsec_trigger),
    .compare_match()
);

logic [3:0] subsec_counter = 0;
logic [3:0] sec_counter = 0;
logic [3:0] ten_sec_counter = 0;
logic [3:0] min_counter = 0;

always @(posedge clock) begin
    if( counter_reset ) begin
        subsec_counter  <= 0;
        sec_counter     <= 0;
        ten_sec_counter <= 0;
        min_counter     <= 0;
    end
    else if( subsec_trigger ) begin
        if( subsec_counter < 9 ) begin
            subsec_counter <= subsec_counter + 1;
        end
        else begin
            subsec_counter <= 0;
            if( sec_counter < 9 ) begin
                sec_counter <= sec_counter + 1;
            end
            else begin
                sec_counter <= 0;
                if( ten_sec_counter < 5 ) begin
                    ten_sec_counter <= ten_sec_counter + 1;
                end
                else begin
                    ten_sec_counter <= 0;
                    if( min_counter < 9 ) begin
                        min_counter <= min_counter + 1;
                    end
                    else begin
                        min_counter <= 0;
                    end
                end
            end
        end
    end
end

typedef enum {
    S_IDLE,
    S_RUNNING,
    S_PAUSE
} state_t;

state_t state = S_IDLE;
assign counter_enable = state == S_RUNNING;

always_ff @(posedge clock) begin
    counter_reset <= 0;
    case(state)
        S_IDLE: begin
            if( keys_pressed[8] ) begin
                state <= S_RUNNING;
            end
            if( keys_pressed[7] ) begin
                counter_reset <= 1;
            end
        end
        S_RUNNING: begin
            if( keys_pressed[8] ) begin
                state <= S_IDLE;
            end
        end
        default: state <= S_IDLE;
    endcase
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
    digits[0] = {1'b1, min_counter};
    digits[1] = {1'b0, ten_sec_counter};
    digits[2] = {1'b1, sec_counter};
    digits[3] = {1'b0, subsec_counter};
    
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
`default_nettype wire