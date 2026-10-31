// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// GW5A wrapper of the transformerless 100BASE-TX PHY (rtl/eth100_phy):
// clocks, comparator deserializers and pads.
//
//   clk_in 50 MHz -> pll_eth100 -> fclk 250 MHz -> CLKDIV /2 -> pclk 125 MHz
//   comparator A / B : TLVDS_IBUF (LVDS25 input, no on-die termination: the
//                      board biases the pins, README §3.2) -> IDES4
//                      (fclk DDR = 500 MS/s, 4 samples per 125 MHz pclk =
//                      4 per 8 ns symbol, Q0 = earliest)
//   TX_P / TX_N, PWM_A / PWM_B : plain LVCMOS33 outputs from pclk registers
//
// The whole PHY (and the user logic on the MII side) runs on pclk; o_rst is
// a pclk-synchronous reset released after the PLL locks and the divider
// starts.
`timescale 1ns/1ps
module eth100_phy_gw5a #(
    parameter TDIV   = 1,
    parameter AN_DIV = 1
) (
    input  wire        clk_in,
    input  wire        reset_in,     // active high (button)

    // pads
    input  wire        cmp_a_p, cmp_a_n,
    input  wire        cmp_b_p, cmp_b_n,
    output wire        tx_p_o, tx_n_o,
    output wire        pwm_a_o, pwm_b_o,

    output wire        pclk_o,
    output wire        rst_o,
    output wire        pll_lock_o,

    // control (pclk domain)
    input  wire [9:0]  th_a, th_b,
    input  wire        force_100,
    input  wire        an_restart,
    input  wire        cdr_freeze,

    // MII (strobed, pclk domain)
    output wire        tx_req,
    input  wire        tx_en,
    input  wire        tx_er,
    input  wire [3:0]  tx_data,
    output wire        rx_valid,
    output wire [3:0]  rx_data,
    output wire        rx_er,
    output wire        rx_sof,
    output wire        rx_eof,
    output wire        rx_dv,

    // status
    output wire        link,
    output wire        full_duplex,
    output wire        parallel,
    output wire [2:0]  an_state,
    output wire [15:0] lp_page,
    output wire        cdr_lock,
    output wire        scr_lock,
    output wire        flp_pulse,
    output wire        cdr_slip,
    output wire [3:0]  samp_a_o,     // raw comparator words (debug)
    output wire [3:0]  samp_b_o
);
    // ---- clocks ----
    wire pll_lock;
    wire fclk /* synthesis syn_keep=1 */;
    wire pclk /* synthesis syn_keep=1 */;
    pll_eth100 u_pll(.lock(pll_lock), .clkout0(fclk), .clkin(clk_in));
    wire resetn_div = pll_lock & ~reset_in;
    CLKDIV u_clkdiv(.HCLKIN(fclk), .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(pclk));
    defparam u_clkdiv.DIV_MODE = "2";
    reg [3:0] rst_sync;
    always @(posedge pclk or negedge resetn_div)
        if (!resetn_div) rst_sync <= 4'hf; else rst_sync <= {rst_sync[2:0], 1'b0};
    wire rst = rst_sync[3];
    assign pclk_o     = pclk;
    assign rst_o      = rst;
    assign pll_lock_o = pll_lock;

    // ---- comparators -> IDES4 ----
    wire a_ib, b_ib;
    TLVDS_IBUF u_ibuf_a(.I(cmp_a_p), .IB(cmp_a_n), .O(a_ib));
    TLVDS_IBUF u_ibuf_b(.I(cmp_b_p), .IB(cmp_b_n), .O(b_ib));
    wire [3:0] sa, sb;
    IDES4 u_ides_a(.D(a_ib), .FCLK(fclk), .PCLK(pclk), .CALIB(1'b0), .RESET(rst),
                   .Q0(sa[0]), .Q1(sa[1]), .Q2(sa[2]), .Q3(sa[3]));
    IDES4 u_ides_b(.D(b_ib), .FCLK(fclk), .PCLK(pclk), .CALIB(1'b0), .RESET(rst),
                   .Q0(sb[0]), .Q1(sb[1]), .Q2(sb[2]), .Q3(sb[3]));
    // one register stage between the IDES outputs and the CDR (placement freedom)
    reg [3:0] sa_r, sb_r;
    always @(posedge pclk) begin
        sa_r <= sa;
        sb_r <= sb;
    end
    assign samp_a_o = sa_r;
    assign samp_b_o = sb_r;

    // ---- PHY core ----
    wire tx_p, tx_n, pwm_a, pwm_b;
    Eth100Phy #(.SAMPLES(4), .OSR(4), .TDIV(TDIV), .AN_DIV(AN_DIV)) u_phy (
        .i_clk(pclk), .i_rst(rst),
        .i_samp_a(sa_r), .i_samp_b(sb_r),
        .o_tx_p(tx_p), .o_tx_n(tx_n), .o_pwm_a(pwm_a), .o_pwm_b(pwm_b),
        .i_th_a(th_a), .i_th_b(th_b), .i_force_100(force_100), .i_an_restart(an_restart),
        .i_cdr_freeze(cdr_freeze),
        .o_tx_req(tx_req), .i_tx_en(tx_en), .i_tx_er(tx_er), .i_tx_data(tx_data),
        .o_rx_valid(rx_valid), .o_rx_data(rx_data), .o_rx_er(rx_er), .o_rx_sof(rx_sof),
        .o_rx_eof(rx_eof), .o_rx_dv(rx_dv),
        .o_link(link), .o_full_duplex(full_duplex), .o_parallel(parallel), .o_an_state(an_state),
        .o_lp_page(lp_page), .o_cdr_lock(cdr_lock), .o_scr_lock(scr_lock), .o_flp_pulse(flp_pulse),
        .o_cdr_slip(cdr_slip));

    // ---- output registers (pack into the IOB; TX_P/TX_N switch together) ----
    reg tx_p_r /* synthesis syn_useioff=1 */;
    reg tx_n_r /* synthesis syn_useioff=1 */;
    reg pwm_a_r, pwm_b_r;
    always @(posedge pclk) begin
        tx_p_r  <= tx_p;
        tx_n_r  <= tx_n;
        pwm_a_r <= pwm_a;
        pwm_b_r <= pwm_b;
    end
    assign tx_p_o  = tx_p_r;
    assign tx_n_o  = tx_n_r;
    assign pwm_a_o = pwm_a_r;
    assign pwm_b_o = pwm_b_r;
endmodule
