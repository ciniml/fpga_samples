/**
 * @file top.sv
 * @brief Top module for ethernet ICMP echo reply system.
 */
// Copyright 2023 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top(
    input wire clock,

    // Input button
    input wire button_s0,
    input wire button_s1,
    input wire button_s2,
    input wire button_s3,
    input wire button_s4,

    // Output LED
    output logic [5:0] led,

    // Stepper motor
    output logic [3:0] stepper_m1p,
    output logic [3:0] stepper_m2p
);

logic reset;

reset_seq reset_seq_main(
  .clock(clock),
  .reset_in(0),
  .reset_out(reset)
);

localparam int CLOCK_HZ = 27_000_000;
localparam int MAX_STEPPER_PPS = 1000;
localparam int MIN_STEPPER_PPS = 500;
localparam int MIN_PULSE_INTERVAL = CLOCK_HZ / MAX_STEPPER_PPS;
localparam int MAX_PULSE_INTERVAL = CLOCK_HZ / MIN_STEPPER_PPS;
localparam int PULSE_COUNTER_BITS = $clog2(MAX_PULSE_INTERVAL);

typedef logic [PULSE_COUNTER_BITS-1:0] pulse_counter_t;

pulse_counter_t pulse_counter = 0;
pulse_counter_t max_pulse_counter = MAX_PULSE_INTERVAL - 1;
logic [2:0] phase = 0;
logic [3:0] stepper_out = 0;
logic direction_ccw = 0;

assign stepper_m1p = stepper_out;
assign stepper_m2p = stepper_out;

assign led = ~{1'b0, button_s4, button_s3, button_s2, button_s1, button_s0};

always_ff @(posedge clock) begin
  if (reset) begin
    pulse_counter <= 0;
    phase <= 0;
    max_pulse_counter <= MAX_PULSE_INTERVAL - 1;
    direction_ccw <= 0;
  end else begin
    if (pulse_counter >= max_pulse_counter) begin
      pulse_counter <= 0;
      if( direction_ccw ) begin
        phase <= phase - 1;
      end else begin
        phase <= phase + 1;
      end
    end else begin
      pulse_counter <= pulse_counter + 1;
    end
    
    if ( !button_s0 ) begin
      if( max_pulse_counter < MAX_PULSE_INTERVAL - 1 ) begin
        max_pulse_counter <= max_pulse_counter + 1;
      end
    end
    if ( !button_s1 ) begin
      if( max_pulse_counter > MIN_PULSE_INTERVAL ) begin
        max_pulse_counter <= max_pulse_counter - 1;
      end
    end
    if ( !button_s2 ) begin
      direction_ccw <= 0;
    end
    if ( !button_s3 ) begin
      direction_ccw <= 1;
    end
    
    case(phase)
      0: stepper_out <= 4'b0001;
      1: stepper_out <= 4'b0011;
      2: stepper_out <= 4'b0010;
      3: stepper_out <= 4'b0110;
      4: stepper_out <= 4'b0100;
      5: stepper_out <= 4'b1100;
      6: stepper_out <= 4'b1000;
      7: stepper_out <= 4'b1001;
      default: stepper_out <= 4'b0000;
    endcase
  end
end

endmodule
`default_nettype wire