/**
 * @file segment_led.sv
 * @brief simple LED blink example.
 */
// Copyright 2019 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module seven_segment_with_dp #(
    parameter int NUMBER_OF_DIGITS = 4,
    parameter bit CATHODE_COMMON = 1'b1,
    localparam int NUMBER_OF_SEGMENTS = 8
) (
    input  wire  clock,
    input  wire  reset,

    input  wire  next_segment,

    input  wire  [6-1:0] digits [0:NUMBER_OF_DIGITS-1],

    output logic [NUMBER_OF_SEGMENTS-1:0] segment_out,
    output logic [NUMBER_OF_DIGITS-1:0] digit_selector_out
);

logic [NUMBER_OF_SEGMENTS-1:0] digits_inner [0:NUMBER_OF_DIGITS-1];

segment_led #(
    .NUMBER_OF_SEGMENTS(NUMBER_OF_SEGMENTS), 
    .NUMBER_OF_DIGITS(NUMBER_OF_DIGITS), 
    .CATHODE_COMMON(CATHODE_COMMON))
    segment_led_inst (
        .digits(digits_inner),
        .*
    );

for(genvar digit = 0; digit < NUMBER_OF_DIGITS; digit++) begin: gen_segment_pattern
    logic [7-1:0] digit_wo_dp;
    
    always_comb begin
        case(digits[digit][3:0])
            4'h0: digit_wo_dp = 7'b0111111;
            4'h1: digit_wo_dp = 7'b0000110;
            4'h2: digit_wo_dp = 7'b1011011;
            4'h3: digit_wo_dp = 7'b1001111;
            4'h4: digit_wo_dp = 7'b1100110;
            4'h5: digit_wo_dp = 7'b1101101;
            4'h6: digit_wo_dp = 7'b1111101;
            4'h7: digit_wo_dp = 7'b0000111;
            4'h8: digit_wo_dp = 7'b1111111;
            4'h9: digit_wo_dp = 7'b1101111;
            4'ha: digit_wo_dp = 7'b1110111;
            4'hb: digit_wo_dp = 7'b1111100;
            4'hc: digit_wo_dp = 7'b0111001;
            4'hd: digit_wo_dp = 7'b1011110;
            4'he: digit_wo_dp = 7'b1111001;
            4'hf: digit_wo_dp = 7'b1110001;
            default: digit_wo_dp = 0;
        endcase
        digits_inner[digit] = digits[digit][5] ? {digits[digit][4], digit_wo_dp} : 0;
    end
end

endmodule
`default_nettype wire