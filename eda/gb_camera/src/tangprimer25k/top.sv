// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Tang Primer 25K as a Game Boy Camera style cartridge: eda/cart_game (GameCart on the FPGA
// cartridge adapter gb_fpga_cart_de0 in Dock J3, ROM from the SPI flash) with mapper 6 (cartridge
// type FCh) and GbCamera, fed by a Digilent Pcam 5C (OV5640, MIPI CSI-2 on Pmod_RPiCamera in pmod0,
// soft D-PHY as eda/csi_capture).
//
//   pmod0: camera ─► csi_phy_gw5a ─► Csi2Rx ─► IspRaw10Unpack ─► IspGbScale (1280x720 RAW10 ->
//          128x112 luma: 768x672 window, 6x6 blocks, black level, gain, sRGB curve)    [pclk 125 MHz]
//   GbCamera: frame buffer (written at pclk), registers at 0xA000, the shot into RAM bank 0
//   GameCart: the console bus, mapper, ROM bank 0 / RAM in block RAM, switchable banks from flash
//                                                                                     [clk 100 MHz]
//   csi_ctrl: OV5640 init (720p30 RAW10, AUTO_INIT ~20 ms after configuration), its commands
//                                                                                   [clk_in 50 MHz]
//
// Host links (HOST_UART, project.tcl from the environment):
//   0 (default): the Dock USB-UART is csi_ctrl's (115200, eda/csi_capture/host/csictl.py; 'X' / 'Y'
//                the design registers below); GameCart only on the Pmod USB HS Single (cart_emu --usb),
//                in pmod2 (USB_PMOD): the camera board in pmod0 is wider than a Pmod and covers pmod1
//   1:           the USB-UART is GameCart's (1 Mbaud, as eda/cart_game), csi_ctrl has no host
// Design registers ('X' a, 'Y' a): 0 black level (10 bits, default 16), 1 gain (8.8, 0x100),
//   2 {flip, mirror}; read only: 0x10 frames (16 bits, pclk domain, for debugging)
`default_nettype none
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

    inout  wire        usb_dp,
    inout  wire        usb_dn,
    input  wire        usb_cmp_dp,
    input  wire        usb_cmp_dp_n,
    inout  wire        usb_term_dp,
    inout  wire        usb_term_dn,
    output wire        usb_pullup,
    input  wire        vbus_det,

    input  wire        csi_clk_p,
    input  wire        csi_clk_n,
    input  wire        csi_d0_p,
    input  wire        csi_d0_n,
    input  wire        csi_d1_p,
    input  wire        csi_d1_n,
    inout  wire        cam_scl,
    inout  wire        cam_sda
);
`ifdef GB_CAMERA_HOST_UART
    localparam bit HOST_UART = 1'b1;
`else
    localparam bit HOST_UART = 1'b0;
`endif
    wire clk, clk2, lock;
    pll_100m_200m_50 u_pll (.lock(lock), .clkout0(clk), .clkout1(clk2), .clkin(clk_in), .reset(1'b0));
    logic [3:0] rst_sr = 4'hF;
    always_ff @(posedge clk) rst_sr <= {rst_sr[2:0], ~lock};
    wire rst = rst_sr[3];
    logic [3:0] rst2_sr = 4'hF;
    always_ff @(posedge clk2) rst2_sr <= {rst2_sr[2:0], ~lock};
    wire rst2 = rst2_sr[3];
    logic [3:0] rst50_sr = 4'hF;
    always_ff @(posedge clk_in) rst50_sr <= {rst50_sr[2:0], 1'b0};
    wire rst50 = rst50_sr[3];

    //------------------------------------------------------------------
    // GameCart command links: USB EP1, and the UART when HOST_UART
    //------------------------------------------------------------------
    wire       rx_valid, rx_ready, tx_valid, tx_ready;
    wire [7:0] rx_data, tx_data;
    wire       u_rx_valid, u_rx_ready, u_tx_valid, u_tx_ready;
    wire [7:0] u_rx_data, u_tx_data;
    wire       cart_uart_txd, cam_uart_txd;
    uart_rx #(.BAUD_DIVIDER(100)) u_rx (
        .clock(clk), .reset(rst), .data_valid(u_rx_valid), .data_ready(u_rx_ready), .data_bits(u_rx_data),
        .rx(HOST_UART ? uart_rxd : 1'b1));
    uart_tx #(.BAUD_DIVIDER(100)) u_tx (
        .clock(clk), .reset(rst), .data_valid(u_tx_valid), .data_ready(u_tx_ready), .data_bits(u_tx_data), .tx(cart_uart_txd));
    assign uart_txd = HOST_UART ? cart_uart_txd : cam_uart_txd;

    wire       b_rx_valid, b_rx_ready, b_tx_valid, b_tx_ready;
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
    // USB 2.0 device (as eda/cart_game)
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
    wire       e_rx_valid, e_rx_ready, e_tx_valid, e_tx_ready;
    wire [7:0] e_rx_data, e_tx_data;
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
    usb_phy_gowin_sl #(.CMP1(1)) u_usbphy(
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

    //------------------------------------------------------------------
    // camera: D-PHY, CSI-2, RAW10 -> 128x112 luma (pclk)
    //------------------------------------------------------------------
    wire        pclk, prst, cam_pll_lock;
    wire [31:0] s_clk, s_d0, s_d1;
    csi_phy_gw5a u_phy (
        .clk_ref(clk_in), .rstn_ref(!rst50),
        .i_clk_p(csi_clk_p), .i_clk_n(csi_clk_n),
        .i_d0_p(csi_d0_p),   .i_d0_n(csi_d0_n),
        .i_d1_p(csi_d1_p),   .i_d1_n(csi_d1_n),
        .o_pclk(pclk), .o_reset(prst), .o_pll_lock(cam_pll_lock),
        .o_s_clk(s_clk), .o_s_d0(s_d0), .o_s_d1(s_d1));

    logic [3:0] ofs0, ofs1;
    logic [1:0] inv;
    logic [3:0] ofs0_p [0:1], ofs1_p [0:1];
    logic [1:0] inv_p [0:1];
    always_ff @(posedge pclk) begin
        ofs0_p[0] <= ofs0; ofs0_p[1] <= ofs0_p[0];
        ofs1_p[0] <= ofs1; ofs1_p[1] <= ofs1_p[0];
        inv_p[0]  <= inv;  inv_p[1]  <= inv_p[0];
    end

    logic        hdr, short_pkt, pend, crc_ok, ecc_corr, ecc_err, abort_pkt, dvld, ovf, drop;
    logic [1:0]  vc, be, sync, active;
    logic [5:0]  dt;
    logic [15:0] wc, data;
    logic [3:0]  nbits;
    Csi2Rx u_rx2 (
        .i_clk(pclk), .i_rst(prst),
        .i_cs(s_clk), .i_ds({s_d1, s_d0}), .i_inv(inv_p[1]), .i_ofs({ofs1_p[1], ofs0_p[1]}),
        .o_hdr(hdr), .o_short(short_pkt), .o_vc(vc), .o_dt(dt), .o_wc(wc),
        .o_data(data), .o_data_be(be), .o_data_vld(dvld),
        .o_end(pend), .o_crc_ok(crc_ok), .o_ecc_corr(ecc_corr), .o_ecc_err(ecc_err), .o_abort(abort_pkt),
        .o_dbg_nbits(nbits), .o_dbg_ovf(ovf), .o_dbg_sync(sync), .o_dbg_drop(drop), .o_dbg_active(active));

    logic        rw_we, r0, fs;
    logic [8:0]  rw_addr;
    logic [39:0] rw_data;
    logic [11:0] rw_row;
    IspRaw10Unpack u_unpack (
        .i_clk(pclk), .i_rst(prst),
        .i_hdr(hdr), .i_short(short_pkt), .i_dt(dt), .i_data(data), .i_be(be), .i_vld(dvld),
        .o_we(rw_we), .o_waddr(rw_addr), .o_wdata(rw_data), .o_row(rw_row), .o_r0(r0), .o_fs(fs));

    // design registers (csi_ctrl domain, quasi-static), into pclk through two flip-flops
    logic        xwr;
    logic [7:0]  xaddr;
    logic [15:0] xdata, xrdata;
    logic [9:0]  r_black;
    logic [15:0] r_gain;
    logic [1:0]  r_orient;
    always_ff @(posedge clk_in) begin
        if (rst50) begin
            r_black  <= 10'd16;
            r_gain   <= 16'h0100;
            r_orient <= 2'd0;
        end else if (xwr) begin
            case (xaddr)
                8'h00: r_black  <= xdata[9:0];
                8'h01: r_gain   <= xdata;
                8'h02: r_orient <= xdata[1:0];
                default: ;
            endcase
        end
    end
    logic [9:0]  black_p [0:1];
    logic [15:0] gain_p [0:1];
    logic [1:0]  orient_p [0:1];
    always_ff @(posedge pclk) begin
        black_p[0]  <= r_black;  black_p[1]  <= black_p[0];
        gain_p[0]   <= r_gain;   gain_p[1]   <= gain_p[0];
        orient_p[0] <= r_orient; orient_p[1] <= orient_p[0];
    end

    wire        fb_we, frame_tgl;
    wire [13:0] fb_wa;
    wire [7:0]  fb_wd;
    IspGbScale u_scale (
        .i_clk(pclk), .i_rst(prst),
        .i_we(rw_we), .i_waddr(rw_addr), .i_wdata(rw_data), .i_row(rw_row),
        .i_black(black_p[1]), .i_gain(gain_p[1]), .i_mirror(orient_p[1][0]), .i_flip(orient_p[1][1]),
        .o_we(fb_we), .o_wa(fb_wa), .o_wd(fb_wd), .o_frame(frame_tgl));
    logic [15:0] n_frames;
    logic        frame_q;
    always_ff @(posedge pclk) begin
        frame_q <= frame_tgl;
        if (prst) n_frames <= '0;
        else if (frame_q != frame_tgl) n_frames <= n_frames + 1'b1;
    end

    always_comb begin
        case (xaddr)
            8'h00: xrdata = {6'd0, r_black};
            8'h01: xrdata = r_gain;
            8'h02: xrdata = {14'd0, r_orient};
            8'h10: xrdata = n_frames;   // (pclk domain, read for debugging)
            default: xrdata = 16'hDEAD;
        endcase
    end
    wire scl_oe, sda_oe, scl_in, sda_in;
    IOBUF u_scl (.O(scl_in), .IO(cam_scl), .I(1'b0), .OEN(!scl_oe));
    IOBUF u_sda (.O(sda_in), .IO(cam_sda), .I(1'b0), .OEN(!sda_oe));
    logic init_busy, aux_ack;
    csi_ctrl #(.SENSOR(2), .I2C_DEV(7'h3C), .VERSION(8'h53)) u_ctrl (
        .clk(clk_in), .rst(rst50), .uart_rxd(HOST_UART ? 1'b1 : uart_rxd), .uart_txd(cam_uart_txd),
        .o_scl_oe(scl_oe), .o_sda_oe(sda_oe), .i_scl(scl_in), .i_sda(sda_in),
        .o_ofs0(ofs0), .o_ofs1(ofs1), .o_inv(inv), .o_init_busy(init_busy),
        .o_snap_tgl(), .i_snap_ack(1'b0), .o_snap_idx(), .i_snap_data(32'd0),
        .o_cap_tgl(), .o_cap_mode(), .o_cap_raddr(), .i_cap_rdata(96'd0),
        .o_log_tgl(), .o_log_at_fs(), .o_log_raddr(), .i_log_rdata(64'd0),
        .o_xwr(xwr), .o_xaddr(xaddr), .o_xdata(xdata), .i_xrdata(xrdata),
        .i_aux_tgl(1'b0), .i_aux_addr(16'h0000), .i_aux_data(8'h00), .o_aux_ack(aux_ack));

    //------------------------------------------------------------------
    // the cartridge (clk)
    //------------------------------------------------------------------
    wire        fl_quad, fl_spiq, fl_cont, fl_ready, fl_want, fl_dval, raw_cs, raw_go, raw_done;
    wire [1:0]  fl_cap;
    wire [23:0] fl_addr, fl_daddr;
    wire [7:0]  fl_data, raw_tx, raw_rx;
    wire [7:0]  d_out;
    wire        d_oe;
    wire        cam_we, cam_busy, cam_ram_we;
    wire [6:0]  cam_wa;
    wire [7:0]  cam_wd, cam_reg0, cam_ram_wd, cam_hq;
    wire [11:0] cam_ram_wa;
    wire [15:0] cam_hra;
    GameCart #(.CLK_HZ(100000000), .CAMERA(1'b1), .TRACE(1'b0)) u_cart (
        .i_clk(clk), .i_rst(rst),
        .i_rx_valid(rx_valid), .i_rx_data(rx_data), .o_rx_ready(rx_ready),
        .o_tx_valid(tx_valid), .o_tx_data(tx_data), .i_tx_ready(tx_ready),
        .i_a(CART_A), .i_rd_n(CART_RD_N), .i_wr_n(CART_WR_N), .i_cs_n(CART_CS_N), .i_phi(CART_CLK),
        .i_rst_n(CART_RST_N), .i_d(CART_D), .o_d(d_out), .o_d_oe(d_oe), .o_d_dir(D_DIR), .o_d_oe_n(D_OE_N),
        .o_rst_drv(RST_DRV),
        .o_fl_quad(fl_quad), .i_fl_ready(fl_ready), .o_fl_cap(fl_cap), .o_fl_spiq(fl_spiq), .o_fl_cont(fl_cont), .o_fl_want(fl_want), .o_fl_addr(fl_addr),
        .i_fl_data(fl_data), .i_fl_daddr(fl_daddr), .i_fl_dval(fl_dval),
        .o_raw_cs(raw_cs), .o_raw_go(raw_go), .o_raw_tx(raw_tx), .i_raw_rx(raw_rx), .i_raw_done(raw_done),
        .o_cam_we(cam_we), .o_cam_wa(cam_wa), .o_cam_wd(cam_wd), .i_cam_reg0(cam_reg0), .i_cam_busy(cam_busy),
        .i_cam_ram_we(cam_ram_we), .i_cam_ram_wa(cam_ram_wa), .i_cam_ram_wd(cam_ram_wd),
        .o_cam_hra(cam_hra), .i_cam_hq(cam_hq));
    assign CART_D = d_oe ? d_out : 8'hzz;
    assign AUD_PWM = 1'b0;

    GbCamera u_cam (
        .i_clk(clk), .i_rst(rst),
        .i_pclk(pclk), .i_fb_we(fb_we), .i_fb_wa(fb_wa), .i_fb_wd(fb_wd), .i_frame(frame_tgl),
        .i_reg_we(cam_we), .i_reg_a(cam_wa), .i_reg_d(cam_wd), .o_reg0(cam_reg0), .o_busy(cam_busy),
        .o_ram_we(cam_ram_we), .o_ram_wa(cam_ram_wa), .o_ram_wd(cam_ram_wd),
        .i_h_ra(cam_hra), .o_h_q(cam_hq));

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

    wire _unused = &{1'b0, r0, fs, vc, wc, pend, crc_ok, ecc_corr, ecc_err, abort_pkt, ovf, drop, sync, active, nbits,
                     init_busy, aux_ack, cam_pll_lock, configured, vbus_det};
endmodule
`default_nettype wire
