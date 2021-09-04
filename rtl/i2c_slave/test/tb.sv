/*
 * @file tb.sv
 * @brief Testbench for i2c_slave module
 */
// Copyright 2019 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


`timescale 10ns/1ps

module tb ();
    localparam I2C_REG_ADDRESS_WIDTH = 8;
    localparam I2C_CLOCK_PERIOD = 1000;

    logic clock;
    logic reset;
    wire scl;
    wire sda;

    logic [I2C_REG_ADDRESS_WIDTH-1:0] reg_address;
    logic reg_is_write;
    logic reg_request;
    logic reg_response;
    logic [7:0] reg_read_data;
    logic [7:0] reg_write_data;

    i2c_slave #(
        .I2C_REG_ADDRESS_WIDTH(I2C_REG_ADDRESS_WIDTH)
    ) dut (
        .*
    );

    initial begin
        forever begin
            clock = 1;
            #2;
            clock = 0;
            #2;
        end
    end

    // registers
    bit [7:0] regs [255:0];
    initial begin
        for(int i = 0; i < 255; i++) begin
            regs[i] = i;
        end
    end
    always @(posedge clock) begin
        if( reset ) begin
            reg_read_data <= 0;
        end
        else begin
            if( reg_request ) begin
                if( reg_is_write )  begin
                    regs[reg_address] <= reg_write_data;
                end else begin
                    reg_read_data <= regs[reg_address];
                end
                reg_response <= 1;
            end
            else begin
                reg_response <= 0;
            end
        end
    end

    // SCL/SDA tri-state buffer setup.
    pullup(scl);
    pullup(sda);

    logic scl_i;
    logic scl_o;
    logic sda_i;
    logic sda_o;
    
    IOBUF scl_buf(
        .I(1'b0),
        .O(scl_i),
        .IO(scl),
        .OEN(scl_o)
    );

    IOBUF sda_buf(
        .I(1'b0),
        .O(sda_i),
        .IO(sda),
        .OEN(sda_o)
    );

    task automatic i2c_start;
        scl_o <= 1;
        sda_o <= 1;
        #I2C_CLOCK_PERIOD;
        sda_o <= 0;
        #I2C_CLOCK_PERIOD;
    endtask

    task automatic i2c_stop;
        scl_o <= 1;
        sda_o <= 0;
        #I2C_CLOCK_PERIOD;
        sda_o <= 0;
        #I2C_CLOCK_PERIOD;
    endtask

    task automatic i2c_read(output bit [7:0] data, input bit ack);
        scl_o <= 1;
        for(int i = 7; i >= 0; i--) begin
            scl_o <= 0;
            #(I2C_CLOCK_PERIOD/2);
            scl_o <= 1;
            #(I2C_CLOCK_PERIOD/4);
            data[i] = sda_i;
            #(I2C_CLOCK_PERIOD/4);
        end
        scl_o <= 0;
        #(I2C_CLOCK_PERIOD/4);
        sda_o <= !ack;
        #(I2C_CLOCK_PERIOD/4);
        scl_o <= 1;
        #(I2C_CLOCK_PERIOD/2);
        scl_o <= 0;
        #(I2C_CLOCK_PERIOD/2);
    endtask

    task automatic i2c_write(input bit [7:0] data, output bit ack);
        scl_o <= 1;
        for(int i = 7; i >= 0; i--) begin
            scl_o <= 0;
            sda_o <= data[i];
            #(I2C_CLOCK_PERIOD/2);
            scl_o <= 1;
            #(I2C_CLOCK_PERIOD/2);
        end
        scl_o <= 0;
        sda_o <= 1;
        #(I2C_CLOCK_PERIOD/2);
        scl_o <= 1;
        #(I2C_CLOCK_PERIOD/4);
        ack = !sda_i;
        #(I2C_CLOCK_PERIOD/4);
        scl_o <= 0;
        #(I2C_CLOCK_PERIOD/2);
    endtask

    task automatic i2c_register_read(input bit [6:0] device, bit [7:0] reg_address, output bit [7:0] reg_value, output bit success );
        bit ack;
        bit success_;

        success = 0;

        i2c_start;
        i2c_write({device, 1'b0}, ack);
        if( ack ) begin
            i2c_write(reg_address, ack);
            if( ack ) begin 
                i2c_start;
                i2c_write({device, 1'b1}, ack);
                if( ack ) begin
                    i2c_read(reg_value, 0);
                    success = 1;
                end
            end
        end
        i2c_stop;
    endtask

    task automatic i2c_register_write(input bit [6:0] device, bit [7:0] reg_address, bit [7:0] reg_value, output bit success );
        bit ack;
        
        success = 0;

        i2c_start;
        i2c_write({device, 1'b0}, ack);
        if( ack ) begin
            i2c_write(reg_address, ack);
            if( ack ) begin
                i2c_write(reg_value, ack);
                if( ack ) begin
                    success = 1;
                end
            end
        end

        i2c_stop;
    endtask

    initial begin
        bit [7:0] data;
        bit [7:0] new_value;
        bit success;
        int i, j;

        $dumpfile("output.vcd");
        $dumpvars;

        reset <= 1;
        
        scl_o <= 1;
        sda_o <= 1;
        
        repeat(2) @(posedge clock);
        reset <= 0;
        @(posedge clock);
        

        for(i = 0; i < 255; i++ ) begin
            i2c_register_read(7'h48, i, data, success);
            if( !success ) $error("reg #%02x: read failed", i);
            if( success && data != i ) $error("reg #%02x: data mismatch, expected=%02x, actual=%02x", i, i, data);
        end

        for(i = 0; i < 255; i++ ) begin
            for(j = 0; j < 7; j++ ) begin
                new_value[j] = i[7 - j];
            end
            i2c_register_write(7'h48, i, new_value, success);
            if( !success ) $error("reg #%02x: write failed", i);
            i2c_register_read(7'h48, i, data, success);
            if( !success ) $error("reg #%02x: read failed", i);
            if( success && new_value != data ) $error("reg #%02x: data mismatch, expected=%02x, actual=%02x", i, new_value, data);
        end
        
        i2c_start;
        i2c_stop;
        i2c_register_read(7'h48, i, data, success);
        if( !success ) $error("read failed after start-stop malformed transaction");
        
        $finish;
    end
endmodule