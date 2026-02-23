`default_nettype none

module xg_mac (
    input wire tx_clock,
    input wire tx_reset,
    
    output wire [63:0] tx_xgmii_d,
    output wire  [7:0] tx_xgmii_c,

    input  wire [63:0] tx_saxis_tdata,
    input  wire        tx_saxis_tvalid,
    output wire        tx_saxis_tready,
    input  wire  [7:0] tx_saxis_tkeep,
    input  wire        tx_saxis_tuser,
    input  wire        tx_saxis_tlast,

    input wire rx_clock,
    input wire rx_reset,
    
    input wire [63:0]  rx_xgmii_d,
    input wire [7:0]   rx_xgmii_c,

    output wire  [63:0] rx_maxis_tdata,
    output wire         rx_maxis_tvalid,
    output wire  [7:0]  rx_maxis_tkeep,
    output wire         rx_maxis_tuser,
    output wire         rx_maxis_tlast
);

xg_mac_tx xg_mac_tx_inst (
    .clock(tx_clock),
    .aresetn(!tx_reset),
    .xgmii_d(tx_xgmii_d),
    .xgmii_c(tx_xgmii_c),
    .saxis_tdata(tx_saxis_tdata),
    .saxis_tvalid(tx_saxis_tvalid),
    .saxis_tready(tx_saxis_tready),
    .saxis_tkeep(tx_saxis_tkeep),
    .saxis_tuser(tx_saxis_tuser),
    .saxis_tlast(tx_saxis_tlast));

xg_mac_rx xg_mac_rx_inst (
    .clock(rx_clock),
    .aresetn(!rx_reset),
    .xgmii_d(rx_xgmii_d),
    .xgmii_c(rx_xgmii_c),
    .maxis_tdata(rx_maxis_tdata),
    .maxis_tvalid(rx_maxis_tvalid),
    .maxis_tkeep(rx_maxis_tkeep),
    .maxis_tuser(rx_maxis_tuser),
    .maxis_tlast(rx_maxis_tlast));

endmodule

`default_nettype wire
