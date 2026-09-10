// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file rtl8201_init.sv
 * @brief Reset + MDIO bring-up of the RTL8201 PHY on the Tang Primer 20K dock.
 *
 * The dock's RTL8201 drives plain CRS on its CRS/CRS_DV pin until it is
 * told otherwise, so an RMII MAC sees link-up but never a valid frame.
 * This block reproduces the vendor example (sipeed/TangPrimer-20K-example,
 * Ethernet/verilog_UDP): hold PHY reset low, release it, then over MDIO
 * (PHY address 1, MDC ~1MHz) write
 *     reg 31 <= 0x0007   (select page 7)
 *     reg 16 <= 0x0FFE   (RMII mode setting: CRS_DV on the CRS pin, ...)
 *     reg 31 <= 0x0000   (back to page 0)
 * Runs entirely on the crystal clock so it never depends on the RMII
 * reference clock, which the PHY stops while it is held in reset.
 */
`default_nettype none
module rtl8201_init #(
    parameter int CLK_HZ   = 27_000_000,
    parameter logic [4:0] PHY_ADDR = 5'd1
) (
    input  wire  clk,
    output logic phy_rstn,
    output logic mdc,
    inout  wire  mdio,
    output logic done
);
    localparam int MDC_HALF = CLK_HZ / 2_000_000;   // ~1MHz MDC
    localparam int RST_CYC  = CLK_HZ / 50;          // 20ms reset low
    localparam int WAIT_CYC = CLK_HZ / 50;          // 20ms after release

    // clause-22 write frames, MSB first: 32 preamble, ST=01, OP=01, PHYAD, REGAD, TA=10, DATA
    function automatic logic [63:0] frame(input logic [4:0] reg_addr, input logic [15:0] data);
        return {32'hFFFF_FFFF, 2'b01, 2'b01, PHY_ADDR, reg_addr, 2'b10, data};
    endfunction
    localparam int NFRAMES = 3;
    logic [63:0] frames [0:NFRAMES-1];
    assign frames[0] = frame(5'd31, 16'h0007);
    assign frames[1] = frame(5'd16, 16'h0FFE);
    assign frames[2] = frame(5'd31, 16'h0000);

    typedef enum logic [2:0] { Rst, Wait, Shift, Gap, Done } St;
    St st = Rst;
    logic [31:0] cnt = 0;
    logic [$clog2(MDC_HALF)+1:0] div = 0;
    logic [1:0] fi = 0;      // frame index
    logic [6:0] bi = 0;      // bit index 0..63
    logic mdio_o = 1, mdio_oe = 0;

    assign mdio = mdio_oe ? mdio_o : 1'bz;
    assign done = (st == Done);

    always_ff @(posedge clk) begin
        case (st)
            Rst: begin
                phy_rstn <= 1'b0; mdc <= 1'b0; mdio_oe <= 1'b0;
                if (cnt == RST_CYC) begin cnt <= 0; st <= Wait; end
                else cnt <= cnt + 1;
            end
            Wait: begin
                phy_rstn <= 1'b1;
                if (cnt == WAIT_CYC) begin
                    cnt <= 0; fi <= 0; bi <= 0; div <= 0;
                    mdio_oe <= 1'b1; mdio_o <= frames[0][63];
                    st <= Shift;
                end else cnt <= cnt + 1;
            end
            Shift: begin
                // mdio changes on the falling edge of mdc; sampled on the rising edge
                if (div == MDC_HALF - 1) begin
                    div <= 0;
                    mdc <= ~mdc;
                    if (mdc) begin // falling edge: present the next bit
                        if (bi == 7'd63) begin
                            bi <= 0; mdio_oe <= 1'b0; cnt <= 0;
                            st <= Gap;
                        end else begin
                            bi <= bi + 1;
                            mdio_o <= frames[fi][63 - (bi + 1)];
                        end
                    end
                end else div <= div + 1;
            end
            Gap: begin
                // a few idle MDC periods between frames (bus released)
                if (div == MDC_HALF - 1) begin
                    div <= 0; mdc <= ~mdc;
                    if (mdc) begin
                        if (cnt == 8) begin
                            cnt <= 0;
                            if (fi == NFRAMES - 1) st <= Done;
                            else begin
                                fi <= fi + 1; mdio_oe <= 1'b1;
                                mdio_o <= frames[fi + 1][63];
                                st <= Shift;
                            end
                        end else cnt <= cnt + 1;
                    end
                end else div <= div + 1;
            end
            Done: begin
                mdc <= 1'b0; mdio_oe <= 1'b0; phy_rstn <= 1'b1;
            end
            default: st <= Rst;
        endcase
    end
endmodule
`default_nettype wire
