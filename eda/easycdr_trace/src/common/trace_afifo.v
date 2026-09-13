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
    reg [DW-1:0] mem [0:(1<<AW)-1];

    // write side
    reg  [AW:0] wbin, wgray;
    reg  [AW:0] rgray_w1, rgray_w2;
    wire [AW:0] wbin_n  = wbin + {{AW{1'b0}}, (wr_en & ~wfull)};
    wire [AW:0] wgray_n = (wbin_n >> 1) ^ wbin_n;
    always @(posedge wclk or negedge wrstn) begin
        if (!wrstn) begin
            wbin     <= {(AW+1){1'b0}};
            wgray    <= {(AW+1){1'b0}};
            wfull    <= 1'b0;
            rgray_w1 <= {(AW+1){1'b0}};
            rgray_w2 <= {(AW+1){1'b0}};
        end else begin
            wbin     <= wbin_n;
            wgray    <= wgray_n;
            rgray_w1 <= rgray;
            rgray_w2 <= rgray_w1;
            wfull    <= (wgray_n == {~rgray_w2[AW:AW-1], rgray_w2[AW-2:0]});
        end
    end
    always @(posedge wclk)
        if (wr_en & ~wfull) mem[wbin[AW-1:0]] <= wr_data;

    // read side
    reg  [AW:0] rbin, rgray;
    reg  [AW:0] wgray_r1, wgray_r2;
    wire [AW:0] rbin_n  = rbin + {{AW{1'b0}}, (rd_en & ~rempty)};
    wire [AW:0] rgray_n = (rbin_n >> 1) ^ rbin_n;
    always @(posedge rclk or negedge rrstn) begin
        if (!rrstn) begin
            rbin     <= {(AW+1){1'b0}};
            rgray    <= {(AW+1){1'b0}};
            rempty   <= 1'b1;
            wgray_r1 <= {(AW+1){1'b0}};
            wgray_r2 <= {(AW+1){1'b0}};
        end else begin
            rbin     <= rbin_n;
            rgray    <= rgray_n;
            wgray_r1 <= wgray;
            wgray_r2 <= wgray_r1;
            rempty   <= (rgray_n == wgray_r2);
        end
    end
    assign rd_data = mem[rbin[AW-1:0]];
endmodule
