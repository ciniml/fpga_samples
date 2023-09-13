`default_nettype none

module rmii_mac (
    input wire tx_clock,
    input wire tx_reset,
    
    output wire [1:0] tx_rmii_d,
    output wire       tx_rmii_en,

    input  wire [7:0] tx_saxis_tdata,
    input  wire       tx_saxis_tvalid,
    output wire       tx_saxis_tready,
    input  wire       tx_saxis_tlast,

    // Ethernet bypass input
    input  wire [7:0] tx_saxis_bypass_tdata,
    input  wire       tx_saxis_bypass_tvalid,
    output wire       tx_saxis_bypass_tready,
    input  wire       tx_saxis_bypass_tlast,

    input wire rx_clock,
    input wire rx_reset,
    
    input wire [1:0] rx_rmii_d,
    input wire       rx_rmii_dv,

    output wire  [7:0] rx_maxis_tdata,
    output wire        rx_maxis_tvalid,
    output wire        rx_maxis_tuser,
    output wire        rx_maxis_tlast
);

mii_mac_tx #(
    .USE_RMII(1)
) mii_mac_tx_inst (
    .clock(tx_clock),
    .aresetn(!tx_reset),
    .mii_d(tx_rmii_d),
    .mii_en(tx_rmii_en),
    .mii_er(),
    .saxis_tdata(tx_saxis_tdata),
    .saxis_tvalid(tx_saxis_tvalid),
    .saxis_tready(tx_saxis_tready),
    .saxis_tlast(tx_saxis_tlast),
    .saxis_bypass_tdata(tx_saxis_bypass_tdata),
    .saxis_bypass_tvalid(tx_saxis_bypass_tvalid),
    .saxis_bypass_tready(tx_saxis_bypass_tready),
    .saxis_bypass_tlast(tx_saxis_bypass_tlast));

mii_mac_rx  #(
    .USE_RMII(1)
) mii_mac_rx_inst (
    .clock(rx_clock),
    .aresetn(!rx_reset),
    .mii_d(rx_rmii_d),
    .mii_dv(rx_rmii_dv),
    .mii_er(0),
    .maxis_tdata(rx_maxis_tdata),
    .maxis_tvalid(rx_maxis_tvalid),
    .maxis_tuser(rx_maxis_tuser),
    .maxis_tlast(rx_maxis_tlast));

endmodule

`default_nettype wire
