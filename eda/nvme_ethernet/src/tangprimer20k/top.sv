// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief NVMe-oF (NVMe/TCP) target on Tang Primer 20K + LAN8720 (RMII).
 *
 * Same stack as the Tang Nano 9K targets, everything in the 50MHz RMII
 * reference clock domain. The GW2A-18 has room for the larger TCP
 * buffers the 9K could not hold (TX ring 16KiB / RX FIFO 8KiB per
 * connection), which is what this target exists to measure. The
 * namespace is the SOM's 128MiB DDR3 (H5TQ1G63EFR, x16) through a 512-byte
 * write-back line cache (LineDwordCache) and the Veryl DDR3 controller +
 * GW2A IOLOGIC PHY from riscv-veryl (rtl/ddr3). The last 512B block is
 * left out of the namespace: the controller's read calibration scratches
 * the last 16 bytes of the device.
 *
 * PHY wiring is selected by the constraint file (see Makefile PINS_CST):
 *  - pins.cst        LAN8720 module wired directly (ethernet_icmp layout)
 *  - pins_pmod2.cst  Pmod Ethernet adapter on PMOD2
 * The PHY (RTL8201 on the dock) is reset and configured over MDIO from
 * the 27MHz crystal domain (rtl8201_init.sv); the CRS/CRS_DV pin must be
 * switched to CRS_DV or the MAC never sees a valid frame.
 */
`default_nettype none
module top(
    input wire clock,          // 27MHz crystal (PHY reset sequencing only)
    input wire button_s2,      // reset (active low)
    output logic [5:0] led,

    // RMII PHY interface (LAN8720)
    input  wire        rmii_txclk,
    input  wire  [1:0] rmii_rxd,
    input  wire        rmii_crs_dv,
    output logic [1:0] rmii_txd,
    output logic       rmii_txen,
    inout  wire        rmii_mdio,
    output logic       rmii_mdc,
    output logic       rmii_rstn,

    // DDR3 (SOM)
    output logic        ddr_ck,     // SSTL15D pair, P side
    output logic        ddr_cke,
    output logic        ddr_odt,
    output logic        ddr_reset_n,
    output logic        ddr_cs_n,
    output logic        ddr_ras_n,
    output logic        ddr_cas_n,
    output logic        ddr_we_n,
    output logic [2:0]  ddr_ba,
    output logic [13:0] ddr_a,
    output logic [1:0]  ddr_dm,
    inout  wire  [15:0] ddr_dq,
    inout  wire  [1:0]  ddr_dqs     // SSTL15D pairs, P side
);
    localparam LBA_COUNT     = 262143;              // 128MiB DDR3 minus the calibration scratch block
    localparam MEM_ADDR_BITS = $clog2(LBA_COUNT) + 7;
    localparam TX_RING_BYTES = 16384;
    localparam RX_FIFO_BYTES = 8192;

    // ---- PHY reset + MDIO bring-up on the crystal clock ----
    // (the dock's RTL8201 needs its CRS pin switched to CRS_DV over MDIO;
    //  nothing here depends on rmii_txclk, which stops while the PHY resets)
    logic phy_ready;
    rtl8201_init #(.CLK_HZ(27_000_000)) phy_init (
        .clk(clock), .phy_rstn(rmii_rstn), .mdc(rmii_mdc), .mdio(rmii_mdio),
        .done(phy_ready)
    );

    // ---- logic reset: power-on only, in the RMII clock domain ----
    // (the dock button's idle polarity is not relied upon: a wrong guess
    // would hold the design in reset; button_s2 is left unused)
    logic [2:0] reset_button = '1;
    always_ff @(posedge rmii_txclk) begin
        reset_button <= {1'b0, reset_button[2:1]};
    end
    logic reset;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_ext (
        .clock(rmii_txclk), .reset_in(reset_button[0]), .reset_out(reset)
    );

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
    TcpEngine #(.TX_RING_BYTES(TX_RING_BYTES), .RX_FIFO_BYTES(RX_FIFO_BYTES)) tcp (
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

    // ---- DDR3 clocks: rPLL 27MHz x 11 = 297MHz fclk, CLKDIV /4 = 74.25MHz pclk ----
    logic fclk, pclk, pll_lock;
    rPLL #(
        .FCLKIN          ("27"),
        .DYN_IDIV_SEL    ("false"),
        .IDIV_SEL        (0),        // /1
        .DYN_FBDIV_SEL   ("false"),
        .FBDIV_SEL       (10),       // x11
        .DYN_ODIV_SEL    ("false"),
        .ODIV_SEL        (2),        // VCO 594 MHz
        .PSDA_SEL        ("0000"),
        .DYN_DA_EN       ("false"),
        .DUTYDA_SEL      ("1000"),
        .CLKOUT_FT_DIR   (1'b1),
        .CLKOUTP_FT_DIR  (1'b1),
        .CLKOUT_DLY_STEP (0),
        .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL       ("internal"),
        .CLKOUT_BYPASS   ("false"),
        .CLKOUTP_BYPASS  ("false"),
        .CLKOUTD_BYPASS  ("false"),
        .DYN_SDIV_SEL    (2),
        .CLKOUTD_SRC     ("CLKOUT"),
        .CLKOUTD3_SRC    ("CLKOUT"),
        .DEVICE          ("GW2A-18C")
    ) u_rpll (
        .CLKOUT  (fclk),
        .LOCK    (pll_lock),
        .CLKOUTP (),
        .CLKOUTD (),
        .CLKOUTD3(),
        .RESET   (1'b0),
        .RESET_P (1'b0),
        .CLKIN   (clock),
        .CLKFB   (1'b0),
        .FBDSEL  (6'b0),
        .IDSEL   (6'b0),
        .ODSEL   (6'b0),
        .PSDA    (4'b0),
        .DUTYDA  (4'b0),
        .FDLY    (4'b0)
    );
    CLKDIV #(.DIV_MODE("4"), .GSREN("false")) u_clkdiv (
        .CLKOUT(pclk), .HCLKIN(fclk), .RESETN(pll_lock), .CALIB(1'b0)
    );

    // DDR3-side reset (pclk domain): held until the PLL locks
    logic [2:0] rst_mem_q = '1;
    always_ff @(posedge pclk) begin
        rst_mem_q <= {(reset || !pll_lock), rst_mem_q[2:1]};
    end
    logic reset_mem;
    reset_seq #(.RESET_DELAY_CYCLES(32)) u_reset_seq_mem (
        .clock(pclk), .reset_in(rst_mem_q[0]), .reset_out(reset_mem)
    );

    // ---- DDR3 controller (CPU side = RMII clock) + PHY ----
    LineBusIf mline();
    BusIf     ctl_bus();
    assign ctl_bus.valid = 1'b0;
    assign ctl_bus.addr  = 32'b0;
    assign ctl_bus.we    = 1'b0;
    assign ctl_bus.wstrb = 4'b0;
    assign ctl_bus.wdata = 32'b0;

    logic         phy_reset_n, phy_cke, phy_odt, phy_cs_n, phy_ras_n, phy_cas_n, phy_we_n;
    logic [2:0]   phy_ba;
    logic [13:0]  phy_a;
    logic [127:0] phy_dq_out, phy_dq_in;
    logic [3:0]   phy_dq_oe, phy_dqs_oe;
    logic [15:0]  phy_dm_out, phy_dqs_out, phy_dqs_in;
    logic         ddr3_init_done;

    Ddr3Ctrl #(
        .PCLK_PS       (13468),  // 74.25 MHz
        .RD_SEL_DEFAULT(44),     // board-measured fallbacks (riscv-veryl cpu_riscv_ddr3)
        .RD_LAT_DEFAULT(12),
        .RECAL_ENABLE  (1)
    ) ddr3 (
        .i_clk_cpu(rmii_txclk), .i_rst_cpu(reset),
        .i_clk_mem(pclk),       .i_rst_mem(reset_mem),
        .bus(mline), .ctl(ctl_bus),
        .o_reset_n(phy_reset_n), .o_cke(phy_cke), .o_odt(phy_odt),
        .o_cs_n(phy_cs_n), .o_ras_n(phy_ras_n), .o_cas_n(phy_cas_n), .o_we_n(phy_we_n),
        .o_ba(phy_ba), .o_a(phy_a),
        .o_dq_out(phy_dq_out), .o_dq_oe(phy_dq_oe), .o_dm_out(phy_dm_out),
        .o_dqs_out(phy_dqs_out), .o_dqs_oe(phy_dqs_oe),
        .i_dq_in(phy_dq_in), .i_dqs_in(phy_dqs_in),
        .o_init_done(ddr3_init_done)
    );

    Ddr3PhyGw2a u_phy (
        .i_pclk(pclk), .i_fclk(fclk), .i_rst(reset_mem),
        .i_reset_n(phy_reset_n), .i_cke(phy_cke), .i_odt(phy_odt),
        .i_cs_n(phy_cs_n), .i_ras_n(phy_ras_n), .i_cas_n(phy_cas_n), .i_we_n(phy_we_n),
        .i_ba(phy_ba), .i_a(phy_a),
        .i_dq_out(phy_dq_out), .i_dq_oe(phy_dq_oe), .i_dm_out(phy_dm_out),
        .i_dqs_out(phy_dqs_out), .i_dqs_oe(phy_dqs_oe),
        .o_dq_in(phy_dq_in), .o_dqs_in(phy_dqs_in),
        .o_ddr_ck(ddr_ck), .o_ddr_cke(ddr_cke), .o_ddr_odt(ddr_odt), .o_ddr_reset_n(ddr_reset_n),
        .o_ddr_cs_n(ddr_cs_n), .o_ddr_ras_n(ddr_ras_n), .o_ddr_cas_n(ddr_cas_n), .o_ddr_we_n(ddr_we_n),
        .o_ddr_ba(ddr_ba), .o_ddr_a(ddr_a), .o_ddr_dm(ddr_dm),
        .io_ddr_dq(ddr_dq), .io_ddr_dqs(ddr_dqs)
    );

    // NVMe/TCP target + DDR3 namespace behind a 512-byte line cache
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

    LineDwordCache #(.ADDR_BITS(MEM_ADDR_BITS), .LINE_BYTES(512)) cache (
        .i_clk(rmii_txclk), .i_rst(reset),
        .i_addr(mem_addr), .i_wen(mem_wen), .i_wdata(mem_wdata), .i_ren(mem_ren),
        .o_rdata(mem_rdata), .o_ready(mem_ready), .o_dbg(),
        .line(mline)
    );

    // LEDs (active low):
    //  [5] heartbeat  [4] MAC RX frame  [3] TX frame
    //  [2:1] TCP connections (I/O, admin)  [0] PHY initialised and DDR3 init done
    logic [24:0] hb = 0;
    logic [20:0] rx_hold = 0, tx_hold = 0;
    always_ff @(posedge rmii_txclk) begin
        hb <= hb + 1;
        if (rx_tvalid && rx_tlast) rx_hold <= '1;
        else if (rx_hold != 0) rx_hold <= rx_hold - 1;
        if (tx_tvalid && tx_tready && tx_tlast) tx_hold <= '1;
        else if (tx_hold != 0) tx_hold <= tx_hold - 1;
    end
    assign led = ~{hb[24], rx_hold != 0, tx_hold != 0, conn_active, phy_ready && ddr3_init_done};

endmodule
`default_nettype wire
