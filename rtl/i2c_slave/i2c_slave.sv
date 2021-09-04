/**
 * @file i2c_slave.v
 * @brief I2C slave to register interface core.
 */
// Copyright 2019 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


module i2c_slave #(
    parameter [6:0] I2C_ADDRESS = 7'h48,
    parameter int   I2C_REG_ADDRESS_WIDTH = 8,
    parameter int   I2C_FILTER_DEPTH = 8
) (
    input wire clock,
    input wire reset,

    inout wire sda,
    inout wire scl,
    
    output reg [I2C_REG_ADDRESS_WIDTH-1:0] reg_address,
    output reg reg_is_write,
    output reg reg_request,
    input wire reg_response,
    input wire [7:0] reg_read_data,
    output reg [7:0] reg_write_data
);


// SDA, SCL IO buffer and filter
logic sda_o;
logic sda_i_raw;

logic scl_o;
logic scl_i_raw;

IOBUF sda_io_buf (
    .O(sda_i_raw),
    .I(1'b0),
    .IO(sda),
    .OEN(sda_o)
);

IOBUF scl_io_buf (
    .O(scl_i_raw),
    .I(1'b0),
    .IO(scl),
    .OEN(scl_o)
);

logic scl_i;
logic sda_i;

logic scl_i_reg;
logic sda_i_reg;

logic [I2C_FILTER_DEPTH-1:0] scl_i_filter;
logic [I2C_FILTER_DEPTH-1:0] sda_i_filter;

always_ff @(posedge clock) begin
    if( reset ) begin
        scl_i_filter <= 0;
        sda_i_filter <= 0;
        scl_i <= 0;
        sda_i <= 0;
        scl_i_reg <= 0;
        sda_i_reg <= 0;
    end
    else begin
        scl_i <= scl_i ? |scl_i_filter : &scl_i_filter;
        sda_i <= sda_i ? |sda_i_filter : &sda_i_filter;
        scl_i_reg <= scl_i;
        sda_i_reg <= sda_i;
        scl_i_filter <= {scl_i_filter[I2C_FILTER_DEPTH-2:0], scl_i_raw};
        sda_i_filter <= {sda_i_filter[I2C_FILTER_DEPTH-2:0], sda_i_raw};
    end
end


logic start_condition;
logic stop_condition;
assign start_condition = scl_i && sda_i_reg && !sda_i;
assign stop_condition = scl_i && !sda_i_reg && sda_i;


// I2C byte + ack read/write

logic       begin_byte;
logic       active;
logic       end_byte;
logic       end_ack;
logic [3:0] bit_counter;
logic [7:0] input_bits;
logic [7:0] output_bits;
logic       next_ack;
logic       master_read;
logic       master_acked;
logic scl_rising;
logic scl_falling;

assign scl_rising = !scl_i_reg & scl_i;
assign scl_falling = scl_i_reg & !scl_i;

always_ff @(posedge clock) begin
    if( reset || start_condition || stop_condition ) begin
        bit_counter <= 0;
        input_bits <= 0;
        master_acked <= 0;
        active <= 0;
        end_byte <= 0;
        end_ack <= 0;
        scl_o <= 1;
        sda_o <= 1;
    end
    else begin
        active <= begin_byte ? 1 
                : bit_counter >= 9 ? 0
                : active;
        end_byte <= active && scl_rising && bit_counter == 7 ? 1 : 0;
        end_ack  <= active && scl_rising && bit_counter >= 8 ? 1 : 0;

        bit_counter <= !active && begin_byte ? 0
                     : active && scl_rising && bit_counter < 9 ? bit_counter + 1
                     : bit_counter;
        input_bits <= active && bit_counter < 8 && scl_rising ? {input_bits[6:0], sda_i} : input_bits;
        master_acked <= active && scl_rising && bit_counter >= 8 ? !sda_i : master_acked;
        sda_o <= active && !scl_i && master_read  && bit_counter < 8  ? output_bits[7 - bit_counter]
               : active && !scl_i && !master_read && bit_counter == 8 ? !next_ack
               : scl_i ? sda_o
               : 1;
    end
end

// 

logic [2:0] i2c_state;
localparam STATE_IDLE = 0;
localparam STATE_DEVICE_ADDRESS = 1;
localparam STATE_REG_ADDRESS = 2;
localparam STATE_READ = 3;
localparam STATE_WRITE = 4;

always_ff @(posedge clock) begin
    if( reset ) begin
        i2c_state <= STATE_IDLE;
        begin_byte <= 0;
        next_ack <= 0;
        master_read <= 0;

        reg_is_write <= 0;
        reg_request <= 0;
        reg_address <= 0;
        reg_write_data <= 0;
    end
    else begin
        begin_byte <= 0;

        case(i2c_state)
            STATE_IDLE: begin
                if( start_condition ) begin
                    next_ack    <= 0;
                    master_read <= 0;
                    begin_byte  <= 1;
                    i2c_state   <= STATE_DEVICE_ADDRESS;
                end
            end
            STATE_DEVICE_ADDRESS: begin
                if( stop_condition ) begin
                    i2c_state <= STATE_IDLE;
                end
                else if( end_byte && input_bits[7:1] == I2C_ADDRESS ) begin
                    next_ack <= 1;  // Address match. respond ack.
                end
                else if( end_ack && input_bits[7:1] == I2C_ADDRESS ) begin
                    if( input_bits[0] ) begin   // READ
                        master_read <= 1;
                        begin_byte <= 1;
                        i2c_state <= STATE_READ;
                        reg_write_data <= 0;
                        reg_is_write <= 0;
                        reg_request <= 1;
                    end
                    else begin   // REG ADDRESS
                        master_read <= 0;
                        next_ack <= 1;
                        begin_byte <= 1;
                        i2c_state <= STATE_REG_ADDRESS;
                    end
                end
                else if( end_ack && input_bits[7:1] != I2C_ADDRESS ) begin
                    i2c_state <= STATE_IDLE;
                end
            end
            STATE_REG_ADDRESS: begin
                if( stop_condition ) begin
                    i2c_state <= STATE_IDLE;
                end
                else if( end_byte ) begin
                    reg_address <= input_bits;
                end
                else if( end_ack ) begin
                    begin_byte <= 1;
                    master_read <= 0;
                    next_ack <= 0;
                    i2c_state <= STATE_WRITE;
                end
            end
            STATE_READ: begin
                if( reg_request ) begin
                    reg_request <= 0;
                end
                output_bits <= reg_response ? reg_read_data : output_bits;

                if( stop_condition ) begin
                    i2c_state <= STATE_IDLE;
                end
                else if( start_condition ) begin
                    next_ack    <= 1;
                    master_read <= 0;
                    begin_byte  <= 1;
                    i2c_state   <= STATE_DEVICE_ADDRESS;
                end
                else if( end_ack && master_acked ) begin
                    begin_byte <= 1;
                    reg_address <= reg_address + 1;
                    reg_request <= 1;
                end
                else if( end_ack && !master_acked ) begin
                    i2c_state <= STATE_IDLE;
                end
            end
            STATE_WRITE: begin
                if( reg_request ) begin
                    reg_request <= 0;
                end
                next_ack <= reg_response ? 1 : reg_request ? reg_response : next_ack;
                if( stop_condition ) begin
                    i2c_state <= STATE_IDLE;
                end
                else if( start_condition ) begin
                    next_ack    <= 1;
                    master_read <= 0;
                    begin_byte  <= 1;
                    i2c_state   <= STATE_DEVICE_ADDRESS;
                end
                else if( end_byte ) begin
                    reg_write_data <= input_bits;
                    reg_is_write <= 1;
                    reg_request <= 1;
                end
                else if( end_ack && next_ack ) begin
                    reg_address <= reg_address + 1;
                    begin_byte <= 1;
                end
                else if( end_ack && !next_ack ) begin
                    i2c_state <= STATE_IDLE;
                end
            end
        endcase
    end
end


endmodule
    
