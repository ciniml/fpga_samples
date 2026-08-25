// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Gowin serial front end for UsbPhy, following the "USB2.0-RC" circuit of
// Gowin TN710 (USB 2.0 SoftPHY Device Peripheral Circuit Design
// Application Note) and the IDES8/OSER8 structure of IPUG781 fig. 3-1.
// 11 FPGA I/Os:
//
//   usb_rx_d      (pair)   differential D+/D- receiver (TN710 USB_RX_D+/-,
//                          TRUE LVDS pin, R4/R5 = 0 ohm). HS data.
//   usb_rxdp_i    (pair)   single-ended D+ : P = D+, N = VREF (~130 mV,
//                          R8 1.8k / R9 75 ohm / C1 1 uF)  -> LineState, FS
//   usb_rxdn_i    (pair)   single-ended D- : P = D-, N = VREF
//   usb_tx_d      (pair)   LVCMOS33D driver, series R6/R7 (42 ohm LittleBee /
//                          Arora, 100 ohm Arora-V), tri-stated when idle
//   usb_term_dp_o / dn_o   HS 45 ohm terminations: pin driven low through
//                          R2/R3 (0 ohm, DRIVE=16 on LittleBee/Arora; 36 ohm,
//                          DRIVE=8 on Arora-V), Z otherwise
//   usb_pullup_en_o        1.5k (R1) D+ pull-up, driven high in FS
//
// Clocks: clk_i = 60 MHz PCLK, fclk_i = 240 MHz FCLK (IDES8/OSER8 DDR ->
// 8 samples per PCLK = 480 Msps), same PLL. pll_locked_i releases reset.
//
// NOTE: not verified on hardware or with Gowin simulation models in this
// repository (no primitive models available here); the UsbPhy core is
// verified by `veryl test` at the sample level. Bit-phase alignment of the
// 1-sample-per-bit HS receiver (Gowin "TX Delay" / IODELAY) is left to the
// integrator: sweep an IODELAY on usb_rx_d during bring-up.
`timescale 1ns/1ps
module usb_phy_gowin (
    input  wire        clk_i,        // 60 MHz
    input  wire        fclk_i,       // 240 MHz (DDR -> 480 Msps)
    input  wire        rst_i,
    input  wire        pll_locked_i,

    // UTMI
    input  wire [7:0]  utmi_data_out_i,
    input  wire        utmi_txvalid_i,
    output wire        utmi_txready_o,
    output wire [7:0]  utmi_data_in_o,
    output wire        utmi_rxactive_o,
    output wire        utmi_rxvalid_o,
    output wire        utmi_rxerror_o,
    output wire [1:0]  utmi_linestate_o,
    input  wire [1:0]  utmi_opmode_i,
    input  wire [1:0]  utmi_xcvrselect_i,
    input  wire        utmi_termselect_i,

    // USB2.0-RC pins (TN710)
    input  wire        usb_rx_dp_i,     // USB_RX_D+  (LVDS pair P)
    input  wire        usb_rx_dn_i,     // USB_RX_D-  (LVDS pair N)
    input  wire        usb_rxdp_p_i,    // USB_RXDP_D+ = D+
    input  wire        usb_rxdp_n_i,    // USB_RXDP_D- = VREF
    input  wire        usb_rxdn_p_i,    // USB_RXDN_D+ = D-
    input  wire        usb_rxdn_n_i,    // USB_RXDN_D- = VREF
    output wire        usb_tx_dp_o,     // USB_TX_D+
    output wire        usb_tx_dn_o,     // USB_TX_D-
    output wire        usb_pullup_en_o,
    output wire        usb_term_dp_o,
    output wire        usb_term_dn_o
);
    wire        rst = rst_i | ~pll_locked_i;
    wire [7:0]  rx_dp, rx_dn, rx_dd, tx_dp, tx_dn;
    wire        tx_oe;
    wire        pullup_dp_en, pullup_dn_en, term_dp_en, term_dn_en;

    UsbPhy u_phy (
        .i_clk            (clk_i),
        .i_rst            (rst),
        .i_utmi_data_out  (utmi_data_out_i),
        .i_utmi_txvalid   (utmi_txvalid_i),
        .o_utmi_txready   (utmi_txready_o),
        .o_utmi_data_in   (utmi_data_in_o),
        .o_utmi_rxactive  (utmi_rxactive_o),
        .o_utmi_rxvalid   (utmi_rxvalid_o),
        .o_utmi_rxerror   (utmi_rxerror_o),
        .o_utmi_linestate (utmi_linestate_o),
        .i_utmi_opmode    (utmi_opmode_i),
        .i_utmi_xcvrselect(utmi_xcvrselect_i),
        .i_utmi_termselect(utmi_termselect_i),
        .i_rx_dp          (rx_dp),
        .i_rx_dn          (rx_dn),
        .i_rx_dd          (rx_dd),
        .o_tx_dp          (tx_dp),
        .o_tx_dn          (tx_dn),
        .o_tx_oe          (tx_oe),
        .o_pullup_dp_en   (pullup_dp_en),
        .o_pullup_dn_en   (pullup_dn_en),
        .o_term_dp_en     (term_dp_en),
        .o_term_dn_en     (term_dn_en)
    );

    // ---- receivers: LVDS input buffers -> 1:8 deserialisers (Q0 first) ----
    wire rx_dd_se, rx_dp_se, rx_dn_se;
    TLVDS_IBUF u_ibuf_dd (.I(usb_rx_dp_i),  .IB(usb_rx_dn_i),  .O(rx_dd_se));
    TLVDS_IBUF u_ibuf_dp (.I(usb_rxdp_p_i), .IB(usb_rxdp_n_i), .O(rx_dp_se));
    TLVDS_IBUF u_ibuf_dn (.I(usb_rxdn_p_i), .IB(usb_rxdn_n_i), .O(rx_dn_se));

    IDES8 u_ides_dd (
        .D(rx_dd_se), .FCLK(fclk_i), .PCLK(clk_i), .CALIB(1'b0), .RESET(rst),
        .Q0(rx_dd[0]), .Q1(rx_dd[1]), .Q2(rx_dd[2]), .Q3(rx_dd[3]),
        .Q4(rx_dd[4]), .Q5(rx_dd[5]), .Q6(rx_dd[6]), .Q7(rx_dd[7])
    );
    IDES8 u_ides_dp (
        .D(rx_dp_se), .FCLK(fclk_i), .PCLK(clk_i), .CALIB(1'b0), .RESET(rst),
        .Q0(rx_dp[0]), .Q1(rx_dp[1]), .Q2(rx_dp[2]), .Q3(rx_dp[3]),
        .Q4(rx_dp[4]), .Q5(rx_dp[5]), .Q6(rx_dp[6]), .Q7(rx_dp[7])
    );
    IDES8 u_ides_dn (
        .D(rx_dn_se), .FCLK(fclk_i), .PCLK(clk_i), .CALIB(1'b0), .RESET(rst),
        .Q0(rx_dn[0]), .Q1(rx_dn[1]), .Q2(rx_dn[2]), .Q3(rx_dn[3]),
        .Q4(rx_dn[4]), .Q5(rx_dn[5]), .Q6(rx_dn[6]), .Q7(rx_dn[7])
    );

    // ---- transmitter: one OSER8 per line, tri-stated together ----
    // OSER8 TX0..TX3 are the per-bit-pair output enables (active low =
    // drive); Q1 is the serialised OEN for the pad.
    wire tx_oen = ~tx_oe;
    wire tx_dp_q, tx_dn_q, tx_dp_oen, tx_dn_oen;
    OSER8 u_oser_dp (
        .D0(tx_dp[0]), .D1(tx_dp[1]), .D2(tx_dp[2]), .D3(tx_dp[3]),
        .D4(tx_dp[4]), .D5(tx_dp[5]), .D6(tx_dp[6]), .D7(tx_dp[7]),
        .TX0(tx_oen), .TX1(tx_oen), .TX2(tx_oen), .TX3(tx_oen),
        .FCLK(fclk_i), .PCLK(clk_i), .RESET(rst),
        .Q0(tx_dp_q), .Q1(tx_dp_oen)
    );
    OSER8 u_oser_dn (
        .D0(tx_dn[0]), .D1(tx_dn[1]), .D2(tx_dn[2]), .D3(tx_dn[3]),
        .D4(tx_dn[4]), .D5(tx_dn[5]), .D6(tx_dn[6]), .D7(tx_dn[7]),
        .TX0(tx_oen), .TX1(tx_oen), .TX2(tx_oen), .TX3(tx_oen),
        .FCLK(fclk_i), .PCLK(clk_i), .RESET(rst),
        .Q0(tx_dn_q), .Q1(tx_dn_oen)
    );
    // Pseudo-differential LVCMOS33D pair as two tri-state pads (TN710 uses
    // one differential pad pair; the levels are identical). SE0 needs both
    // low, which a true differential driver cannot produce, hence two pads.
    TBUF u_tbuf_dp (.I(tx_dp_q), .OEN(tx_dp_oen), .O(usb_tx_dp_o));
    TBUF u_tbuf_dn (.I(tx_dn_q), .OEN(tx_dn_oen), .O(usb_tx_dn_o));

    // ---- terminations / pull-up (external R1..R3, TN710) ----
    assign usb_pullup_en_o = pullup_dp_en;             // R1 1.5k to D+
    assign usb_term_dp_o   = term_dp_en ? 1'b0 : 1'bz; // pin Z_out (+R2) = 45 ohm
    assign usb_term_dn_o   = term_dn_en ? 1'b0 : 1'bz;
endmodule
