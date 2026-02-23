/**
 * @file top.sv
 * @brief Top module for DVI test pattern generator design.
 */
// Copyright 2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top(
    input wire clock, // On board 27MHz clock

    // PSRAM (on-chip)
    output [1:0] O_psram_ck,
		output [1:0] O_psram_ck_n,
		inout [15:0] IO_psram_dq,
		inout [1:0] IO_psram_rwds,
		output [1:0] O_psram_cs_n,
		output [1:0] O_psram_reset_n
);

logic clock_main;      // Main clock, 54MHz
logic clock_psram;     // PSRAM clock, 108MHz
logic lock_main_psram; // Lock signal for PLL
logic reset_out;       // Reset signal (Active High)

// Instantiate PLL
gowin_pllvr pll_inst(
    .clkout(clock_main),       // output clkout
    .lock(lock_main_psram),    // output lock
    .clkoutd(clock_psram),     // output clkoutd
    .clkin(clock)              // input clkin
);

reset_seq #() reset_seq_inst(
    .reset_in(!lock_main_psram),
    .clock(clock_main),
    .reset_out(reset_out)
);

// PSRAM memory IF signals
logic [63:0] wr_data; // Write data
logic [63:0] rd_data; // Read data
logic rd_data_valid;  // Read data valid
logic [20:0] addr;    // Address
logic [1:0] cmd;      // Command
logic cmd_en;         // Command enable
logic init_calib;     // Initial calibration
logic clk_out;        // Clock out
logic [7:0] data_mask; // Data mask

// Instantiate PSRAM memory IF
psram_memory_interface_hs psram_inst(
  .clk(clock_main), //input clk
  .memory_clk(clock_psram), //input memory_clk
  .pll_lock(lock_main_psram), //input pll_lock
  .rst_n(!reset_out), //input rst_n
  .O_psram_ck(O_psram_ck), //output [1:0] O_psram_ck
  .O_psram_ck_n(O_psram_ck_n), //output [1:0] O_psram_ck_n
  .IO_psram_dq(IO_psram_dq), //inout [15:0] IO_psram_dq
  .IO_psram_rwds(IO_psram_rwds), //inout [1:0] IO_psram_rwds
  .O_psram_cs_n(O_psram_cs_n), //output [1:0] O_psram_cs_n
  .O_psram_reset_n(O_psram_reset_n), //output [1:0] O_psram_reset_n
  .wr_data(wr_data), //input [63:0] wr_data
  .rd_data(rd_data), //output [63:0] rd_data
  .rd_data_valid(rd_data_valid), //output rd_data_valid
  .addr(addr), //input [20:0] addr
  .cmd(cmd), //input cmd
  .cmd_en(cmd_en), //input cmd_en
  .init_calib(init_calib), //output init_calib
  .clk_out(clk_out), //output clk_out
  .data_mask(data_mask) //input [7:0] data_mask
);

endmodule
`default_nettype wire