/**
 * @file top.sv
 * @brief Top module for RISC-V Chisel Book CPU core
 */
// Copyright 2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top(
    input wire clock,
    
    input  wire key_1,
    input  wire key_2,
    input  wire key_3,
    input  wire key_4,
    input  wire key_5,
    input  wire key_6,
    input  wire key_7,
    input  wire key_8,

    output logic [7:0] led_out,
    output logic uart_tx,
    input  wire  uart_rx
);

// Reset sequencer.
logic [15:0] reset_seq;
initial begin
  reset_seq = '1;
end
always_ff @(posedge clock) begin
  reset_seq <= reset_seq >> 1;
end
logic reset;
assign reset = reset_seq[0];
logic resetn;
assign resetn = !reset;

// Assign GPIO output to LEDs.
logic [7:0] gpio_out;
assign led_out = gpio_out;

// RV core instance.
logic io_exit;
logic [8:0] io_imem_address;
logic [31:0] io_imem_data;
logic io_imem_enable;
(* mark_debug = "true" *) logic [8:0]  io_imemRead_address;
(* mark_debug = "true" *) logic [31:0] io_imemRead_data;
(* mark_debug = "true" *) logic        io_imemRead_enable;
(* mark_debug = "true" *) logic [8:0]  io_imemWrite_address;
(* mark_debug = "true" *) logic [31:0] io_imemWrite_data;
(* mark_debug = "true" *) logic        io_imemWrite_enable;
(* mark_debug = "true" *) logic [31:0] io_debugSignals_core_mem_reg_pc;
(* mark_debug = "true" *) logic [31:0] io_debugSignals_core_csr_rdata;
(* mark_debug = "true" *) logic [31:0] io_debugSignals_core_mem_reg_csr_addr;
(* mark_debug = "true" *) logic [63:0] io_debugSignals_core_cycle_counter;
(* mark_debug = "true" *) logic [31:0] io_debugSignals_raddr;
(* mark_debug = "true" *) logic [31:0] io_debugSignals_rdata;
(* mark_debug = "true" *) logic        io_debugSignals_ren;
(* mark_debug = "true" *) logic        io_debugSignals_rvalid;
(* mark_debug = "true" *) logic [31:0] io_debugSignals_waddr;
(* mark_debug = "true" *) logic        io_debugSignals_wen;
(* mark_debug = "true" *) logic        io_debugSignals_wready;
(* mark_debug = "true" *) logic [3:0]  io_debugSignals_wstrb;
(* mark_debug = "true" *) logic [31:0] io_debugSignals_wdata;

RiscV core(
    .reset(!resetn),
    .io_gpio(gpio_out),
    .io_uart_tx(uart_tx),
    .*
);

logic [31:0] imem [0:511];
initial begin
    $readmemh("../sw/bootrom.hex", imem);
end

// imem instruction bus access
always_ff @(posedge clock) begin
    if( !resetn ) begin
        io_imem_data <= 0;
    end
    else begin
        if( io_imem_enable ) begin
            io_imem_data <= imem[io_imem_address];
        end
    end
end
// imem data bus access
always_ff @(posedge clock) begin
    if( !resetn ) begin
        io_imemRead_data <= 0;
    end
    else begin
        if( io_imemRead_enable ) begin
            io_imemRead_data <= imem[io_imemRead_address[$bits(io_imemRead_address)-1:2]];
        end
        if( io_imemWrite_enable ) begin
            imem[io_imemWrite_address[$bits(io_imemWrite_address)-1:2]] <= io_imemWrite_data;
        end
    end
end

endmodule
`default_nettype wire