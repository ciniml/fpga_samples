// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file csi_phy_gw5a.sv
 * @brief D-PHY HS front end for GW5A: three differential receivers
 *        (clock lane + 2 data lanes) oversampled by OSIDES32.
 *
 *   50 MHz ─► PLLA (PLL_T) 500 MHz × 0/90/180/270° ─► DHCE ─► OSIDES32 ×3
 *                                         └► CLKDIV /4 ─► o_pclk 125 MHz
 *
 * Each OSIDES32 takes 8 samples per 500 MHz period (4 phases × its two
 * static IODELAY taps, DLY1 = a quarter of the phase spacing later):
 * 32 samples per 125 MHz word, [0] = earliest, 250 ps apart = ~8.8 per UI
 * at 456 Mbps, ~4.4 at 912 Mbps. The sampling clock is free-running and
 * unrelated to the camera: the clock lane is sampled like a data lane and
 * Csi2EdgeSampler takes the data at its edges.
 *
 * Same clocking / reset sequence as eda/easycdr_bert oscdr_phy_gw5a.v
 * (proven on the same pmod0 pins / bank 1 HCLK in eda/easycdr_trace):
 * DHCE gates the four phases until the PLL has locked, CLKDIV is released
 * 16 reference clocks after lock, the PCLK-domain reset a few words later.
 * OSIDES32 taps are static only (dynamic mode disables them, see
 * rtl/oscdr/README.md) and its D input must come straight from the IBUF.
 */
`default_nettype none
module csi_phy_gw5a #(
    parameter DLY0 = 0,
    parameter DLY1 = 21
) (
    input  wire        clk_ref,      // 50 MHz
    input  wire        rstn_ref,     // async, active low
    input  wire        i_clk_p, i_clk_n,
    input  wire        i_d0_p,  i_d0_n,
    input  wire        i_d1_p,  i_d1_n,
    output wire        o_pclk,
    output wire        o_reset,      // o_pclk domain, active high
    output wire        o_pll_lock,
    output wire [31:0] o_s_clk,
    output wire [31:0] o_s_d0,
    output wire [31:0] o_s_d1
);
    wire pll_lock;
    wire rxclk_500m_0 /* synthesis syn_keep=1 */;
    wire rxclk_500m_90, rxclk_500m_180, rxclk_500m_270;
    pll_rx_500m_4ph u_pll_rx (
        .lock(pll_lock), .clkout0(rxclk_500m_0), .clkout1(rxclk_500m_90),
        .clkout2(rxclk_500m_180), .clkout3(rxclk_500m_270), .clkin(clk_ref),
        .pssel(3'd0), .psdir(1'b0), .pspulse(1'b0));
    assign o_pll_lock = pll_lock;

    logic [3:0] delay_cnt;
    logic       resetn_div;
    logic       cen;     // DHCE CEN: 1 = clock stopped
    always_ff @(posedge clk_ref or negedge rstn_ref) begin
        if (!rstn_ref) begin
            delay_cnt  <= 4'd0;
            resetn_div <= 1'b0;
            cen        <= 1'b1;
        end else if (!pll_lock) begin
            delay_cnt  <= 4'd0;
            resetn_div <= 1'b0;
            cen        <= 1'b1;
        end else begin
            if (&delay_cnt) resetn_div <= 1'b1;
            else            delay_cnt  <= delay_cnt + 1'b1;
            if (delay_cnt >= 4'd7) cen <= 1'b0;
        end
    end
    wire fclkp, fclkqp, fclkn, fclkqn, pclk;
    DHCE u_dhce_0  (.CLKIN(rxclk_500m_0),   .CEN(cen), .CLKOUT(fclkp));
    DHCE u_dhce_90 (.CLKIN(rxclk_500m_90),  .CEN(cen), .CLKOUT(fclkqp));
    DHCE u_dhce_180(.CLKIN(rxclk_500m_180), .CEN(cen), .CLKOUT(fclkn));
    DHCE u_dhce_270(.CLKIN(rxclk_500m_270), .CEN(cen), .CLKOUT(fclkqn));
    CLKDIV #(.DIV_MODE("4")) u_clkdiv (.HCLKIN(fclkp), .RESETN(resetn_div), .CALIB(1'b0), .CLKOUT(pclk));
    assign o_pclk = pclk;

    logic [2:0] rst_sync;
    always_ff @(posedge pclk or negedge resetn_div) begin
        if (!resetn_div) rst_sync <= 3'b111;
        else             rst_sync <= {rst_sync[1:0], 1'b0};
    end
    wire reset = rst_sync[2];
    assign o_reset = reset;

    wire [2:0] se;
    TLVDS_IBUF u_ibuf_clk (.O(se[0]), .I(i_clk_p), .IB(i_clk_n));
    TLVDS_IBUF u_ibuf_d0  (.O(se[1]), .I(i_d0_p),  .IB(i_d0_n));
    TLVDS_IBUF u_ibuf_d1  (.O(se[2]), .I(i_d1_p),  .IB(i_d1_n));

    wire [31:0] q [0:2];
    generate
        for (genvar l = 0; l < 3; l++) begin : g_lane
            OSIDES32 #(
                .C_STATIC_DLY_0(DLY0), .DYN_DLY_EN_0("FALSE"), .ADAPT_EN_0("FALSE"),
                .C_STATIC_DLY_1(DLY1), .DYN_DLY_EN_1("FALSE"), .ADAPT_EN_1("FALSE")
            ) u_osides32 (
                .Q(q[l]), .DF0(), .DF1(), .D(se[l]), .PCLK(pclk),
                .FCLKP(fclkp), .FCLKQP(fclkqp), .FCLKN(fclkn), .FCLKQN(fclkqn), .RESET(reset),
                .SDTAP0(1'b0), .VALUE0(1'b0), .DLYSTEP0(8'd0),
                .SDTAP1(1'b0), .VALUE1(1'b0), .DLYSTEP1(8'd0));
        end
    endgenerate
    assign o_s_clk = q[0];
    assign o_s_d0  = q[1];
    assign o_s_d1  = q[2];
endmodule
`default_nettype wire
