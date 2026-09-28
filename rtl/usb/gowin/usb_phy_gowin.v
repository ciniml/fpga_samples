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
//
// SE_FROM_DIFF = 1 (default, from hardware bring-up 2026-09-29): the
// single-ended comparators sit at VREF ~130 mV, which is too close to the
// FS low level seen at the device (host driver + the 1.5k pull-up gives
// ~0.1 V), so their edges are late and glitchy (a J->K transition showed
// ~44 ns of SE1, the EOP SE0 was chopped). They are therefore used only to
// detect SE0 (both low, 24-sample majority), and J/K are taken from the
// differential receiver, which is clean in FS as well as HS. The data path
// is delayed by two words to line up with the SE0 filter.
// DYN_DLY = 1: an IODELAY in dynamic mode (SDTAP=0: DLYSTEP loaded as the
// absolute tap count, 12.5 ps/tap) on each of the three receive paths,
// controlled by i_dly_dd / i_dly_dp / i_dly_dn (bring-up experiments and the
// future HS phase tracking). o_mon_* expose the raw 8-sample words.
// HS_CDR = 1 (needs DYN_DLY = 1): 3x blind-oversampling clock/data recovery
// for HS. The three receivers see the same HS data; with the D+ / D-
// comparator paths delayed by 1/3 and 2/3 UI (i_dly_dp / i_dly_dn, measured
// intrinsic offset ~ +16 taps vs. the differential receiver) the 24 samples
// per word are 3 per bit. OsCdr (rtl/oscdr, OSR=3) tracks the transition
// phase and emits 7..9 bits per word; BitGearbox re-packs them into 8-bit
// words with a valid strobe that stalls the PHY (i_rx_dd_valid) on clocks
// without a full word. Idle (SE0) resets the gearbox and freezes the CDR.
module usb_phy_gowin #(
    parameter SE_FROM_DIFF = 1,
    parameter DYN_DLY      = 0,
    parameter HS_CDR       = 0
) (
    input  wire        clk_i,        // 60 MHz
    input  wire        i_track_en,   // HS_CDR: 1 = delay tracking loop (i_dly_* ignored except i_dly_dd as the manual base)
    input  wire [7:0]  i_dly_dd,
    input  wire [7:0]  i_dly_dp,
    input  wire [7:0]  i_dly_dn,
    output wire [7:0]  o_dly_dd,     // taps in use (tracking or manual)
    output wire [7:0]  o_mon_dd,
    output wire [7:0]  o_mon_dp,
    output wire [7:0]  o_mon_dn,
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

    // ---- receiver conditioning (see SE_FROM_DIFF above) ----
    wire [7:0]  rx_dp_raw, rx_dn_raw, rx_dd_raw;
    reg  [7:0]  dd_d1, dd_d2, dp_d1, dp_d2, dn_d1, dn_d2;
    reg  [3:0]  se0_c0, se0_c1, se0_c2;    // SE0 samples in the current / previous / older word
    function [3:0] popcnt8(input [7:0] v);
        integer k; begin popcnt8 = 0; for (k = 0; k < 8; k = k + 1) popcnt8 = popcnt8 + v[k]; end
    endfunction
    wire [7:0] se0_raw = ~rx_dp_raw & ~rx_dn_raw;
    always @(posedge clk_i) begin
        dd_d1 <= rx_dd_raw; dd_d2 <= dd_d1;
        dp_d1 <= rx_dp_raw; dp_d2 <= dp_d1;
        dn_d1 <= rx_dn_raw; dn_d2 <= dn_d1;
        se0_c0 <= popcnt8(se0_raw); se0_c1 <= se0_c0; se0_c2 <= se0_c1;
    end
    // majority over the 24 samples surrounding the (2-word delayed) output word
    wire se0_f = ({1'b0, se0_c0} + {1'b0, se0_c1} + {1'b0, se0_c2}) >= 5'd12;
    wire       rx_dd_valid;
    wire [7:0] rx_dp_se0, rx_dn_se0;      // SE0-conditioned single-ended view (FS/LS and the HS bus states)
    generate
        if (SE_FROM_DIFF) begin : g_se_diff
            assign rx_dp_se0 = dd_d2  & {8{~se0_f}};
            assign rx_dn_se0 = ~dd_d2 & {8{~se0_f}};
        end else begin : g_se_raw
            assign rx_dp_se0 = rx_dp_raw;
            assign rx_dn_se0 = rx_dn_raw;
        end
        if (HS_CDR) begin : g_cdr
            // in FS/LS the PHY uses sample 0 of rx_dp/rx_dn only; the CDR
            // path is selected by the PHY's transceiver mode (usb_hs_cdr.v)
            wire hs_sel = (utmi_xcvrselect_i == 2'b00) && !utmi_termselect_i;
            wire [7:0] cdr_byte, cdr_dp, cdr_dn; wire cdr_valid;
            usb_hs_cdr u_hs_cdr(
                .clk_i(clk_i), .rst_i(rst), .i_track_en(i_track_en), .i_dly_base(i_dly_dd),
                .o_dly_dd(dly_dd_w), .o_dly_dp(dly_dp_w), .o_dly_dn(dly_dn_w),
                .i_dd(dd_d2), .i_dp(dp_d2), .i_dn(dn_d2), .i_se0(se0_f),
                .o_byte(cdr_byte), .o_valid(cdr_valid), .o_dp(cdr_dp), .o_dn(cdr_dn), .o_lock());
            assign rx_dd       = hs_sel ? cdr_byte  : dd_d2;
            assign rx_dd_valid = hs_sel ? cdr_valid : 1'b1;
            assign rx_dp       = hs_sel ? cdr_dp    : rx_dp_se0;
            assign rx_dn       = hs_sel ? cdr_dn    : rx_dn_se0;
        end else begin : g_nocdr
            assign dly_dd_w = i_dly_dd; assign dly_dp_w = i_dly_dp; assign dly_dn_w = i_dly_dn;
            assign rx_dd       = dd_d2;
            assign rx_dd_valid = 1'b1;
            assign rx_dp       = rx_dp_se0;
            assign rx_dn       = rx_dn_se0;
        end
    endgenerate

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
        .i_rx_dd_valid    (rx_dd_valid),
        .o_tx_dp          (tx_dp),
        .o_tx_dn          (tx_dn),
        .o_tx_oe          (tx_oe),
        .o_pullup_dp_en   (pullup_dp_en),
        .o_pullup_dn_en   (pullup_dn_en),
        .o_term_dp_en     (term_dp_en),
        .o_term_dn_en     (term_dn_en)
    );

    // ---- receivers: LVDS input buffers -> 1:8 deserialisers (Q0 first) ----
    wire rx_dd_ib, rx_dp_ib, rx_dn_ib, rx_dd_se, rx_dp_se, rx_dn_se;
    TLVDS_IBUF u_ibuf_dd (.I(usb_rx_dp_i),  .IB(usb_rx_dn_i),  .O(rx_dd_ib));
    TLVDS_IBUF u_ibuf_dp (.I(usb_rxdp_p_i), .IB(usb_rxdp_n_i), .O(rx_dp_ib));
    TLVDS_IBUF u_ibuf_dn (.I(usb_rxdn_p_i), .IB(usb_rxdn_n_i), .O(rx_dn_ib));
    wire [7:0] dly_dd_w, dly_dp_w, dly_dn_w;      // from the CDR's tracking loop (HS_CDR) or the inputs
    wire [7:0] dly_dd_u = (HS_CDR && i_track_en) ? dly_dd_w : i_dly_dd;
    wire [7:0] dly_dp_u = (HS_CDR && i_track_en) ? dly_dp_w : i_dly_dp;
    wire [7:0] dly_dn_u = (HS_CDR && i_track_en) ? dly_dn_w : i_dly_dn;
    assign o_dly_dd = dly_dd_u;
    generate
        if (DYN_DLY) begin : g_dly
            IODELAY #(.C_STATIC_DLY(0), .DYN_DLY_EN("TRUE"), .ADAPT_EN("FALSE")) u_dly_dd(
                .DO(rx_dd_se), .DF(), .DI(rx_dd_ib), .SDTAP(1'b0), .VALUE(1'b0), .DLYSTEP(dly_dd_u));
            IODELAY #(.C_STATIC_DLY(0), .DYN_DLY_EN("TRUE"), .ADAPT_EN("FALSE")) u_dly_dp(
                .DO(rx_dp_se), .DF(), .DI(rx_dp_ib), .SDTAP(1'b0), .VALUE(1'b0), .DLYSTEP(dly_dp_u));
            IODELAY #(.C_STATIC_DLY(0), .DYN_DLY_EN("TRUE"), .ADAPT_EN("FALSE")) u_dly_dn(
                .DO(rx_dn_se), .DF(), .DI(rx_dn_ib), .SDTAP(1'b0), .VALUE(1'b0), .DLYSTEP(dly_dn_u));
        end else begin : g_nodly
            assign rx_dd_se = rx_dd_ib;
            assign rx_dp_se = rx_dp_ib;
            assign rx_dn_se = rx_dn_ib;
        end
    endgenerate
    assign o_mon_dd = rx_dd_raw;
    assign o_mon_dp = rx_dp_raw;
    assign o_mon_dn = rx_dn_raw;

    IDES8 u_ides_dd (
        .D(rx_dd_se), .FCLK(fclk_i), .PCLK(clk_i), .CALIB(1'b0), .RESET(rst),
        .Q0(rx_dd_raw[0]), .Q1(rx_dd_raw[1]), .Q2(rx_dd_raw[2]), .Q3(rx_dd_raw[3]),
        .Q4(rx_dd_raw[4]), .Q5(rx_dd_raw[5]), .Q6(rx_dd_raw[6]), .Q7(rx_dd_raw[7])
    );
    IDES8 u_ides_dp (
        .D(rx_dp_se), .FCLK(fclk_i), .PCLK(clk_i), .CALIB(1'b0), .RESET(rst),
        .Q0(rx_dp_raw[0]), .Q1(rx_dp_raw[1]), .Q2(rx_dp_raw[2]), .Q3(rx_dp_raw[3]),
        .Q4(rx_dp_raw[4]), .Q5(rx_dp_raw[5]), .Q6(rx_dp_raw[6]), .Q7(rx_dp_raw[7])
    );
    IDES8 u_ides_dn (
        .D(rx_dn_se), .FCLK(fclk_i), .PCLK(clk_i), .CALIB(1'b0), .RESET(rst),
        .Q0(rx_dn_raw[0]), .Q1(rx_dn_raw[1]), .Q2(rx_dn_raw[2]), .Q3(rx_dn_raw[3]),
        .Q4(rx_dn_raw[4]), .Q5(rx_dn_raw[5]), .Q6(rx_dn_raw[6]), .Q7(rx_dn_raw[7])
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
