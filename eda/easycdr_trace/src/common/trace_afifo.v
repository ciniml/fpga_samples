// Asynchronous FIFO (gray-code pointers, 2FF synchronised) for the trace
// record path: written in the sample clock domain, read in the link clock
// domain. Works with identical clocks as well. First-word-fall-through:
// rd_data is valid while !rempty and rd_en pops it. The memory is read
// synchronously into a prefetch register (the only form a block RAM can
// implement - GW5A has no distributed RAM, an asynchronous read would be
// built from flip-flops), so it maps to SDPB / RAM16SDP. AW >= 2.
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
    output reg  [DW-1:0] rd_data,
    output wire          rempty
);
    // small arrays are otherwise flattened into flip-flops on GW5A
    reg [DW-1:0] mem [0:(1<<AW)-1] /* synthesis syn_ramstyle = "block_ram" */;

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

    // read side (same pointer structure). mempty = memory empty; the entry
    // at the read pointer is fetched into rd_data whenever that register is
    // free (or being popped), so rd_data/rempty behave first-word-fall-through.
    reg  [AW:0] rbin, rgray, rgray_inc;
    reg  [AW:0] wgray_r1, wgray_r2;
    reg         mempty, ovalid;
    wire        fetch   = ~mempty & (~ovalid | rd_en);
    wire [AW:0] rbin_p2 = rbin + 2'd2;
    wire [AW:0] rgray_n = fetch ? rgray_inc : rgray;
    assign rempty = ~ovalid;
    always @(posedge rclk or negedge rrstn) begin
        if (!rrstn) begin
            rbin      <= {(AW+1){1'b0}};
            rgray     <= {(AW+1){1'b0}};
            rgray_inc <= {{AW{1'b0}}, 1'b1};
            mempty    <= 1'b1;
            ovalid    <= 1'b0;
            wgray_r1  <= {(AW+1){1'b0}};
            wgray_r2  <= {(AW+1){1'b0}};
        end else begin
            if (fetch) begin
                rbin      <= rbin + 1'b1;
                rgray     <= rgray_inc;
                rgray_inc <= (rbin_p2 >> 1) ^ rbin_p2;
                ovalid    <= 1'b1;
            end else if (rd_en) begin
                ovalid    <= 1'b0;
            end
            wgray_r1 <= wgray;
            wgray_r2 <= wgray_r1;
            mempty   <= (rgray_n == wgray_r2);
        end
    end
    // synchronous read port (block-RAM friendly, no reset)
    always @(posedge rclk)
        if (fetch) rd_data <= mem[rbin[AW-1:0]];
endmodule
