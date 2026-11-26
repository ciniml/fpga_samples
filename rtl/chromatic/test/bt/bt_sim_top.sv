// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Cartridge bus test, both ends: the Chromatic side (CartPower + TestBus + BtCmd, 60 MHz) and the
// adapter with the test target (CartTarget, 100 MHz), joined by a model of gb_fpga_cart_de0:
// SN74LVC4245A data shifter (D_DIR selects the direction, /D_OE enables), the console-side
// shifters of the Chromatic, /RST wired-AND (pull-ups), every line 0 at the target while the slot
// is unpowered (Ioff). Counts data bus contention (both ends driving the slot side).
`timescale 1ns/1ps
module bt_sim_top #(
    parameter int SIM_HZ60  = 60000,     // timer scaling of the Chromatic side
    parameter int SIM_HZ100 = 100000
) (
    input  logic       clk60,
    input  logic       clk100,
    input  logic       rst,
    input  logic       cart_det,
    input  logic       switch_on,
    // Chromatic USB stream
    input  logic       c_rx_valid,
    input  logic [7:0] c_rx_data,
    output logic       c_rx_ready,
    output logic       c_tx_valid,
    output logic [7:0] c_tx_data,
    input  logic       c_tx_ready,
    // target UART stream
    input  logic       t_rx_valid,
    input  logic [7:0] t_rx_data,
    output logic       t_rx_ready,
    output logic       t_tx_valid,
    output logic [7:0] t_tx_data,
    input  logic       t_tx_ready,
    output int         n_contention
);
    // ---- Chromatic ----
    logic legacy, pw_ready, pwr_en, ctrl_oe, drive_low, power_en, rst_done, rst_force;
    logic req_valid, req_write, req_ready, rsp_valid;
    logic [15:0] req_addr, a, st_a;
    logic [7:0] req_wdata, rsp_data, d_out, c_d_in, d_seen, st_d;
    logic [7:0] cyc, sample, wr_on, wr_off;
    logic [5:0] st_ctl;
    logic st_en, d_oe, phi, rd_n, wr_n, cs_n, dir_e, rst_low;
    logic slot_rst_n;

    CartPower #(.CLK_HZ(SIM_HZ60)) u_pwr (
        .i_clk(clk60), .i_rst(rst), .i_enable(power_en), .i_version_det(1'b0),
        .o_legacy(legacy), .o_ready(pw_ready), .o_pwr_en(pwr_en), .o_ctrl_oe(ctrl_oe), .o_drive_low(drive_low));
    TestBus u_bus (
        .i_clk(clk60), .i_rst(rst), .i_ready(pw_ready), .i_drive_low(drive_low), .i_rst_force(rst_force),
        .i_cyc(cyc), .i_sample(sample), .i_wr_on(wr_on), .i_wr_off(wr_off),
        .i_static(st_en), .i_st_a(st_a), .i_st_ctl(st_ctl), .i_st_d(st_d), .o_d_seen(d_seen),
        .i_req_valid(req_valid), .i_req_write(req_write), .i_req_addr(req_addr), .i_req_wdata(req_wdata),
        .o_req_ready(req_ready), .o_rsp_valid(rsp_valid), .o_rsp_data(rsp_data),
        .o_a(a), .o_d_out(d_out), .o_d_oe(d_oe), .i_d_in(c_d_in), .o_clk(phi), .o_rd_n(rd_n), .o_wr_n(wr_n),
        .o_cs_n(cs_n), .o_dir_e(dir_e), .o_rst_low(rst_low), .o_rst_done(rst_done));
    BtCmd #(.CLK_HZ(SIM_HZ60)) u_cmd (
        .i_clk(clk60), .i_rst(rst),
        .i_rx_valid(c_rx_valid), .i_rx_data(c_rx_data), .o_rx_ready(c_rx_ready),
        .o_tx_valid(c_tx_valid), .o_tx_data(c_tx_data), .i_tx_ready(c_tx_ready),
        .i_cart_det(cart_det), .i_switch_on(switch_on), .i_rst_in(slot_rst_n), .i_pwr_en(pwr_en),
        .i_legacy(legacy), .i_bus_ready(pw_ready && rst_done), .o_power_en(power_en), .o_busy(), .o_unlocked(),
        .o_cyc(cyc), .o_sample(sample), .o_wr_on(wr_on), .o_wr_off(wr_off),
        .o_static(st_en), .o_st_a(st_a), .o_st_ctl(st_ctl), .o_st_d(st_d), .i_d_seen(d_seen), .o_rst_force(rst_force),
        .o_req_valid(req_valid), .o_req_write(req_write), .o_req_addr(req_addr), .o_req_wdata(req_wdata),
        .i_req_ready(req_ready), .i_rsp_valid(rsp_valid), .i_rsp_data(rsp_data));

    // ---- slot / adapter ----
    wire slot_on = ctrl_oe;                       // newer board: lines valid while the slot is powered
    logic [7:0] t_d, t_d_out;
    logic t_d_oe, t_d_dir, t_d_oe_n, t_rst_drv, t_aud;
    wire chrom_drives = slot_on && !dir_e;        // Chromatic shifter towards the slot
    wire tgt_drives   = slot_on && t_d_dir && !t_d_oe_n;
    wire [7:0] slot_d = chrom_drives ? (d_oe ? d_out : 8'hFF) : tgt_drives ? (t_d_oe ? t_d_out : 8'hFF) : 8'hFF;
    assign c_d_in     = slot_d;
    assign t_d        = t_d_dir ? t_d_out : (slot_on ? slot_d : 8'h00);
    assign slot_rst_n = !(rst_low || (slot_on && t_rst_drv));

    CartTarget #(.CLK_HZ(SIM_HZ100), .AUD_DIV(50)) u_tgt (
        .i_clk(clk100), .i_rst(rst),
        .i_rx_valid(t_rx_valid), .i_rx_data(t_rx_data), .o_rx_ready(t_rx_ready),
        .o_tx_valid(t_tx_valid), .o_tx_data(t_tx_data), .i_tx_ready(t_tx_ready),
        .i_a(slot_on ? a : 16'h0), .i_rd_n(slot_on ? rd_n : 1'b0), .i_wr_n(slot_on ? wr_n : 1'b0),
        .i_cs_n(slot_on ? cs_n : 1'b0), .i_phi(slot_on ? phi : 1'b0), .i_rst_n(slot_on ? slot_rst_n : 1'b0),
        .i_d(t_d), .o_d(t_d_out), .o_d_oe(t_d_oe), .o_d_dir(t_d_dir), .o_d_oe_n(t_d_oe_n),
        .o_rst_drv(t_rst_drv), .o_aud(t_aud));

    initial n_contention = 0;
    always @(posedge clk100) if (chrom_drives && tgt_drives) begin
        n_contention <= n_contention + 1;
        if (n_contention < 5) $display("[bt] contention at %0t (a=%h)", $time, a);
    end
endmodule
