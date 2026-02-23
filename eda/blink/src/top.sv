/**
 * @file blink_all.sv
 * @brief simple LED blink example.
 */
// Copyright 2019 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module top (
    input  wire  clock,
    output logic [7:0] led_out
);

localparam longint CLOCK_HZ = 12_000_000;
localparam longint COUNT_HALF = CLOCK_HZ/2;
localparam int COUNTER_BITS = $clog2(COUNT_HALF);

logic [COUNTER_BITS-1:0] counter_p = 0;
logic [COUNTER_BITS-1:0] counter_n = 0;

initial begin
    led_out = 0;
end

logic clock_n;
assign clock_n = !clock;

always_ff @(posedge clock) begin
    if( counter_p < COUNT_HALF - 1 ) begin
        counter_p <= counter_p + 1;
    end
    else begin
        counter_p <= 0;
        led_out[3:0] = ~led_out[3:0];
    end    
end

always_ff @(posedge clock_n) begin
    if( counter_n < COUNT_HALF - 1 ) begin
        counter_n <= counter_n + 1;
    end
    else begin
        counter_n <= 0;
        led_out[7:4] = ~led_out[7:4];
    end    
end


endmodule
    
