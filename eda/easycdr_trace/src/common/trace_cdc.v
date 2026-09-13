// Clock-domain-crossing helpers for the trace transmitter (family-independent).
//
//   trace_sync_bit    : N-stage flop synchroniser for W independent bits
//   trace_sync_pulse  : one-clock pulse from domain A to domain B (toggle + 2FF)
//   trace_reset_sync  : asynchronous assert / synchronous de-assert reset
//   trace_cdc_bus     : multi-bit quasi-static bus with a req/ack handshake
//                       (the destination copy changes atomically; rapid source
//                       changes are coalesced into the latest value)

module trace_sync_bit #(
    parameter STAGES = 2,
    parameter W      = 1
) (
    input  wire         clk,
    input  wire         rstn,
    input  wire [W-1:0] d,
    output wire [W-1:0] q
);
    reg [W-1:0] sr [0:STAGES-1];
    integer i;
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            for (i = 0; i < STAGES; i = i + 1) sr[i] <= {W{1'b0}};
        end else begin
            sr[0] <= d;
            for (i = 1; i < STAGES; i = i + 1) sr[i] <= sr[i-1];
        end
    end
    assign q = sr[STAGES-1];
endmodule

module trace_sync_pulse (
    input  wire sclk,
    input  wire srstn,
    input  wire i_pulse,   // one clock in sclk (pulses closer than ~4 dclk are merged)
    input  wire dclk,
    input  wire drstn,
    output wire o_pulse    // one clock in dclk
);
    reg       tgl;
    reg [2:0] s;
    always @(posedge sclk or negedge srstn)
        if (!srstn) tgl <= 1'b0;
        else if (i_pulse) tgl <= ~tgl;
    always @(posedge dclk or negedge drstn)
        if (!drstn) s <= 3'b000;
        else        s <= {s[1:0], tgl};
    assign o_pulse = s[2] ^ s[1];
endmodule

module trace_reset_sync (
    input  wire clk,
    input  wire arstn,     // asynchronous, active low
    output wire rstn       // asserted immediately, released after 2 clocks
);
    reg [1:0] r;
    always @(posedge clk or negedge arstn)
        if (!arstn) r <= 2'b00;
        else        r <= {r[0], 1'b1};
    assign rstn = r[1];
endmodule

module trace_cdc_bus #(
    parameter W = 8
) (
    input  wire         sclk,
    input  wire         srstn,
    input  wire [W-1:0] i_bus,
    input  wire         dclk,
    input  wire         drstn,
    output reg  [W-1:0] o_bus
);
    reg [2:0]   req_s;
    reg         ack;
    // source: hold the value while a transfer is in flight. The wide
    // compare is done per 8-bit chunk and registered twice (diff_c, diff_r):
    // the bus is quasi-static, so acting two cycles late is fine and it
    // keeps the path short on slow fabrics (GW1N @100MHz).
    localparam NCH = (W + 7) / 8;
    reg [W-1:0]   hold;
    reg           req;
    reg [2:0]     ack_s;
    reg [NCH-1:0] diff_c;
    reg           diff_r;
    wire          idle = (req == ack_s[2]);
    genvar gi;
    generate
        for (gi = 0; gi < NCH; gi = gi + 1) begin : g_ch
            localparam LO = gi * 8;
            localparam HI = (LO + 8 > W) ? W - 1 : LO + 7;
            always @(posedge sclk or negedge srstn)
                if (!srstn) diff_c[gi] <= 1'b0;
                else        diff_c[gi] <= (i_bus[HI:LO] != hold[HI:LO]);
        end
    endgenerate
    always @(posedge sclk or negedge srstn) begin
        if (!srstn) begin
            hold   <= {W{1'b0}};
            req    <= 1'b0;
            ack_s  <= 3'b000;
            diff_r <= 1'b0;
        end else begin
            ack_s  <= {ack_s[1:0], ack};
            diff_r <= |diff_c;
            if (idle && diff_r) begin
                hold <= i_bus;
                req  <= ~req;
            end
        end
    end
    // destination: capture when a new request arrives, then acknowledge
    always @(posedge dclk or negedge drstn) begin
        if (!drstn) begin
            req_s <= 3'b000;
            ack   <= 1'b0;
            o_bus <= {W{1'b0}};
        end else begin
            req_s <= {req_s[1:0], req};
            if (req_s[2] != ack) begin
                o_bus <= hold;
                ack   <= ~ack;
            end
        end
    end
endmodule
