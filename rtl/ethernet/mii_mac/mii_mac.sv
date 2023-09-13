`default_nettype none

module mii_mac (
    input wire tx_clock,
    input wire tx_reset,
    
    output wire [3:0] tx_mii_d,
    output wire       tx_mii_en,
    //output wire       tx_mii_er,

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
    
    input wire [3:0] rx_mii_d,
    input wire       rx_mii_dv,
    //input wire       rx_mii_er,

    output wire  [7:0] rx_maxis_tdata,
    output wire        rx_maxis_tvalid,
    output wire        rx_maxis_tuser,
    output wire        rx_maxis_tlast
);

mii_mac_tx mii_mac_tx_inst (
    .clock(tx_clock),
    .aresetn(!tx_reset),
    .mii_d(tx_mii_d),
    .mii_en(tx_mii_en),
    .mii_er(),
    .saxis_tdata(tx_saxis_tdata),
    .saxis_tvalid(tx_saxis_tvalid),
    .saxis_tready(tx_saxis_tready),
    .saxis_tlast(tx_saxis_tlast),
    .saxis_bypass_tdata(tx_saxis_bypass_tdata),
    .saxis_bypass_tvalid(tx_saxis_bypass_tvalid),
    .saxis_bypass_tready(tx_saxis_bypass_tready),
    .saxis_bypass_tlast(tx_saxis_bypass_tlast));

mii_mac_rx mii_mac_rx_inst (
    .clock(rx_clock),
    .aresetn(!rx_reset),
    .mii_d(rx_mii_d),
    .mii_dv(rx_mii_dv),
    .mii_er(0),
    .maxis_tdata(rx_maxis_tdata),
    .maxis_tvalid(rx_maxis_tvalid),
    .maxis_tuser(rx_maxis_tuser),
    .maxis_tlast(rx_maxis_tlast));

endmodule

`default_nettype wire
