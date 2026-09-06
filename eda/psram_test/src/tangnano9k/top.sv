// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Tang Nano 9K: GowinPsram bring-up test on the on-package HyperRAM
// (die 0), results on the UART (115200 8N1, USB-serial of the board).
//
// The O_psram_* / IO_psram_* ports are the "magic" names the Gowin tools
// map onto the internal PSRAM bonding; they must not appear in the CST.
`default_nettype none
module top (
    input  wire        clock,        // 27MHz
    output logic [5:0] led,
    output wire        uart_tx,

    output wire  [1:0]  O_psram_ck,
    output wire  [1:0]  O_psram_ck_n,
    inout  wire  [15:0] IO_psram_dq,
    inout  wire  [1:0]  IO_psram_rwds,
    output wire  [1:0]  O_psram_cs_n,
    output wire  [1:0]  O_psram_reset_n
);
    localparam int CLK_HZ = 81_000_000;
    localparam int BAUD   = 115_200;

    // ---- clocks: 81MHz + 90 degree copy for CK ----
    logic clk, clk_p, pll_lock;
    gowin_rpll_psram pll (
        .clkin(clock), .clkout(clk), .clkoutp(clk_p), .lock(pll_lock)
    );

    // power-on reset from the PLL lock
    logic reset;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_main (
        .clock(clk), .reset_in(!pll_lock), .reset_out(reset)
    );

    // ---- controller <-> test driver ----
    logic        ctrl_rst;
    logic [1:0]  ck_delay, lat_extra;
    logic        ready;
    logic        cmd_valid, cmd_ready, cmd_write, cmd_reg;
    logic [21:0] cmd_addr;
    logic [6:0]  cmd_len;
    logic        wr_valid, wr_ready;
    logic [15:0] wr_data;
    logic [1:0]  wr_mask;
    logic        rd_valid, rd_last;
    logic [15:0] rd_data;
    logic        tx_valid, tx_ready;
    logic [7:0]  tx_data;
    logic [4:0]  status;

    PsramTest #(.CLK_HZ(CLK_HZ)) drv (
        .i_clk(clk), .i_rst(reset),
        .o_ctrl_rst(ctrl_rst), .o_ck_delay(ck_delay), .o_lat_extra(lat_extra), .i_ready(ready),
        .o_cmd_valid(cmd_valid), .i_cmd_ready(cmd_ready),
        .o_cmd_write(cmd_write), .o_cmd_reg(cmd_reg),
        .o_cmd_addr(cmd_addr), .o_cmd_len(cmd_len),
        .o_wr_valid(wr_valid), .i_wr_ready(wr_ready),
        .o_wr_data(wr_data), .o_wr_mask(wr_mask),
        .i_rd_valid(rd_valid), .i_rd_data(rd_data), .i_rd_last(rd_last),
        .o_tx_valid(tx_valid), .i_tx_ready(tx_ready), .o_tx_data(tx_data),
        .o_status(status)
    );

    // die 0 only; die 1 is held idle
    GowinPsram #(.CLK_HZ(CLK_HZ), .LATENCY(3)) psram (
        .i_clk(clk), .i_clk_p(clk_p), .i_rst(reset | ctrl_rst),
        .i_ck_delay(ck_delay), .i_lat_extra(lat_extra), .o_ready(ready),
        .i_cmd_valid(cmd_valid), .o_cmd_ready(cmd_ready),
        .i_cmd_write(cmd_write), .i_cmd_reg(cmd_reg),
        .i_cmd_addr(cmd_addr), .i_cmd_len(cmd_len),
        .i_wr_valid(wr_valid), .o_wr_ready(wr_ready),
        .i_wr_data(wr_data), .i_wr_mask(wr_mask),
        .o_rd_valid(rd_valid), .o_rd_data(rd_data), .o_rd_last(rd_last),
        .o_psram_ck(O_psram_ck[0]), .o_psram_cs_n(O_psram_cs_n[0]),
        .o_psram_reset_n(O_psram_reset_n[0]),
        .io_psram_dq(IO_psram_dq[7:0]), .io_psram_rwds(IO_psram_rwds[0])
    );
    assign O_psram_ck[1]      = 1'b0;
    assign O_psram_ck_n       = 2'b00;
    assign O_psram_cs_n[1]    = 1'b1;
    assign O_psram_reset_n[1] = O_psram_reset_n[0];
    assign IO_psram_dq[15:8]  = 8'bz;
    assign IO_psram_rwds[1]   = 1'bz;

    uart_tx #(.BAUD_DIVIDER(CLK_HZ / BAUD)) uart (
        .clock(clk), .reset(reset),
        .data_valid(tx_valid), .data_ready(tx_ready), .data_bits(tx_data),
        .tx(uart_tx)
    );

    // LEDs are active low: [5] heartbeat, [4:3] ck_delay, [2] pass
    // running, [1] last pass clean, [0] controller ready
    logic [25:0] hb = 0;
    always_ff @(posedge clk) hb <= hb + 1;
    assign led = ~{hb[25], status};
endmodule
`default_nettype wire
