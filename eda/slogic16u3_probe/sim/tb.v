// Co-simulation bench for host/slogic_probe.py --sim: reads "<n> <tms><tdi>..." lines on
// stdin, clocks them into top.v through a behavioural GW_JTAG (TAP + IDCODE/STATUS/
// a fake SAMPLE register), prints the TDO bits back. The board model drives a few pins.
`timescale 1ns/1ps
module tb;
    reg tck = 1'b1, tms = 1'b1, tdi = 1'b0;
    wire tdo;
    wire [`PROBE_N_IO-1:0] io;
`ifdef PROBE_MIPI_DPHY
    wire [9:0] m0;   // CKP CKN D0P D0N D1P D1N D2P D2N D3P D3N
    top dut (.tck_pad_i(tck), .tms_pad_i(tms), .tdi_pad_i(tdi), .tdo_pad_o(tdo), .io(io),
             .m0_ck_p(m0[0]), .m0_ck_n(m0[1]), .m0_d0_p(m0[2]), .m0_d0_n(m0[3]), .m0_d1_p(m0[4]),
             .m0_d1_n(m0[5]), .m0_d2_p(m0[6]), .m0_d2_n(m0[7]), .m0_d3_p(m0[8]), .m0_d3_n(m0[9]));
    // board model for M0: D1P pulled up, D1N pulled down, the rest floating -> read as 0
    pullup   (m0[4]);
    pulldown (m0[5]);
`else
    top dut (.tck_pad_i(tck), .tms_pad_i(tms), .tdi_pad_i(tdi), .tdo_pad_o(tdo), .io(io));
`endif

    // internal weak pull of the build
    genvar gi;
    generate
        for (gi = 0; gi < `PROBE_N_IO; gi = gi + 1) begin : g_pull
            if (`PROBE_PULL == 2'd1) begin : u
                pullup (io[gi]);
            end else if (`PROBE_PULL == 2'd2) begin : d
                pulldown (io[gi]);
            end
        end
    endgenerate

    // board model
    reg osc25 = 1'b0;
    always #20 osc25 = ~osc25;
`ifdef IDX_F13
    assign io[`IDX_F13] = osc25;               // oscillator
`endif
`ifdef IDX_E14
    assign io[`IDX_E14] = 1'b1;                // UART RX idle from some driver
`endif
`ifdef IDX_J12
    assign io[`IDX_J12] = 1'b0;                // strap / driven low
`endif
`ifdef IDX_P14
    assign io[`IDX_P14] = osc25;               // CH3 with a signal attached
`endif
`ifdef IDX_N1
    assign io[`IDX_N1] = 1'b1;                 // MODE1 strap
`endif

    // stdin driver
    integer n, i, r, c;
    reg tdo_s;
    initial begin
        #200;
        forever begin
            r = $fscanf(32'h8000_0000, "%d", n);
            if (r != 1 || n == 0) $finish;
            c = $fgetc(32'h8000_0000);
            for (i = 0; i < n; i = i + 1) begin
                c = $fgetc(32'h8000_0000);
                tms = (c == "1");
                c = $fgetc(32'h8000_0000);
                tdi = (c == "1");
                // rust-dap bit-bang order: TMS/TDI change while TCK is still high,
                // then TCK low, TDO read, TCK high (the design oversamples TCK)
                #2;
                tck = 1'b0;
                #200;
                tdo_s = (tdo === 1'b1);
                tck = 1'b1;
                #200;
                $write("%0d", tdo_s);
            end
            $write("\n");
            $fflush;
        end
    end
endmodule

module IBUF (input I, output O); assign O = I; endmodule
module OBUF (input I, output O); assign O = I; endmodule
module OSCA (output reg OSCOUT, input OSCEN);
    parameter FREQ_DIV = 100;
    initial OSCOUT = 1'b0;
    always #9.5 OSCOUT = ~OSCOUT;
endmodule

module GW_JTAG (
    input tck_pad_i, input tms_pad_i, input tdi_pad_i, output reg tdo_pad_o,
    output tck_o, output tdi_o, output test_logic_reset_o,
    output run_test_idle_er1_o, output run_test_idle_er2_o,
    output shift_dr_capture_dr_o, output pause_dr_o, output update_dr_o,
    output enable_er1_o, output enable_er2_o,
    input tdo_er1_i, input tdo_er2_i
);
    localparam TLR = 0, RTI = 1, SDS = 2, CDR = 3, SDR = 4, E1D = 5, PDR = 6, E2D = 7, UDR = 8,
               SIS = 9, CIR = 10, SIR = 11, E1I = 12, PIR = 13, E2I = 14, UIR = 15;
    localparam BSR_LEN = 3 * `PROBE_N_IO + 7;
    reg [3:0] st = TLR;
    reg [7:0] ir = 8'h11, ir_sr = 8'h00;
    reg [31:0] r32 = 0;
    reg byp = 1'b0;
    reg [BSR_LEN-1:0] bsr = 0;
    wire [BSR_LEN-1:0] bsr_cap;

    // fake cell order: 7 constant cells, then per pin (reversed) {oe, out, in}
    assign bsr_cap[6:0] = 7'b1010011;
    genvar gi;
    generate
        for (gi = 0; gi < `PROBE_N_IO; gi = gi + 1) begin : g_cell
            localparam integer B = 7 + 3 * (`PROBE_N_IO - 1 - gi);
            assign bsr_cap[B]     = (tb.io[gi] === 1'b1);
            assign bsr_cap[B + 1] = tb.dut.g_pin[gi].out_w;
            assign bsr_cap[B + 2] = tb.dut.g_pin[gi].oe_w;
        end
    endgenerate

    assign tck_o = tck_pad_i;
    assign tdi_o = tdi_pad_i;
    assign test_logic_reset_o = (st == TLR);
    assign run_test_idle_er1_o = (st == RTI) && ir == 8'h42;
    assign run_test_idle_er2_o = (st == RTI) && ir == 8'h43;
    assign shift_dr_capture_dr_o = (st == CDR || st == SDR);
    assign pause_dr_o = (st == PDR);
    assign update_dr_o = (st == UDR);
    assign enable_er1_o = (ir == 8'h42);
    assign enable_er2_o = (ir == 8'h43);

    always @(posedge tck_pad_i) begin
        case (st)
            CIR: ir_sr <= 8'b0000_0001;
            SIR: ir_sr <= {tdi_pad_i, ir_sr[7:1]};
            UIR: ir <= ir_sr;
            TLR: ir <= 8'h11;
            CDR: case (ir)
                     8'h11: r32 <= 32'h0001681B;
                     8'h13: r32 <= 32'h00000000;
                     8'h41: r32 <= 32'h0001F020;
                     8'h01: bsr <= bsr_cap;
                     default: byp <= 1'b0;
                 endcase
            SDR: case (ir)
                     8'h11, 8'h13, 8'h41: r32 <= {tdi_pad_i, r32[31:1]};
                     8'h01: bsr <= {tdi_pad_i, bsr[BSR_LEN-1:1]};
                     default: byp <= tdi_pad_i;
                 endcase
            default: ;
        endcase
        case (st)
            TLR: st <= tms_pad_i ? TLR : RTI;
            RTI: st <= tms_pad_i ? SDS : RTI;
            SDS: st <= tms_pad_i ? SIS : CDR;
            CDR: st <= tms_pad_i ? E1D : SDR;
            SDR: st <= tms_pad_i ? E1D : SDR;
            E1D: st <= tms_pad_i ? UDR : PDR;
            PDR: st <= tms_pad_i ? E2D : PDR;
            E2D: st <= tms_pad_i ? UDR : SDR;
            UDR: st <= tms_pad_i ? SDS : RTI;
            SIS: st <= tms_pad_i ? TLR : CIR;
            CIR: st <= tms_pad_i ? E1I : SIR;
            SIR: st <= tms_pad_i ? E1I : SIR;
            E1I: st <= tms_pad_i ? UIR : PIR;
            PIR: st <= tms_pad_i ? E2I : PIR;
            E2I: st <= tms_pad_i ? UIR : SIR;
            UIR: st <= tms_pad_i ? SDS : RTI;
        endcase
    end

    always @(negedge tck_pad_i) begin
        if (st == SIR)
            tdo_pad_o <= ir_sr[0];
        else if (st == SDR)
            case (ir)
                8'h11, 8'h13, 8'h41: tdo_pad_o <= r32[0];
                8'h01: tdo_pad_o <= bsr[0];
                8'h42: tdo_pad_o <= tdo_er1_i;
                8'h43: tdo_pad_o <= tdo_er2_i;
                default: tdo_pad_o <= byp;
            endcase
        else
            tdo_pad_o <= 1'bz;
    end
endmodule

// LP-mode model of the hard D-PHY: LPRX reads the pad, LPTX drives both pads of an enabled lane
module MIPI_DPHY (
    inout CK_P, CK_N, D0_P, D0_N, D1_P, D1_N, D2_P, D2_N, D3_P, D3_N,
    output DI_LPRXCK_P, DI_LPRXCK_N, DI_LPRX0_P, DI_LPRX0_N, DI_LPRX1_P, DI_LPRX1_N,
    output DI_LPRX2_P, DI_LPRX2_N, DI_LPRX3_P, DI_LPRX3_N,
    input DO_LPTXCK_P, DO_LPTXCK_N, DO_LPTX0_P, DO_LPTX0_N, DO_LPTX1_P, DO_LPTX1_N,
    input DO_LPTX2_P, DO_LPTX2_N, DO_LPTX3_P, DO_LPTX3_N,
    input LPTXEN_LNCK, LPTXEN_LN0, LPTXEN_LN1, LPTXEN_LN2, LPTXEN_LN3,
    input LPRX_EN_CK, LPRX_EN_D0, LPRX_EN_D1, LPRX_EN_D2, LPRX_EN_D3,
    input HSRX_EN_CK, HSRX_EN_D0, HSRX_EN_D1, HSRX_EN_D2, HSRX_EN_D3,
    input HSTXEN_LN0, HSTXEN_LN1, HSTXEN_LN2, HSTXEN_LN3, HSTXEN_LNCK,
    input PWRON_RX, PWRON_TX, RESET, RX_DRST_N, TX_DRST_N
);
    assign CK_P = LPTXEN_LNCK ? DO_LPTXCK_P : 1'bz;  assign CK_N = LPTXEN_LNCK ? DO_LPTXCK_N : 1'bz;
    assign D0_P = LPTXEN_LN0 ? DO_LPTX0_P : 1'bz;    assign D0_N = LPTXEN_LN0 ? DO_LPTX0_N : 1'bz;
    assign D1_P = LPTXEN_LN1 ? DO_LPTX1_P : 1'bz;    assign D1_N = LPTXEN_LN1 ? DO_LPTX1_N : 1'bz;
    assign D2_P = LPTXEN_LN2 ? DO_LPTX2_P : 1'bz;    assign D2_N = LPTXEN_LN2 ? DO_LPTX2_N : 1'bz;
    assign D3_P = LPTXEN_LN3 ? DO_LPTX3_P : 1'bz;    assign D3_N = LPTXEN_LN3 ? DO_LPTX3_N : 1'bz;
    assign DI_LPRXCK_P = (CK_P === 1'b1); assign DI_LPRXCK_N = (CK_N === 1'b1);
    assign DI_LPRX0_P = (D0_P === 1'b1);  assign DI_LPRX0_N = (D0_N === 1'b1);
    assign DI_LPRX1_P = (D1_P === 1'b1);  assign DI_LPRX1_N = (D1_N === 1'b1);
    assign DI_LPRX2_P = (D2_P === 1'b1);  assign DI_LPRX2_N = (D2_N === 1'b1);
    assign DI_LPRX3_P = (D3_P === 1'b1);  assign DI_LPRX3_N = (D3_N === 1'b1);
endmodule
