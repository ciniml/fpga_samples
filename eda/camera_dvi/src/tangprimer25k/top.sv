// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief Tang Primer 25K: Digilent Pcam 5C (OV5640, MIPI CSI-2, soft D-PHY)
 *        -> demosaic / white balance / gamma -> DVI 1280x720p30, no frame
 *        buffer: the camera is locked to the display.
 *
 *   pmod0 (bank 1): camera (Pmod_RPiCamera)       ─► csi_phy_gw5a ─► Csi2Rx
 *       ─► IspRaw10Unpack ─► IspLineRing (8 raw lines, BSRAM)   [125 MHz]
 *   IspVideoTiming (CEA 720p30) ─► IspDisplay (3x3 window, bilinear
 *       demosaic, black level, gains, sRGB gamma) ─► dvi_out ─► OSER10
 *       ─► pmod2 (Pmod DVI)                                    [74.25 MHz]
 *   IspGenlock: row 0 of every camera frame should arrive 4 lines before
 *       the display's first active line; the camera's frame length (VTS,
 *       0x380F) is rewritten every frame through csi_ctrl's aux port.
 *       The camera's line length (HTS 2489 at PCLK 56 MHz) equals the
 *       display line (3300 / 74.25 MHz = 44.444 us).
 *   USB-UART 115200: csi_ctrl (eda/csi_capture/host/csictl.py; 'X' / 'Y'
 *       for the registers below, host/camctl.py).
 *
 * Design registers ('X' a, 'Y' a): 0 mode (0 camera, 1 colour bars, 2 raw
 *   grey, 3 grey), 1 CFA (3 = BGGR), 2 black level, 3..5 gains R G B (8.8),
 *   6 genlock enable, 7 target lead (lines), 8 max VTS step, 9 VTS nominal;
 *   read only: 0x10 genlock error, 0x11 display line of row 0, 0x12 VTS
 *   sent, 0x13 locked, 0x14 VTS writes.
 * LEDs: led_lock (B2) = genlock locked, led_err (C2) = CRC / ECC error in
 *   the last ~0.13 s or a PLL not locked.
 */
`default_nettype none
`ifdef CAMERA_DVI_1080P
`define CAM_W 1920
`define CAM_H 1080
`define CAM_VT 1125
`else
`define CAM_W 1280
`define CAM_H 720
`define CAM_VT 750
`endif
module top (
    input  wire clock,           // 50 MHz
    input  wire reset_button,

    input  wire csi_clk_p,
    input  wire csi_clk_n,
    input  wire csi_d0_p,
    input  wire csi_d0_n,
    input  wire csi_d1_p,
    input  wire csi_d1_n,
    inout  wire cam_scl,
    inout  wire cam_sda,

    output wire       tx_clk_p,
    output wire       tx_clk_n,
    output wire [2:0] tx_data_p,
    output wire [2:0] tx_data_n,

    output wire uart_txd,
    input  wire uart_rxd,
    output wire led_lock,
    output wire led_err
);
    localparam int W  = `CAM_W;
    localparam int H  = `CAM_H;
    localparam int VT = `CAM_VT;

    // ---------------- system clock domain ----------------
    logic reset_sys;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_sys (
        .clock(clock), .reset_in(reset_button), .reset_out(reset_sys));

    // ---------------- D-PHY front end + CSI-2 receiver (pclk 125 MHz) ----------------
    wire        pclk, prst, pll_lock;
    wire [31:0] s_clk, s_d0, s_d1;
    csi_phy_gw5a u_phy (
        .clk_ref(clock), .rstn_ref(!reset_sys),
        .i_clk_p(csi_clk_p), .i_clk_n(csi_clk_n),
        .i_d0_p(csi_d0_p),   .i_d0_n(csi_d0_n),
        .i_d1_p(csi_d1_p),   .i_d1_n(csi_d1_n),
        .o_pclk(pclk), .o_reset(prst), .o_pll_lock(pll_lock),
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
    Csi2Rx u_rx (
        .i_clk(pclk), .i_rst(prst),
        .i_cs(s_clk), .i_ds({s_d1, s_d0}), .i_inv(inv_p[1]), .i_ofs({ofs1_p[1], ofs0_p[1]}),
        .o_hdr(hdr), .o_short(short_pkt), .o_vc(vc), .o_dt(dt), .o_wc(wc),
        .o_data(data), .o_data_be(be), .o_data_vld(dvld),
        .o_end(pend), .o_crc_ok(crc_ok), .o_ecc_corr(ecc_corr), .o_ecc_err(ecc_err), .o_abort(abort_pkt),
        .o_dbg_nbits(nbits), .o_dbg_ovf(ovf), .o_dbg_sync(sync), .o_dbg_drop(drop), .o_dbg_active(active));

    // ---------------- instrumentation (csictl.py stats / log / capture) ----------------
    logic        snap_tgl, snap_ack, cap_tgl, log_tgl, log_at_fs;
    logic [4:0]  snap_idx;
    logic [31:0] snap_data;
    logic [2:0]  cap_mode;
    logic [9:0]  cap_raddr, log_raddr;
    logic [95:0] cap_rdata;
    logic [63:0] log_rdata;
    csi_stats u_stats (
        .pclk(pclk), .prst(prst),
        .i_hdr(hdr), .i_short(short_pkt), .i_vc(vc), .i_dt(dt), .i_wc(wc),
        .i_end(pend), .i_crc_ok(crc_ok), .i_ecc_corr(ecc_corr), .i_ecc_err(ecc_err), .i_abort(abort_pkt),
        .i_nbits(nbits), .i_ovf(ovf), .i_sync(sync), .i_drop(drop), .i_active(active),
        .i_s_clk(s_clk), .i_s_d0(s_d0), .i_s_d1(s_d1),
        .clk(clock), .i_snap_tgl(snap_tgl), .o_snap_ack(snap_ack), .i_snap_idx(snap_idx), .o_snap_data(snap_data),
        .i_cap_tgl(cap_tgl), .i_cap_mode(cap_mode), .i_cap_raddr(cap_raddr), .o_cap_rdata(cap_rdata),
        .i_log_tgl(log_tgl), .i_log_at_fs(log_at_fs), .i_log_raddr(log_raddr), .o_log_rdata(log_rdata));

    // ---------------- raw lines into the ring (pclk) ----------------
    logic        rw_we, r0, fs;
    logic [8:0]  rw_addr;
    logic [39:0] rw_data;
    logic [11:0] rw_row;
    IspRaw10Unpack u_unpack (
        .i_clk(pclk), .i_rst(prst),
        .i_hdr(hdr), .i_short(short_pkt), .i_dt(dt), .i_data(data), .i_be(be), .i_vld(dvld),
        .o_we(rw_we), .o_waddr(rw_addr), .o_wdata(rw_data), .o_row(rw_row), .o_r0(r0), .o_fs(fs));
    logic r0_tgl;
    always_ff @(posedge pclk) begin
        if (prst) r0_tgl <= 1'b0;
        else if (r0) r0_tgl <= ~r0_tgl;
    end

    // ---------------- display clocks: 50 -> 27 -> 74.25 / 371.25 MHz ----------------
    logic clock_27, pll_27_lock;
    gowin_pll_27 u_pll_27 (.clkout0(clock_27), .lock(pll_27_lock), .clkin(clock));
    logic tx_pclk, tx_fclk, tx_pll_lock;
    pll_tx_1080p #(.ODIV0(10), .ODIV1(2)) u_pll_tx (
        .clkout0(tx_pclk), .clkout1(tx_fclk), .lock(tx_pll_lock), .clkin(clock_27));
    logic reset_tx;
    reset_seq #(.RESET_DELAY_CYCLES(8)) u_reset_tx (
        .clock(tx_pclk), .reset_in(!pll_27_lock || !tx_pll_lock || reset_button), .reset_out(reset_tx));

    // ---------------- design registers (system domain, quasi-static) ----------------
    logic        xwr;
    logic [7:0]  xaddr;
    logic [15:0] xdata, xrdata;
    logic [1:0]  r_mode, r_cfa;
    logic [9:0]  r_black;
    logic [15:0] r_gain_r, r_gain_g, r_gain_b, r_vts0;
    logic        r_lock_en;
    logic [7:0]  r_target, r_maxstep;
    always_ff @(posedge clock) begin
        if (reset_sys) begin
            r_mode    <= 2'd0;
            r_cfa     <= 2'd3;
            r_black   <= 10'd16;
            r_gain_r  <= 16'h0100;
            r_gain_g  <= 16'h0100;
            r_gain_b  <= 16'h0100;
            r_lock_en <= 1'b1;
            r_target  <= 8'd4;
            r_maxstep <= 8'd16;
            r_vts0    <= 16'(VT);
        end else if (xwr) begin
            case (xaddr)
                8'h00: r_mode    <= xdata[1:0];
                8'h01: r_cfa     <= xdata[1:0];
                8'h02: r_black   <= xdata[9:0];
                8'h03: r_gain_r  <= xdata;
                8'h04: r_gain_g  <= xdata;
                8'h05: r_gain_b  <= xdata;
                8'h06: r_lock_en <= xdata[0];
                8'h07: r_target  <= xdata[7:0];
                8'h08: r_maxstep <= xdata[7:0];
                8'h09: r_vts0    <= xdata;
                default: ;
            endcase
        end
    end

    // ---------------- display (tx_pclk) ----------------
    logic [11:0] vx, vy;
    logic        vde, vhs, vvs;
`ifdef CAMERA_DVI_1080P
    IspVideoTiming #(.HACT(1920), .HFP(88), .HSW(44), .HBP(148), .VACT(1080), .VFP(4), .VSW(5), .VBP(36)) u_timing (
`else
    IspVideoTiming u_timing (
`endif
        .i_clk(tx_pclk), .i_rst(reset_tx), .o_x(vx), .o_y(vy), .o_de(vde), .o_hs(vhs), .o_vs(vvs));

    logic [8:0]  rd_addr;
    logic [2:0]  rb0, rb1, rb2;
    logic [39:0] q0, q1, q2;
    IspLineRing u_ring (
        .i_wclk(pclk), .i_we(rw_we), .i_wbank(rw_row[2:0]), .i_waddr(rw_addr), .i_wdata(rw_data),
        .i_rclk(tx_pclk), .i_raddr(rd_addr), .i_rbank0(rb0), .i_rbank1(rb1), .i_rbank2(rb2),
        .o_q0(q0), .o_q1(q1), .o_q2(q2));

    logic [23:0] rgb;
    logic        ode, ohs, ovs;
    IspDisplay #(.W(W), .H(H)) u_disp (
        .i_clk(tx_pclk), .i_rst(reset_tx), .i_x(vx), .i_y(vy), .i_de(vde), .i_hs(vhs), .i_vs(vvs),
        .i_black(r_black), .i_gain_r(r_gain_r), .i_gain_g(r_gain_g), .i_gain_b(r_gain_b),
        .i_cfa(r_cfa), .i_mode(r_mode),
        .o_raddr(rd_addr), .o_rbank0(rb0), .o_rbank1(rb1), .o_rbank2(rb2), .i_q0(q0), .i_q1(q1), .i_q2(q2),
        .o_rgb(rgb), .o_de(ode), .o_hs(ohs), .o_vs(ovs));

    // camera row 0 -> display domain
    logic [2:0] r0_s;
    always_ff @(posedge tx_pclk) r0_s <= {r0_s[1:0], r0_tgl};
    wire r0_p = r0_s[2] ^ r0_s[1];

    logic [15:0] vts_cmd, lock_err;
    logic [11:0] lock_vr0;
    logic        vts_req, locked;
    IspGenlock #(.VT(VT)) u_lock (
        .i_clk(tx_pclk), .i_rst(reset_tx), .i_y(vy), .i_x(vx), .i_r0(r0_p),
        .i_en(r_lock_en), .i_target(r_target), .i_vts0(r_vts0), .i_maxstep(r_maxstep),
        .o_vts(vts_cmd), .o_req(vts_req), .o_err(lock_err), .o_vr0(lock_vr0), .o_locked(locked));

    // VTS request -> system domain -> csi_ctrl aux port (0x380F = VTS[7:0])
    logic [2:0]  vts_req_s;
    logic        aux_ack;
    logic [15:0] vts_writes;
    always_ff @(posedge clock) begin
        vts_req_s <= {vts_req_s[1:0], vts_req};
        if (reset_sys) vts_writes <= '0;
        else if (vts_req_s[2] != vts_req_s[1]) vts_writes <= vts_writes + 1'b1;
    end

    // ---------------- DVI out ----------------
    logic [9:0] tmds_clock_word;
    logic [9:0] tmds_word [0:2];
    dvi_out u_dvi_out (
        .clock(tx_pclk), .reset(reset_tx),
        .video_data(rgb), .video_de(ode), .video_hsync(ohs), .video_vsync(ovs),
        .dvi_clock(tmds_clock_word), .dvi_data0(tmds_word[0]), .dvi_data1(tmds_word[1]), .dvi_data2(tmds_word[2]));
    wire [9:0] ser_word [0:3];
    assign ser_word[0] = tmds_word[0];
    assign ser_word[1] = tmds_word[1];
    assign ser_word[2] = tmds_word[2];
    assign ser_word[3] = tmds_clock_word;
    wire [3:0] ser_q;
    generate
        for (genvar i = 0; i < 4; i++) begin : g_oser
            OSER10 u_oser (
                .Q(ser_q[i]),
                .D0(ser_word[i][0]), .D1(ser_word[i][1]), .D2(ser_word[i][2]), .D3(ser_word[i][3]), .D4(ser_word[i][4]),
                .D5(ser_word[i][5]), .D6(ser_word[i][6]), .D7(ser_word[i][7]), .D8(ser_word[i][8]), .D9(ser_word[i][9]),
                .FCLK(tx_fclk), .PCLK(tx_pclk), .RESET(reset_tx));
        end
        for (genvar i = 0; i < 3; i++) begin : g_tx_obuf
            ELVDS_OBUF u_obuf (.I(ser_q[i]), .O(tx_data_p[i]), .OB(tx_data_n[i]));
        end
    endgenerate
    ELVDS_OBUF u_obuf_clk (.I(ser_q[3]), .O(tx_clk_p), .OB(tx_clk_n));

    // ---------------- host interface + I2C ----------------
    always_comb begin
        case (xaddr)
            8'h00: xrdata = {14'd0, r_mode};
            8'h01: xrdata = {14'd0, r_cfa};
            8'h02: xrdata = {6'd0, r_black};
            8'h03: xrdata = r_gain_r;
            8'h04: xrdata = r_gain_g;
            8'h05: xrdata = r_gain_b;
            8'h06: xrdata = {15'd0, r_lock_en};
            8'h07: xrdata = {8'd0, r_target};
            8'h08: xrdata = {8'd0, r_maxstep};
            8'h09: xrdata = r_vts0;
            8'h10: xrdata = lock_err;          // (display domain, read for debugging)
            8'h11: xrdata = {4'd0, lock_vr0};
            8'h12: xrdata = vts_cmd;
            8'h13: xrdata = {15'd0, locked};
            8'h14: xrdata = vts_writes;
            default: xrdata = 16'hDEAD;
        endcase
    end
    wire scl_oe, sda_oe, scl_in, sda_in;
    IOBUF u_scl (.O(scl_in), .IO(cam_scl), .I(1'b0), .OEN(!scl_oe));
    IOBUF u_sda (.O(sda_in), .IO(cam_sda), .I(1'b0), .OEN(!sda_oe));
    logic init_busy;
    csi_ctrl #(.SENSOR(2), .I2C_DEV(7'h3C), .VERSION(8'h52)) u_ctrl (
        .clk(clock), .rst(reset_sys), .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .o_scl_oe(scl_oe), .o_sda_oe(sda_oe), .i_scl(scl_in), .i_sda(sda_in),
        .o_ofs0(ofs0), .o_ofs1(ofs1), .o_inv(inv), .o_init_busy(init_busy),
        .o_snap_tgl(snap_tgl), .i_snap_ack(snap_ack), .o_snap_idx(snap_idx), .i_snap_data(snap_data),
        .o_cap_tgl(cap_tgl), .o_cap_mode(cap_mode), .o_cap_raddr(cap_raddr), .i_cap_rdata(cap_rdata),
        .o_log_tgl(log_tgl), .o_log_at_fs(log_at_fs), .o_log_raddr(log_raddr), .i_log_rdata(log_rdata),
        .o_xwr(xwr), .o_xaddr(xaddr), .o_xdata(xdata), .i_xrdata(xrdata),
        .i_aux_tgl(vts_req_s[2]), .i_aux_addr(16'h380F),   // served after the init
        .i_aux_data(vts_cmd[7:0]), .o_aux_ack(aux_ack));

    // ---------------- LEDs ----------------
    logic [23:0] err_st;    // ~0.13 s at 125 MHz
    wire         err_ev = ecc_err || abort_pkt || (pend && !crc_ok);
    always_ff @(posedge pclk) begin
        if (prst) err_st <= '0;
        else if (err_ev) err_st <= '1;
        else if (err_st[23]) err_st <= err_st - 1'b1;
    end
    logic [2:0] locked_s;
    always_ff @(posedge clock) locked_s <= {locked_s[1:0], locked};
    assign led_lock = locked_s[2];
    assign led_err  = err_st[23] || !pll_lock || !tx_pll_lock;
    wire _unused = &{1'b0, fs, vc, wc, init_busy};
endmodule
`default_nettype wire
