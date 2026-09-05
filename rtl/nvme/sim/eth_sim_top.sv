// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Simulation top: the verified rtl/ethernet RMII MAC + EthIpStack,
// single 50MHz clock domain, RMII pins at the boundary - the same
// structure that goes on the Tang Nano 9K + LAN8720.
`default_nettype none
module eth_sim_top (
    input  wire       clk,   // 50MHz RMII reference
    input  wire       rst,
    input  wire [1:0] rmii_rxd,
    input  wire       rmii_crs_dv,
    output wire [1:0] rmii_txd,
    output wire       rmii_tx_en,
    // debug counters (simulation only)
    output logic [7:0] dbg_rx_frames = 0, // MAC RX frames delivered (tlast)
    output logic [7:0] dbg_rx_errs = 0,   // ... of which tuser was set
    output logic [7:0] dbg_tx_frames = 0  // frames the stack sent (tlast)
);

    wire [7:0] rx_tdata;
    wire       rx_tvalid, rx_tuser, rx_tlast;
    wire [7:0] tx_tdata;
    wire       tx_tvalid, tx_tready, tx_tlast;

    rmii_mac mac (
        .tx_clock(clk), .tx_reset(rst),
        .tx_rmii_d(rmii_txd), .tx_rmii_en(rmii_tx_en),
        .tx_saxis_tdata(tx_tdata), .tx_saxis_tvalid(tx_tvalid),
        .tx_saxis_tready(tx_tready), .tx_saxis_tlast(tx_tlast),
        .tx_saxis_bypass_tdata(8'h00), .tx_saxis_bypass_tvalid(1'b0),
        .tx_saxis_bypass_tready(), .tx_saxis_bypass_tlast(1'b0),
        .rx_clock(clk), .rx_reset(rst),
        .rx_rmii_d(rmii_rxd), .rx_rmii_dv(rmii_crs_dv),
        .rx_maxis_tdata(rx_tdata), .rx_maxis_tvalid(rx_tvalid),
        .rx_maxis_tuser(rx_tuser), .rx_maxis_tlast(rx_tlast)
    );

    always @(posedge clk) begin
        if (rx_tvalid && rx_tlast) begin
            dbg_rx_frames <= dbg_rx_frames + 1;
            if (rx_tuser) dbg_rx_errs <= dbg_rx_errs + 1;
        end
        if (tx_tvalid && tx_tready && tx_tlast) dbg_tx_frames <= dbg_tx_frames + 1;
    end

    EthIpStack stack (
        .i_clk(clk), .i_rst(rst),
        .i_rx_data(rx_tdata), .i_rx_valid(rx_tvalid),
        .i_rx_user(rx_tuser), .i_rx_last(rx_tlast),
        .o_tx_data(tx_tdata), .o_tx_valid(tx_tvalid),
        .i_tx_ready(tx_tready), .o_tx_last(tx_tlast)
    );

endmodule
`default_nettype wire
