// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Tang Primer 25K (Dock J3) on the FPGA cartridge adapter gb_fpga_cart_de0: the test target of
// the cartridge bus test (rtl/chromatic/cart_target.veryl). Configured and read over the Dock's
// USB-UART (FT2232 interface B, 1 Mbaud 8N1) by util/chromatic_bustest; the bus master is a
// Chromatic running eda/chromatic_cart_bustest.
//
//   50 MHz -> pll_100m_50 -> 100 MHz -> CartTarget <- uart_rx / -> uart_tx (rtl/uart)
//
// Adapter signals (J3 pin): /RST 1, AUD_PWM 2, CLK 3, RST_DRV 4, /WR 5, /RD 6, /CS 7, D_DIR 8,
// /D_OE 9, D0-D7 13-20, A0-A7 21-28, A8-A15 31-38.
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
    input  wire [15:0] CART_A
);
    wire clk, lock;
    pll_100m_50 u_pll (.lock(lock), .clkout0(clk), .clkin(clk_in), .reset(1'b0));
    logic [3:0] rst_sr = 4'hF;
    always_ff @(posedge clk) rst_sr <= {rst_sr[2:0], ~lock};
    wire rst = rst_sr[3];

    wire       rx_valid, rx_ready, tx_valid, tx_ready;
    wire [7:0] rx_data, tx_data;
    uart_rx #(.BAUD_DIVIDER(100)) u_rx (
        .clock(clk), .reset(rst), .data_valid(rx_valid), .data_ready(rx_ready), .data_bits(rx_data), .rx(uart_rxd));
    uart_tx #(.BAUD_DIVIDER(100)) u_tx (
        .clock(clk), .reset(rst), .data_valid(tx_valid), .data_ready(tx_ready), .data_bits(tx_data), .tx(uart_txd));

    wire [7:0] d_out;
    wire       d_oe;
    CartTarget #(.CLK_HZ(100000000)) u_tgt (
        .i_clk(clk), .i_rst(rst),
        .i_rx_valid(rx_valid), .i_rx_data(rx_data), .o_rx_ready(rx_ready),
        .o_tx_valid(tx_valid), .o_tx_data(tx_data), .i_tx_ready(tx_ready),
        .i_a(CART_A), .i_rd_n(CART_RD_N), .i_wr_n(CART_WR_N), .i_cs_n(CART_CS_N), .i_phi(CART_CLK),
        .i_rst_n(CART_RST_N), .i_d(CART_D), .o_d(d_out), .o_d_oe(d_oe), .o_d_dir(D_DIR), .o_d_oe_n(D_OE_N),
        .o_rst_drv(RST_DRV), .o_aud(AUD_PWM));
    assign CART_D = d_oe ? d_out : 8'hzz;
endmodule
