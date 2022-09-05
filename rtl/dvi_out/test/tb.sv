/*
 * @file tb.sv
 * @brief Testbench for dvi_out module
 */
// Copyright 2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)


`timescale 10ns/1ps

module tb ();
    logic clock;
    logic reset;
    
    logic [23:0] video_data;
    logic        video_de;
    logic        video_hsync;
    logic        video_vsync;

    logic [9:0] dvi_clock;
    logic [9:0] dvi_data0;
    logic [9:0] dvi_data1;
    logic [9:0] dvi_data2;

    logic [23:0] io_video_pixelData;
    logic        io_video_hSync;
    logic        io_video_vSync;
    logic        io_video_dataEnable;
    logic [9:0]  io_dviClock;
    logic [9:0]  io_dviData0;
    logic [9:0]  io_dviData1;
    logic [9:0]  io_dviData2;


    logic [2:0] matched;
    assign matched = {io_dviData2 == dvi_data2, io_dviData1 == dvi_data1, io_dviData0 == dvi_data0};

    DviOut reference (
        .io_video_pixelData (video_data),
        .io_video_hSync     (video_hsync),
        .io_video_vSync     (video_vsync),
        .io_video_dataEnable(video_de),
        .*
    );

    dvi_out dut (
        .*
    );

    logic [9:0] counter_h = 0;
    logic [9:0] counter_v = 0;
    localparam int h_pulse  = 3;
    localparam int h_back   = 10;
    localparam int h_active = 20;
    localparam int h_front  = 10;
    localparam int h_max_count = h_pulse + h_back + h_active + h_front - 1;
    localparam int v_pulse  = 1;
    localparam int v_back   = 10;
    localparam int v_active = 20;
    localparam int v_front  = 10;
    localparam int v_max_count = v_pulse + v_back + v_active + v_front - 1;

    initial begin
        forever begin
            clock = 1;
            #2;
            clock = 0;
            #2;
        end
    end

    always_ff @(posedge clock) begin
        if( reset ) begin
            video_data <= 0;
            video_de <= 0;
            video_hsync <= 0;
            video_vsync <= 0;

            counter_h <= 0;
            counter_v <= 0;
        end
        else begin
            video_hsync <= counter_h < h_pulse;
            video_vsync <= counter_v < v_pulse;
            video_de <= h_pulse + h_back <= counter_h && counter_h < h_pulse + h_back + h_active
                     && v_pulse + v_back <= counter_v && counter_v < v_pulse + v_back + v_active;
            
            if( counter_h == h_max_count  ) begin
                counter_h <= 0;
                if( counter_v == v_max_count ) begin
                    counter_v <= 0;
                end
                else begin
                    counter_v <= counter_v + 1;
                end
            end
            else begin
                counter_h <= counter_h + 1;
            end
        end
    end

    always_ff @(posedge clock) begin
        if( reset ) begin
            video_data <= 0;
        end
        else begin
            video_data <= video_data + 1;
        end
    end

    initial begin
        $dumpfile("output.vcd");
        $dumpvars;

        reset <= 1;
        repeat(10) @(posedge clock);
        reset <= 0;
        @(posedge clock);
        
        for(int i = 0; i < (h_max_count + 1) * (v_max_count + 1) * 3; i++) begin
            if( io_dviData0 != dvi_data0 ) $error("data0: expected: %010b actual: %010b", io_dviData0, dvi_data0);
            if( io_dviData1 != dvi_data1 ) $error("data1: expected: %010b actual: %010b", io_dviData1, dvi_data1);
            if( io_dviData2 != dvi_data2 ) $error("data2: expected: %010b actual: %010b", io_dviData2, dvi_data2);
            @(posedge clock);
        end
        
        $finish;
    end
endmodule