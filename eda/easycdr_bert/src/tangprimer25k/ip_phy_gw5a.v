// Gowin EasyCDR IP wrapper with the same ports as oscdr_phy_gw5a (for A/B
// comparison: build with USE_EASYCDR_IP=1 in the environment).
module ip_phy_gw5a (
    input  wire        clk_in,
    input  wire        rstn_in,
    input  wire        i_serial_p,
    input  wire        i_serial_n,
    output wire        o_pclk,
    output wire        o_reset,
    output wire        o_pll_lock,
    output wire [15:0] o_dout,
    output wire        o_dout_en
);
    wire pll_lock;
    wire rxclk_500m_0 /* synthesis syn_keep=1 */;
    wire rxclk_500m_90, rxclk_500m_180, rxclk_500m_270;
    pll_rx_500m_4ph u_pll_rx(
        .lock(pll_lock), .clkout0(rxclk_500m_0), .clkout1(rxclk_500m_90),
        .clkout2(rxclk_500m_180), .clkout3(rxclk_500m_270), .clkin(clk_in),
        .pssel(3'd0), .psdir(1'b0), .pspulse(1'b0));
    assign o_pll_lock = pll_lock;
    EasyCDR_Top u_EasyCDR_Top(
        .rxp_i(i_serial_p), .rxn_i(i_serial_n), .rstn_i(rstn_in),
        .pll_clkin_i(clk_in),
        .pll_clkout0_i(rxclk_500m_0), .pll_clkout1_i(rxclk_500m_90),
        .pll_clkout2_i(rxclk_500m_180), .pll_clkout3_i(rxclk_500m_270),
        .pll_lock_i(pll_lock),
        .share_clk0_o(), .share_clk1_o(), .share_clk2_o(), .share_clk3_o(),
        .share_clk4_o(o_pclk), .share_reset_o(o_reset),
        .dout_o(o_dout), .dout_en_o(o_dout_en));
endmodule
