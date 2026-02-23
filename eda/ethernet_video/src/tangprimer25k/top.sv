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

    // Output LED
    output logic [5:0] led,

    // RMII PHY interface
    input  wire        rmii_txclk,
    input  wire  [1:0] rmii_rxd,
    input  wire        rmii_crs_dv,
    output logic [1:0] rmii_txd,
    output logic       rmii_txen,
    output logic       rmii_rstn,

    // I2S Master
    //output logic out_bclk,
    //output logic out_data,
    //output logic out_ws,
    //output logic out_pa_en,

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
    output logic       hub75io_oe,

    // Debug
    output logic out_bclk_dbg,
    output logic out_data_dbg,
    output logic out_ws_dbg,
    output logic dbg_buffering,
    output logic dbg_probeOut
);

logic rmii_reset;
logic main_clock;
logic main_clock_lock;
logic main_reset;

// dummy
logic out_bclk;
logic out_data;
logic out_ws;
logic out_pa_en;

// blink
localparam int MAIN_CLOCK_HZ = 36_000_000;
logic blink = 0;
logic [$clog2(MAIN_CLOCK_HZ)-1:0] blink_counter;
localparam int RMII_CLOCK_HZ = 50_000_000;
logic blink_rmii = 0;
logic [$clog2(RMII_CLOCK_HZ)-1:0] blink_rmii_counter;

reset_seq reset_seq_ext(
  .clock(rmii_txclk),
  .reset_in(!main_clock_lock),
  .reset_out(rmii_reset)
);
reset_seq reset_seq_main(
  .clock(main_clock),
  .reset_in(!main_clock_lock),
  .reset_out(main_reset)
);

// Generate main clock (36MHz)
// 36MHz is suitable clock for generate 48kHz audio clock, and can be generated from 27MHz input clock.
gowin_pll_main gowin_pll_main_inst(
    .clkout0(main_clock),      //output clkout
    .lock   (main_clock_lock), //output lock
    .clkin  (clock)            //input clkin
);

// blink logic
always_ff @(posedge main_clock) begin
    if( main_reset ) begin
        blink_counter <= 0;
        blink <= 1'b0;
    end
    else begin
        if( blink_counter < MAIN_CLOCK_HZ/2 - 1 ) begin
            blink_counter <= blink_counter + 1;
        end
        else begin
            blink_counter <= 0;
            blink <= !blink;
        end
    end
end
// RMII blink logic
always_ff @(posedge rmii_txclk) begin
    if( rmii_reset ) begin
        blink_rmii_counter <= 0;
        blink_rmii <= 1'b0;
    end
    else begin
        if( blink_rmii_counter < RMII_CLOCK_HZ/2 - 1 ) begin
            blink_rmii_counter <= blink_rmii_counter + 1;
        end
        else begin
            blink_rmii_counter <= 0;
            blink_rmii <= !blink_rmii;
        end
    end
end

assign rmii_rstn = !main_reset; // DO NOT connect any rmii_txclk domain signal to PHY reset. PHY does not output clock while reset.

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
assign gpio_in = {6'b000000, !button_s1, !button_s0};
assign led = {gpio_out[3:0], blink_rmii, blink};

rmii_mac rmii_mac_inst (
  .tx_clock(rmii_txclk),
  .tx_reset(rmii_reset),
  .tx_rmii_d(rmii_txd),
  .tx_rmii_en(rmii_txen),
  .rx_clock(rmii_txclk),
  .rx_reset(rmii_reset),
  .rx_rmii_d(rmii_rxd),
  .rx_rmii_dv(rmii_crs_dv),
  .tx_saxis_bypass_tdata(0),
  .tx_saxis_bypass_tvalid(0),
  .tx_saxis_bypass_tready(),
  .tx_saxis_bypass_tlast(0),
  .*
);

EthernetVideoSystem ethernet_video_system_inst (
  .clock(main_clock),
  .aresetn(!main_reset),
  
  .rmii_clock(rmii_txclk),
  .rmii_reset(rmii_reset),
  
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
  
  .out_bclk(out_bclk),
  .out_data(out_data),
  .out_ws(out_ws),
  
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
  .hub75io_clk(hub75io_clk),
  
  .dbg_buffering(dbg_buffering),
  .dbg_probeOut(dbg_probeOut)
);

// Connect I2S signals for debugging
assign out_bclk_dbg = out_bclk;
assign out_data_dbg = out_data;
assign out_ws_dbg   = out_ws;

// Enable phone amplifier
assign out_pa_en = 1'b1;

endmodule
`default_nettype wire