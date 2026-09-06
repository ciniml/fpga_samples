`define USER_RMII
// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Tang Nano 9K: PsramDwordCache + GowinPsram test. The user side of the
// cache runs on a separate clock (USER_ASYNC=1: the 27MHz crystal,
// asynchronous to the 81MHz PSRAM clock like in the NVMe design;
// USER_ASYNC=0: the PSRAM clock itself) to isolate CDC effects.
`default_nettype none
module top (
    input  wire        clock,        // 27MHz
    input  wire        rmii_txclk,   // 50MHz from the Ethernet PHY (truly asynchronous to pclk)
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
`ifdef USER_SYNC
    localparam USER_ASYNC = 0;
`elsif USER_RMII
    localparam USER_ASYNC = 2;
`else
    localparam USER_ASYNC = 1;
`endif

    logic pclk, pclk_p, pll_lock;
    gowin_rpll_psram pll (
        .clkin(clock), .clkout(pclk), .clkoutp(pclk_p), .lock(pll_lock)
    );
    logic preset;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_psram (
        .clock(pclk), .reset_in(!pll_lock), .reset_out(preset)
    );
    // USER_ASYNC: 0 = pclk (synchronous), 1 = 27MHz crystal (pclk is its
    // 3x multiple: phase-locked, not a real CDC), 2 = the PHY's 50MHz
    wire  uclk = USER_ASYNC == 2 ? rmii_txclk : USER_ASYNC == 1 ? clock : pclk;
    logic ureset;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_user (
        .clock(uclk), .reset_in(!pll_lock), .reset_out(ureset)
    );

    logic [19:0] addr;
    logic        wen, ren, ready;
    logic [31:0] wdata, rdata;
    logic        tx_valid, tx_ready;
    logic [7:0]  tx_data;
    logic [2:0]  status;
    CacheTest drv (
        .i_clk(uclk), .i_rst(ureset),
        .o_addr(addr), .o_wen(wen), .o_wdata(wdata), .o_ren(ren), .i_rdata(rdata), .i_ready(ready),
        .o_tx_valid(tx_valid), .i_tx_ready(tx_ready), .o_tx_data(tx_data), .o_status(status)
    );

    wire        ps_ready;
    wire        cmd_valid, cmd_ready, cmd_write;
    wire [21:0] cmd_addr;
    wire [5:0]  cmd_len;
    wire        wr_valid, wr_ready;
    wire [15:0] wr_data;
    wire [1:0]  wr_mask;
    wire        rd_valid, rd_last;
    wire [15:0] rd_data;
    PsramDwordCache #(.ADDR_BITS(20)) cache (
        .i_clk(uclk), .i_rst(ureset),
        .i_addr(addr), .i_wen(wen), .i_wdata(wdata), .i_ren(ren),
        .o_rdata(rdata), .o_ready(ready), .o_dbg(),
        .i_pclk(pclk), .i_prst(preset), .i_pready(ps_ready),
        .o_cmd_valid(cmd_valid), .i_cmd_ready(cmd_ready), .o_cmd_write(cmd_write),
        .o_cmd_addr(cmd_addr), .o_cmd_len(cmd_len),
        .o_wr_valid(wr_valid), .i_wr_ready(wr_ready), .o_wr_data(wr_data), .o_wr_mask(wr_mask),
        .i_rd_valid(rd_valid), .i_rd_data(rd_data), .i_rd_last(rd_last)
    );
    GowinPsram #(.CLK_HZ(CLK_HZ), .LATENCY(3)) psram (
        .i_clk(pclk), .i_clk_p(pclk_p), .i_rst(preset), .o_ready(ps_ready),
        .i_cmd_valid(cmd_valid), .o_cmd_ready(cmd_ready),
        .i_cmd_write(cmd_write), .i_cmd_reg(1'b0),
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

    uart_tx #(.BAUD_DIVIDER(USER_ASYNC == 2 ? 50_000_000 / 115_200 : USER_ASYNC == 1 ? 27_000_000 / 115_200 : CLK_HZ / 115_200)) uart (
        .clock(uclk), .reset(ureset),
        .data_valid(tx_valid), .data_ready(tx_ready), .data_bits(tx_data),
        .tx(uart_tx)
    );

    logic [25:0] hb = 0;
    always_ff @(posedge pclk) hb <= hb + 1;
    assign led = ~{hb[25], 1'b0, status, ps_ready};
endmodule
`default_nettype wire
