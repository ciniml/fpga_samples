// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief NVMe-oF (NVMe/TCP) target on Tang Nano 9K + LAN8720 (RMII).
 *
 * Everything runs in the 50MHz RMII reference clock domain, same as
 * the verified ethernet_icmp design. The target answers ARP/ICMP at
 * 192.168.37.2 and serves NVMe/TCP on port 4420 (subsystem NQN
 * nqn.2026-09.org.fugafuga:nvme:veryl-sim); the namespace lives in
 * 32KiB of BRAM (64 blocks x 512B).
 */
`default_nettype none
module top(
    // Input button (reset)
    input wire button_s2,
    // Output LED (active low)
    output logic [5:0] led,

    // RMII PHY interface (LAN8720)
    input  wire        rmii_txclk,
    input  wire  [1:0] rmii_rxd,
    input  wire        rmii_crs_dv,
    output logic [1:0] rmii_txd,
    output logic       rmii_txen,
    input  wire        rmii_mdio,
    output logic       rmii_mdc
);
    localparam LBA_COUNT = 64;
    localparam MEM_ADDR_BITS = $clog2(LBA_COUNT) + 7;

    logic [2:0] reset_button = '1;
    always_ff @(posedge rmii_txclk) begin
        reset_button <= {1'b0, reset_button[2:1]};
    end

    // Power-on reset only: the base-board button polarity is not
    // relied upon (a wrong assumption would hold the design in reset).
    logic reset;
    reset_seq reset_seq_ext(
        .clock(rmii_txclk),
        .reset_in(reset_button[0]),
        .reset_out(reset)
    );

    assign rmii_mdc = 0;

    wire [7:0] rx_tdata;
    wire       rx_tvalid, rx_tuser, rx_tlast;
    wire [7:0] tx_tdata;
    wire       tx_tvalid, tx_tready, tx_tlast;

    rmii_mac mac (
        .tx_clock(rmii_txclk), .tx_reset(reset),
        .tx_rmii_d(rmii_txd), .tx_rmii_en(rmii_txen),
        .tx_saxis_tdata(tx_tdata), .tx_saxis_tvalid(tx_tvalid),
        .tx_saxis_tready(tx_tready), .tx_saxis_tlast(tx_tlast),
        .tx_saxis_bypass_tdata(8'h00), .tx_saxis_bypass_tvalid(1'b0),
        .tx_saxis_bypass_tready(), .tx_saxis_bypass_tlast(1'b0),
        .rx_clock(rmii_txclk), .rx_reset(reset),
        .rx_rmii_d(rmii_rxd), .rx_rmii_dv(rmii_crs_dv),
        .rx_maxis_tdata(rx_tdata), .rx_maxis_tvalid(rx_tvalid),
        .rx_maxis_tuser(rx_tuser), .rx_maxis_tlast(rx_tlast)
    );

    // ARP / ICMP responder (TX port 0 of the mux)
    wire [7:0] ip_txd;
    wire       ip_txv, ip_txr, ip_txl;
    EthIpStack ipstack (
        .i_clk(rmii_txclk), .i_rst(reset),
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
        .i_clk(rmii_txclk), .i_rst(reset),
        .i_rx_data(rx_tdata), .i_rx_valid(rx_tvalid),
        .i_rx_user(rx_tuser), .i_rx_last(rx_tlast),
        .o_tx_data(tcp_txd), .o_tx_valid(tcp_txv),
        .i_tx_ready(tcp_txr), .o_tx_last(tcp_txl),
        .o_conn_active(conn_active),
        .o_app_rx_valid(app_rxv), .i_app_rx_ready(app_rxr), .o_app_rx_data(app_rxd),
        .i_app_tx_valid(app_txv), .o_app_tx_ready(app_txr), .i_app_tx_data(app_txd)
    );

    EthTxMux txmux (
        .i_clk(rmii_txclk), .i_rst(reset),
        .i_s0_data(ip_txd), .i_s0_valid(ip_txv), .o_s0_ready(ip_txr), .i_s0_last(ip_txl),
        .i_s1_data(tcp_txd), .i_s1_valid(tcp_txv), .o_s1_ready(tcp_txr), .i_s1_last(tcp_txl),
        .o_m_data(tx_tdata), .o_m_valid(tx_tvalid), .i_m_ready(tx_tready), .o_m_last(tx_tlast)
    );

    // NVMe/TCP target + BRAM namespace
    wire [MEM_ADDR_BITS-1:0] mem_addr;
    wire        mem_wen, mem_ren;
    wire [31:0] mem_wdata;
    logic [31:0] mem_rdata;
    NvmeTcpTarget #(.LBA_COUNT(LBA_COUNT)) nvme (
        .i_clk(rmii_txclk), .i_rst(reset),
        .i_conn_active(conn_active),
        .i_rx_valid(app_rxv), .o_rx_ready(app_rxr), .i_rx_data(app_rxd),
        .o_tx_valid(app_txv), .i_tx_ready(app_txr), .o_tx_data(app_txd),
        .o_mem_addr(mem_addr), .o_mem_wen(mem_wen), .o_mem_wdata(mem_wdata),
        .o_mem_ren(mem_ren), .i_mem_rdata(mem_rdata)
    );

    logic [31:0] bmem [0:LBA_COUNT*128-1];
    always_ff @(posedge rmii_txclk) begin
        if (mem_wen) bmem[mem_addr] <= mem_wdata;
        if (mem_ren) mem_rdata <= bmem[mem_addr];
    end

    // DEBUG LEDs (active low) - ICResp path trace, sticky until reset:
    //  [5] heartbeat
    //  [4] engine->target byte handshake happened (RX delivery)
    //  [3] target produced a response byte (app TX valid seen)
    //  [2] engine accepted a response byte into the TX ring
    //  [1] TCP connection 0 established
    //  [0] engine reader presented a byte (RX FIFO -> target valid)
    // LEDs (active low):
    //  [5] heartbeat (clock alive)  [4] MAC RX frame  [3] TX frame
    //  [2:1] TCP connections        [0] raw CRS_DV activity at the pin
    logic [24:0] hb = 0;
    wire rx_act, tx_act, crs_act;
    logic [20:0] rx_hold = 0, tx_hold = 0, crs_hold = 0;
    always_ff @(posedge rmii_txclk) begin
        hb <= hb + 1;
        if (rx_tvalid && rx_tlast) rx_hold <= '1;
        else if (rx_hold != 0) rx_hold <= rx_hold - 1;
        if (tx_tvalid && tx_tready && tx_tlast) tx_hold <= '1;
        else if (tx_hold != 0) tx_hold <= tx_hold - 1;
        if (rmii_crs_dv) crs_hold <= '1;
        else if (crs_hold != 0) crs_hold <= crs_hold - 1;
    end
    assign rx_act = rx_hold != 0;
    assign tx_act = tx_hold != 0;
    assign crs_act = crs_hold != 0;
    assign led = ~{hb[24], rx_act, tx_act, conn_active, crs_act};

endmodule
`default_nettype wire
