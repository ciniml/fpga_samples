// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Tang Primer 25K (Dock J3) on the FPGA cartridge adapter gb_fpga_cart_de0 as a game cartridge
// (rtl/chromatic/game_cart.veryl): ROM bank 0 and the cartridge RAM in block RAM, the switchable
// ROM bank read from the core board's SPI flash (SPI-Quad continuous reads, rtl/chromatic/qspi_rom.veryl, image at
// 4 MiB). Loaded and read by util/cart_emu (game subcommands) over the Dock's USB-UART (FT2232
// interface B, 1 Mbaud 8N1) or over USB 2.0 HS on a Pmod USB HS Single (slot USB_PMOD, default
// pmod1; EP1 bulk OUT / IN carry the same byte stream as the UART). Replies go to the link the
// last command byte came from. Adapter pins as eda/cart_target.
//
//   50 MHz -> PLLA -> 100 MHz (GameCart, UART) / 200 MHz (QspiRom, SCLK 100 MHz)
//   50 MHz -> pll_usb 60 MHz -> pll_hs960 960 / 480 MHz -> usb_phy_gowin_sl: clk60 (UsbDevice)
//   clk60 <-> 100 MHz: ByteAfifo each way
module top (
    input  wire        clk_in,
    input  wire        uart_rxd,
    output wire        uart_txd,

    input  wire        CART_RST_N,
    output wire        AUD_PWM,
    input  wire        CART_CLK,
    output wire        RST_DRV,
    input  wire        CART_WR_N,
    input  wire        CART_RD_N,
    input  wire        CART_CS_N,
    output wire        D_DIR,
    output wire        D_OE_N,
    inout  wire [7:0]  CART_D,
    input  wire [15:0] CART_A,

    output wire        FL_CS_N,
    output wire        FL_SCLK,
    inout  wire [3:0]  FL_IO,

    inout  wire        usb_dp,        // Pmod pin 1 (DX_P; the IOBUF's P side, constrained to both balls)
    inout  wire        usb_dn,        // pin 7 (DX_N)
    input  wire        usb_cmp_dp,    // pin 2 (D+ comparator)
    input  wire        usb_cmp_dp_n,  // pin 8 (VREF)
    inout  wire        usb_term_dp,   // pin 3
    inout  wire        usb_term_dn,   // pin 9
    output wire        usb_pullup,    // pin 4
    input  wire        vbus_det       // pin 10
);
    wire clk, clk2, lock;
    pll_100m_200m_50 u_pll (.lock(lock), .clkout0(clk), .clkout1(clk2), .clkin(clk_in), .reset(1'b0));
    logic [3:0] rst_sr = 4'hF;
    always_ff @(posedge clk) rst_sr <= {rst_sr[2:0], ~lock};
    wire rst = rst_sr[3];
    logic [3:0] rst2_sr = 4'hF;
    always_ff @(posedge clk2) rst2_sr <= {rst2_sr[2:0], ~lock};
    wire rst2 = rst2_sr[3];

    //------------------------------------------------------------------
    // command links: UART and USB EP1, replies to the link of the last received byte
    //------------------------------------------------------------------
    wire       rx_valid, rx_ready, tx_valid, tx_ready;
    wire [7:0] rx_data, tx_data;
    wire       u_rx_valid, u_rx_ready, u_tx_valid, u_tx_ready;
    wire [7:0] u_rx_data, u_tx_data;
    uart_rx #(.BAUD_DIVIDER(100)) u_rx (
        .clock(clk), .reset(rst), .data_valid(u_rx_valid), .data_ready(u_rx_ready), .data_bits(u_rx_data), .rx(uart_rxd));
    uart_tx #(.BAUD_DIVIDER(100)) u_tx (
        .clock(clk), .reset(rst), .data_valid(u_tx_valid), .data_ready(u_tx_ready), .data_bits(u_tx_data), .tx(uart_txd));

    wire       b_rx_valid, b_rx_ready, b_tx_valid, b_tx_ready;   // USB side, 100 MHz end of the FIFOs
    wire [7:0] b_rx_data;
    logic      sel_usb = 1'b0;
    always_ff @(posedge clk)
        if (rst) sel_usb <= 1'b0;
        else if (rx_ready && b_rx_valid) sel_usb <= 1'b1;
        else if (rx_ready && u_rx_valid) sel_usb <= 1'b0;
    assign rx_valid   = b_rx_valid | u_rx_valid;
    assign rx_data    = b_rx_valid ? b_rx_data : u_rx_data;
    assign b_rx_ready = rx_ready;
    assign u_rx_ready = rx_ready & ~b_rx_valid;
    assign u_tx_valid = tx_valid & ~sel_usb;
    assign u_tx_data  = tx_data;
    assign b_tx_valid = tx_valid & sel_usb;
    assign tx_ready   = sel_usb ? b_tx_ready : u_tx_ready;

    //------------------------------------------------------------------
    // USB 2.0 device (rtl/usb, EP1 byte stream) + Single LVDS SoftPHY (as eda/usb_device top_sl.v)
    //------------------------------------------------------------------
    wire usb_pll_lock, os_lock, rst60;
    wire pll_60m /* synthesis syn_keep=1 */;
    wire os_f960 /* synthesis syn_keep=1 */, os_f480 /* synthesis syn_keep=1 */;
    wire clk60 /* synthesis syn_keep=1 */;
    wire os_pclk /* synthesis syn_keep=1 */;
    pll_usb u_pll_usb(.lock(usb_pll_lock), .clkout0(), .clkout1(pll_60m), .clkout2(), .clkout3(),
                      .clkin(clk_in), .psdir(1'b0), .pspulse(1'b0));
    pll_hs960 u_pll_os(.lock(os_lock), .clkout0(os_f960), .clkout1(os_f480), .clkin(pll_60m));
    logic [3:0] rst60_sr = 4'hF;
    always_ff @(posedge clk60) rst60_sr <= {rst60_sr[2:0], ~usb_pll_lock | ~os_lock | rst60};
    wire usb_rst = rst60_sr[3];

    wire [7:0] utmi_data_out, utmi_data_in;
    wire       utmi_txvalid, utmi_txready, utmi_rxactive, utmi_rxvalid, utmi_rxerror, utmi_termselect;
    wire [1:0] utmi_linestate, utmi_opmode, utmi_xcvrselect;
    wire       high_speed, configured;
    wire       e_rx_valid, e_rx_ready, e_tx_valid, e_tx_ready;   // EP1 stream, clk60
    wire [7:0] e_rx_data, e_tx_data;
    // vendor request 0x01 reads "GC" + high_speed: tells this cartridge apart from other 1209:0001 devices
    UsbDevice #(.HS_CAPABLE(1'b1), .CLK_PER_US(60), .EP1_STREAM(1'b1), .STREAM_FLUSH_US(20)) u_usb(
        .i_clk(clk60), .i_rst(usb_rst),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvrselect), .o_utmi_termselect(utmi_termselect),
        .o_high_speed(high_speed), .o_configured(configured), .o_suspended(), .o_reset(),
        .o_address(), .o_frame(), .o_sof(),
        .o_vendor_reg(), .i_vendor_status({8'h47, 8'h43, 15'd0, high_speed}),
        .o_rx_valid(e_rx_valid), .o_rx_data(e_rx_data), .i_rx_ready(e_rx_ready),
        .i_tx_valid(e_tx_valid), .i_tx_data(e_tx_data), .o_tx_ready(e_tx_ready));
    wire phy_pullup;
    usb_phy_gowin_sl #(.CMP1(1)) u_phy(
        .clk_ref_i(clk_in), .rstn_ref_i(1'b1), .pll_lock_i(os_lock & usb_pll_lock),
        .fclk_i(os_f960), .fclk480_i(os_f480), .pclk_o(os_pclk), .clk60_o(clk60), .rst60_o(rst60), .rst_i(usb_rst),
        .i_scan_freeze(1'b0), .i_scan_ofs(1'b0), .i_scan_class(2'd0), .i_hist_run(1'b0), .o_hist(),
        .o_samples(), .o_cmp_dbg(), .o_tx_oe(), .o_mon_line(),
        .utmi_data_out_i(utmi_data_out), .utmi_txvalid_i(utmi_txvalid), .utmi_txready_o(utmi_txready),
        .utmi_data_in_o(utmi_data_in), .utmi_rxactive_o(utmi_rxactive), .utmi_rxvalid_o(utmi_rxvalid),
        .utmi_rxerror_o(utmi_rxerror), .utmi_linestate_o(utmi_linestate),
        .utmi_opmode_i(utmi_opmode), .utmi_xcvrselect_i(utmi_xcvrselect), .utmi_termselect_i(utmi_termselect),
        .usb_dxp_io(usb_dp), .usb_dxn_io(usb_dn),
        .usb_rxdp_p_i(usb_cmp_dp), .usb_rxdp_n_i(usb_cmp_dp_n),
        .usb_rxdn_p_i(1'b0), .usb_rxdn_n_i(1'b1),
        .usb_pullup_en_o(phy_pullup), .usb_term_dp_o(usb_term_dp), .usb_term_dn_o(usb_term_dn),
        .usb_term_dp_i(usb_term_dp), .usb_term_dn_i(usb_term_dn));
    assign usb_pullup = phy_pullup & ~usb_rst;

    ByteAfifo u_usb_rx (
        .i_wclk(clk60), .i_wrst(usb_rst), .s_valid(e_rx_valid), .s_data(e_rx_data), .s_ready(e_rx_ready),
        .i_rclk(clk), .i_rrst(rst), .m_valid(b_rx_valid), .m_data(b_rx_data), .m_ready(b_rx_ready));
    ByteAfifo u_usb_tx (
        .i_wclk(clk), .i_wrst(rst), .s_valid(b_tx_valid), .s_data(tx_data), .s_ready(b_tx_ready),
        .i_rclk(clk60), .i_rrst(usb_rst), .m_valid(e_tx_valid), .m_data(e_tx_data), .m_ready(e_tx_ready));

    wire        fl_quad, fl_spiq, fl_cont, fl_ready, fl_want, fl_dval, raw_cs, raw_go, raw_done;
    wire [1:0]  fl_cap;
    wire [23:0] fl_addr, fl_daddr;
    wire [7:0]  fl_data, raw_tx, raw_rx;
    wire [7:0]  d_out;
    wire        d_oe;
    GameCart #(.CLK_HZ(100000000)) u_cart (
        .i_clk(clk), .i_rst(rst),
        .i_rx_valid(rx_valid), .i_rx_data(rx_data), .o_rx_ready(rx_ready),
        .o_tx_valid(tx_valid), .o_tx_data(tx_data), .i_tx_ready(tx_ready),
        .i_a(CART_A), .i_rd_n(CART_RD_N), .i_wr_n(CART_WR_N), .i_cs_n(CART_CS_N), .i_phi(CART_CLK),
        .i_rst_n(CART_RST_N), .i_d(CART_D), .o_d(d_out), .o_d_oe(d_oe), .o_d_dir(D_DIR), .o_d_oe_n(D_OE_N),
        .o_rst_drv(RST_DRV),
        .o_fl_quad(fl_quad), .i_fl_ready(fl_ready), .o_fl_cap(fl_cap), .o_fl_spiq(fl_spiq), .o_fl_cont(fl_cont), .o_fl_want(fl_want), .o_fl_addr(fl_addr),
        .i_fl_data(fl_data), .i_fl_daddr(fl_daddr), .i_fl_dval(fl_dval),
        .o_raw_cs(raw_cs), .o_raw_go(raw_go), .o_raw_tx(raw_tx), .i_raw_rx(raw_rx), .i_raw_done(raw_done));
    assign CART_D = d_oe ? d_out : 8'hzz;
    assign AUD_PWM = 1'b0;

    wire [3:0] io_o, io_oe;
    QspiRom u_fl (
        .i_clk(clk2), .i_rst(rst2),
        .i_quad(fl_quad), .o_ready(fl_ready), .i_cap(fl_cap), .i_spiq(fl_spiq), .i_cont(fl_cont), .i_want(fl_want), .i_addr(fl_addr),
        .o_data(fl_data), .o_daddr(fl_daddr), .o_dval(fl_dval),
        .i_raw_cs(raw_cs), .i_raw_go(raw_go), .i_raw_tx(raw_tx), .o_raw_rx(raw_rx), .o_raw_done(raw_done),
        .o_sclk(FL_SCLK), .o_cs_n(FL_CS_N), .o_io(io_o), .o_io_oe(io_oe), .i_io(FL_IO));
    genvar i;
    generate for (i = 0; i < 4; i++) begin : g_io
        assign FL_IO[i] = io_oe[i] ? io_o[i] : 1'bz;
    end endgenerate
endmodule
