// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Tang Primer 25K (Dock J3) on the FPGA cartridge adapter gb_fpga_cart_de0 as a game cartridge
// (rtl/chromatic/game_cart.veryl): ROM bank 0 and the cartridge RAM in block RAM, the switchable
// ROM bank read from the core board's W25Q64 in QPI mode (rtl/chromatic/qspi_rom.veryl, image at
// 4 MiB). Loaded and read over the Dock's USB-UART (FT2232 interface B, 1 Mbaud 8N1) by
// util/cart_emu (game subcommands). Adapter pins as eda/cart_target.
//
//   50 MHz -> PLLA -> 100 MHz (GameCart, UART) / 200 MHz (QspiRom, SCLK 100 MHz)
module top (
    input  wire        clk_in,
    input  wire        uart_rxd,
    output wire        uart_txd,

    input  wire        CART_RST_N,
    output wire        AUD_PWM,
    input  wire        CART_CLK,
    output wire        RST_DRV,
    input  wire        CART_WR_N,
    input  wire        CART_RD_N,
    input  wire        CART_CS_N,
    output wire        D_DIR,
    output wire        D_OE_N,
    inout  wire [7:0]  CART_D,
    input  wire [15:0] CART_A,

    output wire        FL_CS_N,
    output wire        FL_SCLK,
    inout  wire [3:0]  FL_IO
);
    wire clk, clk2, lock;
    pll_100m_200m_50 u_pll (.lock(lock), .clkout0(clk), .clkout1(clk2), .clkin(clk_in), .reset(1'b0));
    logic [3:0] rst_sr = 4'hF;
    always_ff @(posedge clk) rst_sr <= {rst_sr[2:0], ~lock};
    wire rst = rst_sr[3];
    logic [3:0] rst2_sr = 4'hF;
    always_ff @(posedge clk2) rst2_sr <= {rst2_sr[2:0], ~lock};
    wire rst2 = rst2_sr[3];

    wire       rx_valid, rx_ready, tx_valid, tx_ready;
    wire [7:0] rx_data, tx_data;
    uart_rx #(.BAUD_DIVIDER(100)) u_rx (
        .clock(clk), .reset(rst), .data_valid(rx_valid), .data_ready(rx_ready), .data_bits(rx_data), .rx(uart_rxd));
    uart_tx #(.BAUD_DIVIDER(100)) u_tx (
        .clock(clk), .reset(rst), .data_valid(tx_valid), .data_ready(tx_ready), .data_bits(tx_data), .tx(uart_txd));

    wire        fl_quad, fl_spiq, fl_cont, fl_ready, fl_want, fl_dval, raw_cs, raw_go, raw_done;
    wire [1:0]  fl_cap;
    wire [23:0] fl_addr, fl_daddr;
    wire [7:0]  fl_data, raw_tx, raw_rx;
    wire [7:0]  d_out;
    wire        d_oe;
    GameCart #(.CLK_HZ(100000000)) u_cart (
        .i_clk(clk), .i_rst(rst),
        .i_rx_valid(rx_valid), .i_rx_data(rx_data), .o_rx_ready(rx_ready),
        .o_tx_valid(tx_valid), .o_tx_data(tx_data), .i_tx_ready(tx_ready),
        .i_a(CART_A), .i_rd_n(CART_RD_N), .i_wr_n(CART_WR_N), .i_cs_n(CART_CS_N), .i_phi(CART_CLK),
        .i_rst_n(CART_RST_N), .i_d(CART_D), .o_d(d_out), .o_d_oe(d_oe), .o_d_dir(D_DIR), .o_d_oe_n(D_OE_N),
        .o_rst_drv(RST_DRV),
        .o_fl_quad(fl_quad), .i_fl_ready(fl_ready), .o_fl_cap(fl_cap), .o_fl_spiq(fl_spiq), .o_fl_cont(fl_cont), .o_fl_want(fl_want), .o_fl_addr(fl_addr),
        .i_fl_data(fl_data), .i_fl_daddr(fl_daddr), .i_fl_dval(fl_dval),
        .o_raw_cs(raw_cs), .o_raw_go(raw_go), .o_raw_tx(raw_tx), .i_raw_rx(raw_rx), .i_raw_done(raw_done));
    assign CART_D = d_oe ? d_out : 8'hzz;
    assign AUD_PWM = 1'b0;

    wire [3:0] io_o, io_oe;
    QspiRom u_fl (
        .i_clk(clk2), .i_rst(rst2),
        .i_quad(fl_quad), .o_ready(fl_ready), .i_cap(fl_cap), .i_spiq(fl_spiq), .i_cont(fl_cont), .i_want(fl_want), .i_addr(fl_addr),
        .o_data(fl_data), .o_daddr(fl_daddr), .o_dval(fl_dval),
        .i_raw_cs(raw_cs), .i_raw_go(raw_go), .i_raw_tx(raw_tx), .o_raw_rx(raw_rx), .o_raw_done(raw_done),
        .o_sclk(FL_SCLK), .o_cs_n(FL_CS_N), .o_io(io_o), .o_io_oe(io_oe), .i_io(FL_IO));
    genvar i;
    generate for (i = 0; i < 4; i++) begin : g_io
        assign FL_IO[i] = io_oe[i] ? io_o[i] : 1'bz;
    end endgenerate
endmodule
