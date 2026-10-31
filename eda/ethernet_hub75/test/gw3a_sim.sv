// Simulation stand-ins for the GW3A primitives / IP used by the
// DK_LED-RXCARD top (Gowin ships no model of GMT_DB):
//   pllb_hub75  125 MHz, 125 MHz + 270°, 50 MHz, 333.3 MHz, locked after 1 us
//   CLKDIV      HCLKIN / DIV_MODE (2, 4, 8)
//   IDDR / ODDR behaviour of the GW3A prim_sim.v models (without GSR)
//   IODELAY     zero delay
//   GMT_DB      UG311: 2 × 32 × 32 bit buffers per component, rows written
//               by WADDR, columns read by RADDR one clock later
`timescale 1ns/1ps
module pllb_hub75 (output logic lock, output logic clkout0, output logic clkout1,
                   output logic clkout2, output logic clkout3, input logic clkin);
    initial begin
        clkout0 = 1'b0;
        forever #4 clkout0 = ~clkout0;
    end
    initial begin
        clkout1 = 1'b0;
        #6;
        forever #4 clkout1 = ~clkout1;
    end
    initial begin
        clkout2 = 1'b0;
        forever #10 clkout2 = ~clkout2;
    end
    initial begin
        clkout3 = 1'b0;
        forever #1.5 clkout3 = ~clkout3;
    end
    initial begin
        lock = 1'b0;
        #1000 lock = 1'b1;
    end
endmodule

module CLKDIV (output logic CLKOUT, input logic CALIB, input logic HCLKIN, input logic RESETN);
    parameter DIV_MODE = "2";
    localparam int N = (DIV_MODE == "8") ? 8 : (DIV_MODE == "4") ? 4 : 2;
    int cnt = 0;
    initial CLKOUT = 1'b0;
    always @(posedge HCLKIN) begin
        if (cnt == N / 2 - 1) begin
            cnt    <= 0;
            CLKOUT <= ~CLKOUT;
        end else
            cnt <= cnt + 1;
    end
endmodule

module IDDR (output logic Q0, output logic Q1, input logic D, input logic CLK);
    parameter Q0_INIT = 1'b0;
    parameter Q1_INIT = 1'b0;
    logic p = 1'b0, n = 1'b0;
    initial begin
        Q0 = 1'b0;
        Q1 = 1'b0;
    end
    always @(posedge CLK) p <= D;
    always @(negedge CLK) n <= D;
    always @(posedge CLK) begin
        Q0 <= p;
        Q1 <= n;
    end
endmodule

module ODDR (output logic Q0, output logic Q1, input logic D0, input logic D1, input logic TX,
             input logic CLK);
    parameter TXCLK_POL = 1'b0;
    parameter INIT = 1'b0;
    logic d0_0 = 0, d0_1 = 0, d0_2 = 0, d1_0 = 0, d1_1 = 0, d1_2 = 0;
    always @(posedge CLK) begin
        d0_0 <= D0;
        d1_0 <= D1;
        d0_1 <= d0_0;
        d1_1 <= d1_0;
        d1_2 <= d1_1;
    end
    always @(negedge CLK) d0_2 <= d0_1;
    assign Q0 = CLK ? d0_2 : d1_2;
    assign Q1 = 1'b0;
endmodule

module IODELAY (output logic DO, output logic DF, input logic DI, input logic SDTAP,
                input logic VALUE, input logic [7:0] DLYSTEP);
    parameter integer C_STATIC_DLY = 0;
    parameter DYN_DLY_EN = "FALSE";
    parameter ADAPT_EN = "FALSE";
    assign DO = DI;
    assign DF = 1'b0;
endmodule

module GMT_DB (
    input  logic        WCLK, WCE, RCLK, RCE,
    input  logic        WEN0, WEN1, WEN2, WEN3,
    input  logic        RSTN,
    input  logic [5:0]  WADDR, RADDR,
    input  logic [31:0] WDATA0, WDATA1, WDATA2, WDATA3,
    input  logic        GSRN, CFGRSTN, MDCLK,
    input  logic [7:0]  MDWDATA,
    input  logic        MDAINC,
    input  logic [1:0]  MDOPC,
    input  logic        MD1BITM,
    output logic [31:0] RDATA0, RDATA1, RDATA2, RDATA3,
    output logic [7:0]  MDRDATA
);
    parameter WADDR_REMAP_EN = 1'b0;
    parameter COMP_EN = 4'b0000;
    logic [31:0] arr [4][2][32];
    wire  [3:0]  wen = {WEN3, WEN2, WEN1, WEN0};
    logic [31:0] wdata [4];
    assign wdata[0] = WDATA0;
    assign wdata[1] = WDATA1;
    assign wdata[2] = WDATA2;
    assign wdata[3] = WDATA3;
    logic [31:0] rdata [4];

    always @(posedge WCLK)
        if (WCE)
            for (int c = 0; c < 4; c++)
                if (wen[c] && COMP_EN[c]) arr[c][WADDR[5]][WADDR[4:0]] <= wdata[c];

    // column RADDR[4:0]: bit i = element of row i
    always @(posedge RCLK)
        if (RCE)
            for (int c = 0; c < 4; c++)
                for (int i = 0; i < 32; i++) rdata[c][i] <= arr[c][RADDR[5]][i][RADDR[4:0]];

    assign RDATA0 = rdata[0];
    assign RDATA1 = rdata[1];
    assign RDATA2 = rdata[2];
    assign RDATA3 = rdata[3];
    assign MDRDATA = 8'h00;
endmodule
