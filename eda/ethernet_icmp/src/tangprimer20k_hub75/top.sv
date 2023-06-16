/**
 * @file top.sv
 * @brief Top module for ethernet ICMP echo reply system.
 */
// Copyright 2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top(
    input wire clock,

    // Input button
    input wire button_s0,
    input wire button_s1,
    input wire button_s2,
    input wire button_s3,
    input wire button_s4,

    // Output LED
    output logic [5:0] led,

    // RMII PHY interface
    input  wire        rmii_txclk,
    input  wire  [1:0] rmii_rxd,
    input  wire        rmii_crs_dv,
    output logic [1:0] rmii_txd,
    output logic       rmii_txen,
    input  wire        rmii_mdio,
    output logic       rmii_mdc,
    output logic       rmii_rstn,

    // HUB75
    output logic       hub75io_clk,
    output logic [1:0] hub75io_r,
    output logic [1:0] hub75io_g,
    output logic [1:0] hub75io_b,
    output logic       hub75io_row_a,
    output logic       hub75io_row_b,
    output logic       hub75io_row_c,
    output logic       hub75io_row_d,
    output logic       hub75io_row_e,
    output logic       hub75io_lat,
    output logic       hub75io_oe
);

logic [2:0] reset_button = '1;
always_ff @(posedge rmii_txclk) begin
  reset_button <= {1'b0, reset_button[2:1]};
end

logic reset;
reset_seq reset_seq_ext(
  .clock(rmii_txclk),
  .reset_in(reset_button[0]),
  .reset_out(reset)
);

assign rmii_rstn = !reset;
assign rmii_mdc = 0;

logic [7:0] tx_saxis_tdata;
logic       tx_saxis_tvalid;
logic       tx_saxis_tready;
logic       tx_saxis_tlast;

logic [7:0] rx_maxis_tdata;
logic       rx_maxis_tvalid;
logic       rx_maxis_tready;
logic       rx_maxis_tlast;
logic       rx_maxis_tuser;

logic [7:0] gpio_in;
logic [71:0] gpio_out;
assign gpio_in = {3'b000, !button_s4, !button_s3, !button_s2, !button_s1, !button_s0};
assign led = gpio_out[5:0];

rmii_mac rmii_mac_inst (
  .tx_clock(rmii_txclk),
  .tx_reset(reset),
  .tx_rmii_d(rmii_txd),
  .tx_rmii_en(rmii_txen),
  .rx_clock(rmii_txclk),
  .rx_reset(reset),
  .rx_rmii_d(rmii_rxd),
  .rx_rmii_dv(rmii_crs_dv),
  .tx_saxis_bypass_tdata(0),
  .tx_saxis_bypass_tvalid(0),
  .tx_saxis_bypass_tready(),
  .tx_saxis_bypass_tlast(0),
  .*
);

EthernetSystem ethernet_system_isnt (
  .clock(rmii_txclk),
  .aresetn(!reset),
  .in_tdata (rx_maxis_tdata),
  .in_tvalid(rx_maxis_tvalid),
  .in_tready(rx_maxis_tready),
  .in_tlast (rx_maxis_tlast),
  .out_tdata (tx_saxis_tdata),
  .out_tvalid(tx_saxis_tvalid),
  .out_tready(tx_saxis_tready),
  .out_tlast (tx_saxis_tlast),
  .gpio_in(gpio_in),
  .gpio_out(gpio_out),
  .hub75io_row_a(hub75io_row_a),
  .hub75io_row_b(hub75io_row_b),
  .hub75io_row_c(hub75io_row_c),
  .hub75io_row_d(hub75io_row_d),
  .hub75io_row_e(hub75io_row_e),
  .hub75io_r(hub75io_r),
  .hub75io_g(hub75io_g),
  .hub75io_b(hub75io_b),
  .hub75io_oe(hub75io_oe),
  .hub75io_lat(hub75io_lat),
  .hub75io_clk(hub75io_clk)
);

endmodule
`default_nettype wire