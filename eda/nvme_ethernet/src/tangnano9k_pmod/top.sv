// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief NVMe-oF (NVMe/TCP) target on Tang Nano 9K + LAN8720 (RMII).
 *
 * The network / NVMe logic runs in the 50MHz RMII reference clock
 * domain, same as the verified ethernet_icmp design. The target answers
 * ARP/ICMP at 192.168.37.2 and serves NVMe/TCP on port 4420 (subsystem
 * NQN nqn.2026-09.org.fugafuga:nvme:veryl-sim).
 *
 * The namespace is the on-package PSRAM die 0 (4MiB = 8192 blocks x
 * 512B) behind a one-line write-back cache (PsramDwordCache); the
 * GowinPsram controller runs at 54MHz from the 27MHz crystal (rPLL,
 * CLKOUTP +90 degrees for CK). The O_psram_* / IO_psram_* ports are
 * the "magic" names the Gowin tools map onto the internal PSRAM.
 */
`default_nettype none
module top(
    // 27MHz crystal (PSRAM clock source)
    input wire clock,
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
    output logic       rmii_mdc,

    // debug UART (board USB serial, 115200)
    output wire uart_tx,

    // on-package PSRAM (HyperRAM, 2 dies)
    output wire  [1:0]  O_psram_ck,
    output wire  [1:0]  O_psram_ck_n,
    inout  wire  [15:0] IO_psram_dq,
    inout  wire  [1:0]  IO_psram_rwds,
    output wire  [1:0]  O_psram_cs_n,
    output wire  [1:0]  O_psram_reset_n
);
    localparam LBA_COUNT = 8192;                     // 4MiB / 512B
    localparam MEM_ADDR_BITS = $clog2(LBA_COUNT) + 7; // 20: dword address
    localparam PSRAM_HZ = 54_000_000;  // lowered from 81MHz for PSRAM read-capture margin

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

    // NVMe/TCP target; the namespace memory is the PSRAM cache below
    wire [MEM_ADDR_BITS-1:0] mem_addr;
    wire        mem_wen, mem_ren, mem_ready;
    wire [31:0] mem_wdata, mem_rdata;
    NvmeTcpTarget #(.LBA_COUNT(LBA_COUNT)) nvme (
        .i_clk(rmii_txclk), .i_rst(reset),
        .i_conn_active(conn_active),
        .i_rx_valid(app_rxv), .o_rx_ready(app_rxr), .i_rx_data(app_rxd),
        .o_tx_valid(app_txv), .i_tx_ready(app_txr), .o_tx_data(app_txd),
        .o_mem_addr(mem_addr), .o_mem_wen(mem_wen), .o_mem_wdata(mem_wdata),
        .o_mem_ren(mem_ren), .i_mem_rdata(mem_rdata), .i_mem_ready(mem_ready)
    );

    // ---- PSRAM clock domain: 81MHz + 90 degree copy for CK ----
    logic pclk, pclk_p, pll_lock;
    gowin_rpll_psram pll (
        .clkin(clock), .clkout(pclk), .clkoutp(pclk_p), .lock(pll_lock)
    );
    logic preset;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_psram (
        .clock(pclk), .reset_in(!pll_lock), .reset_out(preset)
    );

    wire        ps_ready;
    wire        ps_cmd_valid, ps_cmd_ready, ps_cmd_write;
    wire [21:0] ps_cmd_addr;
    wire [5:0]  ps_cmd_len;
    wire        ps_wr_valid, ps_wr_ready;
    wire [15:0] ps_wr_data;
    wire [1:0]  ps_wr_mask;
    wire        ps_rd_valid, ps_rd_last;
    wire [15:0] ps_rd_data;

    PsramDwordCache #(.ADDR_BITS(MEM_ADDR_BITS)) cache (
        .i_clk(rmii_txclk), .i_rst(reset),
        .i_addr(mem_addr), .i_wen(mem_wen), .i_wdata(mem_wdata), .i_ren(mem_ren),
        .o_rdata(mem_rdata), .o_ready(mem_ready), .o_dbg(),
        .i_pclk(pclk), .i_prst(preset), .i_pready(ps_ready),
        .o_cmd_valid(ps_cmd_valid), .i_cmd_ready(ps_cmd_ready), .o_cmd_write(ps_cmd_write),
        .o_cmd_addr(ps_cmd_addr), .o_cmd_len(ps_cmd_len),
        .o_wr_valid(ps_wr_valid), .i_wr_ready(ps_wr_ready), .o_wr_data(ps_wr_data), .o_wr_mask(ps_wr_mask),
        .i_rd_valid(ps_rd_valid), .i_rd_data(ps_rd_data), .i_rd_last(ps_rd_last)
    );

    // die 0 only; die 1 is held idle
    GowinPsram #(.CLK_HZ(PSRAM_HZ), .LATENCY(3)) psram (
        .i_clk(pclk), .i_clk_p(pclk_p), .i_rst(preset), .o_ready(ps_ready),
        .i_cmd_valid(ps_cmd_valid), .o_cmd_ready(ps_cmd_ready),
        .i_cmd_write(ps_cmd_write), .i_cmd_reg(1'b0),
        .i_cmd_addr(ps_cmd_addr), .i_cmd_len(ps_cmd_len),
        .i_wr_valid(ps_wr_valid), .o_wr_ready(ps_wr_ready),
        .i_wr_data(ps_wr_data), .i_wr_mask(ps_wr_mask),
        .o_rd_valid(ps_rd_valid), .o_rd_data(ps_rd_data), .o_rd_last(ps_rd_last),
        .o_psram_ck(O_psram_ck[0]), .o_psram_cs_n(O_psram_cs_n[0]),
        .o_psram_reset_n(O_psram_reset_n[0]),
        .io_psram_dq(IO_psram_dq[7:0]), .io_psram_rwds(IO_psram_rwds[0])
    );
    assign O_psram_ck[1]      = 1'b0;
    assign O_psram_ck_n       = 2'b00;
    assign O_psram_cs_n[1]    = 1'b1;
    assign O_psram_reset_n[1] = O_psram_reset_n[0];
    assign IO_psram_dq[15:8]  = 8'bz;
    assign IO_psram_rwds[1]   = 1'bz;

    assign uart_tx = 1'b1;   // debug UART removed with the throughput experiments

    // DEBUG LEDs (active low) - ICResp path trace, sticky until reset:
    //  [5] heartbeat
    //  [4] engine->target byte handshake happened (RX delivery)
    //  [3] target produced a response byte (app TX valid seen)
    //  [2] engine accepted a response byte into the TX ring
    //  [1] TCP connection 0 established
    //  [0] engine reader presented a byte (RX FIFO -> target valid)
    // LEDs (active low):
    //  [5] heartbeat (clock alive)  [4] MAC RX frame  [3] TX frame
    //  [2:1] TCP connections        [0] PSRAM controller initialized
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
    assign led = ~{hb[24], rx_act, tx_act, conn_active, ps_ready};

endmodule
`default_nettype wire
