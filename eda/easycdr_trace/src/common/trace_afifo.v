// Asynchronous FIFO (gray-code pointers, 2FF synchronised) for the trace
// record path: written in the sample clock domain, read in the link clock
// domain. Works with identical clocks as well. Read data is presented
// combinationally for the entry at the read pointer (first-word-fall-through);
// rd_en pops it. AW >= 2.
module trace_afifo #(
    parameter DW = 40,
    parameter AW = 4
) (
    input  wire          wclk,
    input  wire          wrstn,
    input  wire          wr_en,
    input  wire [DW-1:0] wr_data,
    output reg           wfull,

    input  wire          rclk,
    input  wire          rrstn,
    input  wire          rd_en,
    output wire [DW-1:0] rd_data,
    output reg           rempty
);
    // GW1N maps this to SSRAM (RAM16). GW5A builds it from flip-flops (the
    // syn_ramstyle hint had no effect there): 16 x 40 = 640 FF, acceptable.
    reg [DW-1:0] mem [0:(1<<AW)-1];

    // write side. wgray_inc = gray(wbin + 1) is kept in a register so the
    // full flag is a mux + compare (no adder on the path).
    reg  [AW:0] wbin, wgray, wgray_inc;
    reg  [AW:0] rgray_w1, rgray_w2;
    wire        wr_go   = wr_en & ~wfull;
    wire [AW:0] wbin_p2 = wbin + 2'd2;
    wire [AW:0] wgray_n = wr_go ? wgray_inc : wgray;
    wire [AW:0] rgray_wf = {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]};
    always @(posedge wclk or negedge wrstn) begin
        if (!wrstn) begin
            wbin      <= {(AW+1){1'b0}};
            wgray     <= {(AW+1){1'b0}};
            wgray_inc <= {{AW{1'b0}}, 1'b1};
            wfull     <= 1'b0;
            rgray_w1  <= {(AW+1){1'b0}};
            rgray_w2  <= {(AW+1){1'b0}};
        end else begin
            if (wr_go) begin
                wbin      <= wbin + 1'b1;
                wgray     <= wgray_inc;
                wgray_inc <= (wbin_p2 >> 1) ^ wbin_p2;
            end
            rgray_w1 <= rgray;
            rgray_w2 <= rgray_w1;
            wfull    <= (wgray_n == rgray_wf);
        end
    end
    always @(posedge wclk)
        if (wr_en & ~wfull) mem[wbin[AW-1:0]] <= wr_data;

    // read side (same structure)
    reg  [AW:0] rbin, rgray, rgray_inc;
    reg  [AW:0] wgray_r1, wgray_r2;
    wire        rd_go   = rd_en & ~rempty;
    wire [AW:0] rbin_p2 = rbin + 2'd2;
    wire [AW:0] rgray_n = rd_go ? rgray_inc : rgray;
    always @(posedge rclk or negedge rrstn) begin
        if (!rrstn) begin
            rbin      <= {(AW+1){1'b0}};
            rgray     <= {(AW+1){1'b0}};
            rgray_inc <= {{AW{1'b0}}, 1'b1};
            rempty    <= 1'b1;
            wgray_r1  <= {(AW+1){1'b0}};
            wgray_r2  <= {(AW+1){1'b0}};
        end else begin
            if (rd_go) begin
                rbin      <= rbin + 1'b1;
                rgray     <= rgray_inc;
                rgray_inc <= (rbin_p2 >> 1) ^ rbin_p2;
            end
            wgray_r1 <= wgray;
            wgray_r2 <= wgray_r1;
            rempty   <= (rgray_n == wgray_r2);
        end
    end
    assign rd_data = mem[rbin[AW-1:0]];
endmodule
