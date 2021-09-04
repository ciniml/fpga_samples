/**
 * @file ws2812b.sv
 * @brief control signal generator for Worldsemi WS2812B and variants.
 */
// Copyright 2021 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module ws2812b #(
    parameter longint CLOCK_HZ = 12_000_000,
    parameter NUMBER_OF_LEDS = 16
) (
    input  logic clock,
    input  logic reset,

    output logic serial_out,

    // LED pixel buffer interface
    output logic [$clog2(NUMBER_OF_LEDS*3)-1:0] pixel_address,
    output logic                                pixel_request,
    input  logic                                pixel_ready,
    input  logic                                pixel_valid,
    input  logic [7:0]                          pixel_data
);

localparam longint LONG_PERIOD  = (580*CLOCK_HZ + 1000_000_000-1)/1000_000_000;
localparam longint SHORT_PERIOD = (220*CLOCK_HZ + 1000_000_000-1)/1000_000_000;
localparam longint RESET_PERIOD = (280_000*CLOCK_HZ + 1000_000_000-1)/1000_000_000;

typedef struct packed {
    bit [7:0] g;
    bit [7:0] r;
    bit [7:0] b;
} pixel_t;
typedef bit [$clog2(NUMBER_OF_LEDS) - 1:0] led_index_t;

// Read pixel data process
pixel_t     pixel_buffer_next = 0;          // The next pixel data
logic       pixel_buffer_next_valid = 0;    // Is the next pixel data valid?
logic       pixel_buffer_next_ready = 0;    // Is the next pixel data ready to consume?
led_index_t pixel_counter = 0;              // Pixel index counter. [0 .. NUMBER_OF_LEDS-1]
logic [1:0] pixel_color_counter = 0;        // Pixel color counter. [0 .. 2]
logic [1:0] pixel_address_counter = 0;      // Pixel address counter. [0 .. 2]
typedef enum { S_READ_PIXEL_IDLE, S_READ_PIXEL_READ } read_state_t;
read_state_t pixel_read_state = S_READ_PIXEL_IDLE;

always_ff @(posedge clock) begin
    if( reset ) begin
        pixel_read_state <= S_READ_PIXEL_IDLE;
        pixel_buffer_next <= 0;
        pixel_counter <= 0;
        pixel_color_counter <= 0;
        pixel_address <= 0;
        pixel_address_counter <= 0;
        pixel_request <= 0;
    end
    else begin
        if( pixel_buffer_next_valid && pixel_buffer_next_ready ) begin
            pixel_buffer_next_valid <= 0;   // Clear valid if the pixel data in the pixel_buffer_next is consumed.
        end

        case(pixel_read_state)
            S_READ_PIXEL_IDLE: begin
                // Check if the pixel_buffer_next is empty or ready to consume.
                if( !pixel_buffer_next_valid || pixel_buffer_next_ready ) begin
                    // Begin to read the next pixel data.
                    pixel_color_counter <= 0;
                    pixel_address_counter <= 0;
                    pixel_request <= 1;
                    pixel_read_state <= S_READ_PIXEL_READ;
                end
            end
            S_READ_PIXEL_READ: begin
                if( pixel_request && pixel_ready ) begin
                    pixel_address <= pixel_address < NUMBER_OF_LEDS*3 - 1 ? pixel_address + 1 : 0;
                    if( pixel_address_counter < 2 ) begin
                        pixel_address_counter <= pixel_address_counter + 1;
                    end 
                    else begin
                        pixel_request <= 0;
                    end
                end
                if( pixel_valid ) begin
                    // Reorder the pixel data. (BGR888 -> GRB888)
                    case(pixel_color_counter)
                        0: pixel_buffer_next.b <= pixel_data;
                        1: pixel_buffer_next.g <= pixel_data;
                        2: pixel_buffer_next.r <= pixel_data;
                    endcase

                    if( pixel_color_counter < 2 ) begin
                        pixel_color_counter <= pixel_color_counter + 1;
                    end
                    else begin
                        pixel_buffer_next_valid <= 1;
                        pixel_color_counter <= 0;
                        pixel_read_state <= S_READ_PIXEL_IDLE;
                        pixel_counter <= pixel_counter < NUMBER_OF_LEDS - 1 ? pixel_counter + 1 : 0;
                    end
                end
            end
        default: pixel_read_state <= S_READ_PIXEL_IDLE;
        endcase
    end
end

localparam PERIOD_COUNTER_BITS = $clog2(RESET_PERIOD); 
localparam LED_COUNTER_BITS = $clog2(NUMBER_OF_LEDS);

logic [PERIOD_COUNTER_BITS-1:0] period_counter;
logic [4:0] bit_counter;
logic [LED_COUNTER_BITS-1:0] led_counter;
logic [23:0] pixel;

typedef enum {S_IDLE, S_INTERVAL, S_RESET, S_BEGIN_LED, S_BEGIN_BIT, S_BIT_HIGH, S_BIT_LOW } state_t;
state_t state;

always_comb begin
    case(state)
        S_RESET: serial_out = 0;
        S_BIT_LOW: serial_out = 0;
        default: serial_out = 1;
    endcase
end

always_comb begin
    case(state)
        S_BEGIN_LED: pixel_buffer_next_ready = 1;
        default: pixel_buffer_next_ready = 0;
    endcase
end

always_ff @(posedge clock) begin
    if( reset ) begin
        state <= S_IDLE;
    end
    else begin
        case(state)
        S_IDLE: begin
            period_counter <= LONG_PERIOD+SHORT_PERIOD;
            led_counter <= 0;
            pixel <= 0;
            state <= S_INTERVAL;
        end
        S_INTERVAL: begin
            period_counter <= period_counter - 1;
            if( period_counter == 0 ) begin
                period_counter <= RESET_PERIOD;
                state <= S_RESET;
            end
        end
        S_RESET: begin
            period_counter <= period_counter - 1;
            if( period_counter == 0 ) begin
                state <= S_BEGIN_LED;
            end
        end
        S_BEGIN_LED: begin
            bit_counter <= 23;
            pixel <= pixel_buffer_next;
            if( pixel_buffer_next_valid ) begin
                state <= S_BEGIN_BIT;
            end
        end
        S_BEGIN_BIT: begin
            period_counter <= pixel[bit_counter] ? LONG_PERIOD : SHORT_PERIOD;
            state <= S_BIT_HIGH;
        end
        S_BIT_HIGH: begin
            period_counter <= period_counter - 1;
            if( period_counter == 0 ) begin
                period_counter <= pixel[bit_counter] ? SHORT_PERIOD : LONG_PERIOD;
                state <= S_BIT_LOW;
            end
        end
        S_BIT_LOW: begin
            period_counter <= period_counter - 1;
            if( period_counter == 0 ) begin
                bit_counter <= bit_counter - 1;
                if( bit_counter == 0 ) begin
                    led_counter <= led_counter + 1;
                    if( led_counter == NUMBER_OF_LEDS - 1 ) begin
                        state <= S_IDLE;
                    end
                    else begin
                        state <= S_BEGIN_LED;
                    end
                end
                else begin
                    state <= S_BEGIN_BIT;
                end
            end
        end
        default: begin
            state <= S_IDLE;
        end
        endcase
    end
end

endmodule
    
