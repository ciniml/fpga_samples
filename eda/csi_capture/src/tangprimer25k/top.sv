// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file top.sv
 * @brief Tang Primer 25K: MIPI CSI-2 camera (Raspberry Pi Camera v2,
 *        IMX219) on one Pmod, soft D-PHY, bring-up instrumentation.
 *
 *   pmod0 (bank 1): CLK / D0 / D1 pairs (LVDS25, on-chip 100 ohm
 *   termination always on, no LP receivers) + I2C (SCL / SDA)
 *       ─► csi_phy_gw5a (OSIDES32 ×3, 4 Gsps, free-running 125 MHz words)
 *       ─► Csi2Rx (rtl/csi2: clock-edge sampling, SoT, lanes, packets)
 *       ─► csi_stats (counters, packet log, raw sample capture)
 *   USB-UART 115200: csi_ctrl (host/csictl.py) — sensor registers, init,
 *   receiver trims, readouts. The sensor is initialised automatically
 *   ~20 ms after configuration (640x480 RAW10, 2 x 456 Mbps).
 *
 * LEDs: led_rx = long packets with good CRC within ~0.1 s,
 *       led_err = CRC / ECC error or abort within ~0.1 s.
 * Scope taps (pmod2 bottom row): dbg[0] clock-lane activity,
 *       dbg[1] a lane aligner in RX, dbg[2] frame (FS..FE), dbg[3] error.
 */
`default_nettype none
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

    output wire uart_txd,
    input  wire uart_rxd,

    output logic led_rx,
    output logic led_err,
    output logic [3:0] dbg
);
    // ---------------- system clock domain ----------------
    logic reset_sys;
    reset_seq #(.RESET_DELAY_CYCLES(16)) reset_seq_sys (
        .clock(clock), .reset_in(reset_button), .reset_out(reset_sys));

    // ---------------- D-PHY front end ----------------
    wire        pclk, prst, pll_lock;
    wire [31:0] s_clk, s_d0, s_d1;
    csi_phy_gw5a u_phy (
        .clk_ref(clock), .rstn_ref(!reset_sys),
        .i_clk_p(csi_clk_p), .i_clk_n(csi_clk_n),
        .i_d0_p(csi_d0_p),   .i_d0_n(csi_d0_n),
        .i_d1_p(csi_d1_p),   .i_d1_n(csi_d1_n),
        .o_pclk(pclk), .o_reset(prst), .o_pll_lock(pll_lock),
        .o_s_clk(s_clk), .o_s_d0(s_d0), .o_s_d1(s_d1));

    // receiver settings from the system domain (quasi-static)
    logic [3:0] ofs0, ofs1;
    logic [1:0] inv;
    logic [3:0] ofs0_p [0:1], ofs1_p [0:1];
    logic [1:0] inv_p [0:1];
    always_ff @(posedge pclk) begin
        ofs0_p[0] <= ofs0; ofs0_p[1] <= ofs0_p[0];
        ofs1_p[0] <= ofs1; ofs1_p[1] <= ofs1_p[0];
        inv_p[0]  <= inv;  inv_p[1]  <= inv_p[0];
    end

    // ---------------- CSI-2 receiver ----------------
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

    // ---------------- instrumentation ----------------
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

    // ---------------- host interface + I2C ----------------
    wire scl_oe, sda_oe, scl_in, sda_in;
    IOBUF u_scl (.O(scl_in), .IO(cam_scl), .I(1'b0), .OEN(!scl_oe));
    IOBUF u_sda (.O(sda_in), .IO(cam_sda), .I(1'b0), .OEN(!sda_oe));
    logic init_busy;
    csi_ctrl u_ctrl (
        .clk(clock), .rst(reset_sys), .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .o_scl_oe(scl_oe), .o_sda_oe(sda_oe), .i_scl(scl_in), .i_sda(sda_in),
        .o_ofs0(ofs0), .o_ofs1(ofs1), .o_inv(inv), .o_init_busy(init_busy),
        .o_snap_tgl(snap_tgl), .i_snap_ack(snap_ack), .o_snap_idx(snap_idx), .i_snap_data(snap_data),
        .o_cap_tgl(cap_tgl), .o_cap_mode(cap_mode), .o_cap_raddr(cap_raddr), .i_cap_rdata(cap_rdata),
        .o_log_tgl(log_tgl), .o_log_at_fs(log_at_fs), .o_log_raddr(log_raddr), .i_log_rdata(log_rdata));

    // ---------------- LEDs / scope taps ----------------
    logic [23:0] ok_st, err_st;    // ~0.13 s at 125 MHz
    logic        in_frame;
    wire         err_ev = ecc_err || abort_pkt || (pend && !crc_ok);
    always_ff @(posedge pclk) begin
        if (prst) begin
            ok_st    <= '0;
            err_st   <= '0;
            in_frame <= 1'b0;
        end else begin
            if (pend && crc_ok)  ok_st  <= '1; else if (ok_st[23])  ok_st  <= ok_st - 1'b1;
            if (err_ev)          err_st <= '1; else if (err_st[23]) err_st <= err_st - 1'b1;
            if (hdr && short_pkt && dt == 6'h00) in_frame <= 1'b1;
            if (hdr && short_pkt && dt == 6'h01) in_frame <= 1'b0;
        end
        dbg[0] <= nbits != 4'd0;
        dbg[1] <= |active;
        dbg[2] <= in_frame;
        dbg[3] <= err_ev;
    end
    assign led_rx  = ok_st[23];
    assign led_err = err_st[23] || !pll_lock;
    wire _unused = &{1'b0, dvld, be, data, init_busy};
endmodule
`default_nettype wire
