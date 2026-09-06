// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Full NVMe-oF-over-Ethernet top: RMII MAC + ARP/ICMP + TCP engine +
// NVMe/TCP target + backing RAM, RMII pins at the boundary. Pin
// compatible with eth_sim_top so the same TAP bridge drives it; this
// is the structure that goes on the Tang Nano 9K + LAN8720.
`default_nettype none
module eth_nvme_top #(
    parameter LBA_COUNT = 2048
) (
    input  wire       clk,   // 50MHz RMII reference
    input  wire       rst,
    input  wire [1:0] rmii_rxd,
    input  wire       rmii_crs_dv,
    output wire [1:0] rmii_txd,
    output wire       rmii_tx_en,
    output logic [7:0] dbg_rx_frames = 0,
    output logic [7:0] dbg_rx_errs = 0,
    output logic [7:0] dbg_tx_frames = 0,
    output logic [15:0] dbg_app_rx = 0, // bytes TCP -> NVMe target
    output logic [15:0] dbg_app_tx = 0, // bytes NVMe target -> TCP
    output wire  [1:0]  dbg_conn
);
    localparam MEM_ADDR_BITS = $clog2(LBA_COUNT) + 7;

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

    // ARP / ICMP responder (TX port 0 of the mux)
    wire [7:0] ip_txd;
    wire       ip_txv, ip_txr, ip_txl;
    EthIpStack ipstack (
        .i_clk(clk), .i_rst(rst),
        .i_rx_data(rx_tdata), .i_rx_valid(rx_tvalid),
        .i_rx_user(rx_tuser), .i_rx_last(rx_tlast),
        .o_tx_data(ip_txd), .o_tx_valid(ip_txv),
        .i_tx_ready(ip_txr), .o_tx_last(ip_txl)
    );

    // TCP engine (TX port 1)
    wire [7:0]  tcp_txd;
    wire        tcp_txv, tcp_txr, tcp_txl;
    wire [1:0]  conn_active;
    wire [1:0]  app_rxv, app_rxr;
    wire [15:0] app_rxd;
    wire [1:0]  app_txv, app_txr;
    wire [15:0] app_txd;
    TcpEngine tcp (
        .i_clk(clk), .i_rst(rst),
        .i_rx_data(rx_tdata), .i_rx_valid(rx_tvalid),
        .i_rx_user(rx_tuser), .i_rx_last(rx_tlast),
        .o_tx_data(tcp_txd), .o_tx_valid(tcp_txv),
        .i_tx_ready(tcp_txr), .o_tx_last(tcp_txl),
        .o_conn_active(conn_active),
        .o_app_rx_valid(app_rxv), .i_app_rx_ready(app_rxr), .o_app_rx_data(app_rxd),
        .i_app_tx_valid(app_txv), .o_app_tx_ready(app_txr), .i_app_tx_data(app_txd)
    );

    EthTxMux txmux (
        .i_clk(clk), .i_rst(rst),
        .i_s0_data(ip_txd), .i_s0_valid(ip_txv), .o_s0_ready(ip_txr), .i_s0_last(ip_txl),
        .i_s1_data(tcp_txd), .i_s1_valid(tcp_txv), .o_s1_ready(tcp_txr), .i_s1_last(tcp_txl),
        .o_m_data(tx_tdata), .o_m_valid(tx_tvalid), .i_m_ready(tx_tready), .o_m_last(tx_tlast)
    );

    // NVMe/TCP target + backing RAM
    wire [MEM_ADDR_BITS-1:0] mem_addr;
    wire        mem_wen, mem_ren;
    wire [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    NvmeTcpTarget #(.LBA_COUNT(LBA_COUNT)) nvme (
        .i_clk(clk), .i_rst(rst),
        .i_conn_active(conn_active),
        .i_rx_valid(app_rxv), .o_rx_ready(app_rxr), .i_rx_data(app_rxd),
        .o_tx_valid(app_txv), .i_tx_ready(app_txr), .o_tx_data(app_txd),
        .o_mem_addr(mem_addr), .o_mem_wen(mem_wen), .o_mem_wdata(mem_wdata),
        .o_mem_ren(mem_ren), .i_mem_rdata(mem_rdata), .i_mem_ready(1'b1)
    );

    logic [31:0] bmem [0:LBA_COUNT*128-1];
    always @(posedge clk) begin
        if (mem_wen) bmem[mem_addr] <= mem_wdata;
        if (mem_ren) mem_rdata <= bmem[mem_addr];
    end

    assign dbg_conn = conn_active;
    always @(posedge clk) begin
        if (app_rxv[0] && app_rxr[0]) dbg_app_rx <= dbg_app_rx + 1;
        else if (app_rxv[1] && app_rxr[1]) dbg_app_rx <= dbg_app_rx + 1;
        if (app_txv[0] && app_txr[0]) dbg_app_tx <= dbg_app_tx + 1;
        else if (app_txv[1] && app_txr[1]) dbg_app_tx <= dbg_app_tx + 1;
    end
    always @(posedge clk) begin
        if (rx_tvalid && rx_tlast) begin
            dbg_rx_frames <= dbg_rx_frames + 1;
            if (rx_tuser) dbg_rx_errs <= dbg_rx_errs + 1;
        end
        if (tx_tvalid && tx_tready && tx_tlast) dbg_tx_frames <= dbg_tx_frames + 1;
    end

endmodule
`default_nettype wire
