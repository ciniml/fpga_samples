// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// The cartridge reader (CartPower + CartBus + CartCmd, as in eda/chromatic_cart_dump)
// with a gb_cart_model in the slot. Byte stream ports = USB EP1 OUT / IN.
`timescale 1ns/1ps
module cart_sim_top #(
    parameter int SIM_HZ   = 60000,  // clock rate the timers are scaled for (50 ms = 3000 clocks)
    parameter int CYCLE    = 16,
    parameter int MBC      = 5,
    parameter int ROM_CODE = 5,
    parameter bit MBC1M    = 0,
    parameter bit BAD_HDR  = 0,
    parameter bit LEGACY   = 0,
    parameter int RAM_CODE = 0,
    parameter int EEP_WORDS = 128
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       cart_det,
    input  logic       switch_on,
    input  logic       host_ok,
    input  logic       rx_valid,
    input  logic [7:0] rx_data,
    output logic       rx_ready,
    output logic       tx_valid,
    output logic [7:0] tx_data,
    input  logic       tx_ready,
    output int         n_writes,
    output int         n_violations,
    output int         n_ram_reads,
    output logic       ram_enabled
);
    logic legacy, pw_ready, pwr_en, ctrl_oe, drive_low, power_en;
    logic req_valid, req_write, req_ready, rsp_valid, rsp_reject, rst_done;
    logic [15:0] req_addr, a;
    logic [7:0] req_wdata, rsp_data, d_out, d_in;
    logic d_oe, phi, rd_n, wr_n, cs_n, dir_e, rst_low;
    logic ram_mode, ram_on, req_priv;

    CartPower #(.CLK_HZ(SIM_HZ)) u_pwr (
        .i_clk(clk), .i_rst(rst), .i_enable(power_en), .i_version_det(LEGACY),
        .o_legacy(legacy), .o_ready(pw_ready), .o_pwr_en(pwr_en), .o_ctrl_oe(ctrl_oe), .o_drive_low(drive_low));
    CartBus #(.CYCLE(CYCLE)) u_bus (
        .i_clk(clk), .i_rst(rst), .i_ready(pw_ready), .i_drive_low(drive_low),
        .i_ram_mode(ram_mode), .o_ram_on(ram_on),
        .i_req_valid(req_valid), .i_req_write(req_write), .i_req_addr(req_addr), .i_req_wdata(req_wdata),
        .i_req_priv(req_priv), .o_req_ready(req_ready), .o_rsp_valid(rsp_valid), .o_rsp_data(rsp_data), .o_rsp_reject(rsp_reject),
        .o_a(a), .o_d_out(d_out), .o_d_oe(d_oe), .i_d_in(d_in), .o_clk(phi), .o_rd_n(rd_n), .o_wr_n(wr_n),
        .o_cs_n(cs_n), .o_dir_e(dir_e), .o_rst_low(rst_low), .o_rst_done(rst_done));
    CartCmd #(.CLK_HZ(SIM_HZ)) u_cmd (
        .i_clk(clk), .i_rst(rst),
        .i_rx_valid(rx_valid), .i_rx_data(rx_data), .o_rx_ready(rx_ready),
        .o_tx_valid(tx_valid), .o_tx_data(tx_data), .i_tx_ready(tx_ready),
        .i_cart_det(cart_det), .i_switch_on(switch_on), .i_rst_in(!rst_low), .i_pwr_en(pwr_en),
        .i_legacy(legacy), .i_bus_ready(pw_ready && rst_done), .o_power_en(power_en),
        .i_host_ok(host_ok), .i_ram_on(ram_on), .o_ram_mode(ram_mode),
        .o_cart_det(), .o_busy(), .o_rejected(),
        .o_req_valid(req_valid), .o_req_write(req_write), .o_req_addr(req_addr), .o_req_wdata(req_wdata),
        .o_req_priv(req_priv), .i_req_ready(req_ready), .i_rsp_valid(rsp_valid), .i_rsp_data(rsp_data), .i_rsp_reject(rsp_reject));
    gb_cart_model #(.MBC(MBC), .ROM_CODE(ROM_CODE), .MBC1M(MBC1M), .BAD_HDR(BAD_HDR), .RAM_CODE(RAM_CODE), .EEP_WORDS(EEP_WORDS)) u_cart (
        .clk(clk), .rst(rst), .legacy(legacy), .pwr_en(pwr_en), .ctrl_oe(ctrl_oe), .drive_low_expected(drive_low), .ram_mode(ram_mode),
        .a(a), .clk_phi(phi), .rd_n(rd_n), .wr_n(wr_n), .cs_n(cs_n), .rst_low(rst_low), .dir_e(dir_e),
        .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .n_writes(n_writes), .n_violations(n_violations),
        .n_ram_reads(n_ram_reads), .ram_enabled(ram_enabled));
endmodule
