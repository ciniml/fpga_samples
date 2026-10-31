// Simulation stand-in for Ddr2PhyGw3a (ddr2_Ddr2PhyGw3a as a dependency, same ports): the slot vectors of
// Ddr2Ctrl go straight to the slot-level DDR2 model of rtl/ddr2/test (no
// OSER8 / IDES8, the pins are left alone). The model stops the simulation
// ($error) on any protocol violation.
`timescale 1ns/1ps
module ddr2_Ddr2PhyGw3a #(
    parameter int unsigned ROW_BITS  = 13,
    parameter int unsigned BANK_BITS = 2
) (
    input  var logic                 i_pclk,
    input  var logic                 i_fclk,
    input  var logic                 i_rst,
    input  var logic                 i_cke,
    input  var logic                 i_odt,
    input  var logic                 i_cs_n,
    input  var logic                 i_ras_n,
    input  var logic                 i_cas_n,
    input  var logic                 i_we_n,
    input  var logic [BANK_BITS-1:0] i_ba,
    input  var logic [ROW_BITS-1:0]  i_a,
    input  var logic [127:0]         i_dq_out,
    input  var logic [3:0]           i_dq_oe,
    input  var logic [15:0]          i_dqs_out,
    input  var logic [3:0]           i_dqs_oe,
    output var logic [127:0]         o_dq_in,
    output var logic [15:0]          o_dqs_in,
    output var logic                 o_ddr_ck,
    output var logic                 o_ddr_cke,
    output var logic                 o_ddr_odt,
    output var logic                 o_ddr_cs_n,
    output var logic                 o_ddr_ras_n,
    output var logic                 o_ddr_cas_n,
    output var logic                 o_ddr_we_n,
    output var logic [BANK_BITS-1:0] o_ddr_ba,
    output var logic [ROW_BITS-1:0]  o_ddr_a,
    inout  tri logic [15:0]          io_ddr_dq,
    inout  tri logic [1:0]           io_ddr_dqs
);
    parameter int T_INIT_PS = 20_000_000; // must match the top's DDR_T_INIT_PS in the test bench

    ddr2_model #(
        .ROW_BITS (ROW_BITS),
        .BANK_BITS(BANK_BITS),
        .CK_PS    (6000),
        .CL       (4),
        .T_INIT_PS(T_INIT_PS)
    ) mdl (
        .clk           (i_pclk),
        .rst           (i_rst),
        .rd_delay_slots(3'd3),
        .rd_odd_shift  (1'b0),
        .report        (1'b0),
        .cke           (i_cke),
        .cs_n          (i_cs_n),
        .ras_n         (i_ras_n),
        .cas_n         (i_cas_n),
        .we_n          (i_we_n),
        .ba            (i_ba),
        .a             (i_a),
        .dq_out        (i_dq_out),
        .dq_oe         (i_dq_oe),
        .dqs_out       (i_dqs_out),
        .dqs_oe        (i_dqs_oe),
        .dq_in         (o_dq_in),
        .dqs_in        (o_dqs_in),
        .errors        (),
        .ref_count     (),
        .wr_bursts     (),
        .rd_bursts     (),
        .init_done     ()
    );

    assign o_ddr_ck    = i_pclk;
    assign o_ddr_cke   = i_cke;
    assign o_ddr_odt   = i_odt;
    assign o_ddr_cs_n  = i_cs_n;
    assign o_ddr_ras_n = i_ras_n;
    assign o_ddr_cas_n = i_cas_n;
    assign o_ddr_we_n  = i_we_n;
    assign o_ddr_ba    = i_ba;
    assign o_ddr_a     = i_a;
endmodule
