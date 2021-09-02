/**
 * @file segment_led.sv
 * @brief simple LED blink example.
 */
// Copyright 2019 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module segment_led #(
    parameter int NUMBER_OF_SEGMENTS = 8,
    parameter int NUMBER_OF_DIGITS = 4,
    parameter bit CATHODE_COMMON = 1'b1
) (
    input  logic clock,
    input  logic reset,

    input  logic next_segment,

    input  logic [NUMBER_OF_SEGMENTS-1:0] digits [0:NUMBER_OF_DIGITS-1],

    output logic [NUMBER_OF_SEGMENTS-1:0] segment_out,
    output logic [NUMBER_OF_DIGITS-1:0] digit_selector_out
);

logic [NUMBER_OF_DIGITS-1:0] digit_selector = 1;
assign digit_selector_out = CATHODE_COMMON ? ~digit_selector : digit_selector;
logic [NUMBER_OF_DIGITS-1:0] digit_selector_next;
assign digit_selector_next = { digit_selector[NUMBER_OF_DIGITS-2:0], digit_selector[NUMBER_OF_DIGITS-1] };

always_ff @(posedge clock) begin
    if( reset ) begin
        segment_out <= 0;
        digit_selector <= 1;
    end
    else begin
        if( next_segment ) begin
            for(int digit = 0; digit < NUMBER_OF_DIGITS; digit++ ) begin
                if( digit_selector_next[digit] ) begin
                    segment_out <= digits[digit];
                end
            end
            digit_selector <= digit_selector_next;
        end
    end
end

endmodule
    
