// Re-frames the {K flag, byte} word stream from the EasyCDR receiver into
// trace records: [K28.1][ts LSB..MSB][data LSB..MSB].
// K28.5 commas and K28.3 fillers interleaved inside a record are ignored;
// K28.1 restarts a record, K28.2 (overflow marker) is flagged.
module trace_rx_decoder #(
    parameter WIDTH   = 16,
    parameter TS_BITS = 24
) (
    input  wire               clk,
    input  wire               rst,       // active high
    input  wire               in_valid,  // aligned word strobe
    input  wire [8:0]         in_word,   // {K flag, byte}
    output reg                rec_valid,
    output reg  [TS_BITS-1:0] rec_ts,
    output reg  [WIDTH-1:0]   rec_data,
    output reg                ovf_seen   // pulse on K28.2
);
    localparam REC_BYTES = (TS_BITS + WIDTH) / 8;
    localparam REC_BITS  = TS_BITS + WIDTH;
    localparam [7:0] K28_1 = 8'h3c;
    localparam [7:0] K28_2 = 8'h5c;

    reg                active;
    reg [7:0]          idx;
    reg [REC_BITS-1:0] acc;     // {data, ts}

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active    <= 1'b0;
            idx       <= 8'd0;
            acc       <= {REC_BITS{1'b0}};
            rec_valid <= 1'b0;
            rec_ts    <= {TS_BITS{1'b0}};
            rec_data  <= {WIDTH{1'b0}};
            ovf_seen  <= 1'b0;
        end else begin
            rec_valid <= 1'b0;
            ovf_seen  <= 1'b0;
            if (in_valid) begin
                if (in_word[8]) begin
                    if (in_word[7:0] == K28_1) begin
                        active <= 1'b1;
                        idx    <= 8'd0;
                    end else if (in_word[7:0] == K28_2) begin
                        ovf_seen <= 1'b1;
                    end
                    // other K codes (comma / filler): ignore
                end else if (active) begin
                    acc[idx*8 +: 8] <= in_word[7:0];
                    if (idx == REC_BYTES-1) begin
                        active    <= 1'b0;
                        rec_valid <= 1'b1;
                        rec_ts    <= acc[TS_BITS-1:0];
                        rec_data  <= {in_word[7:0], acc[REC_BITS-9:TS_BITS]};
                    end
                    idx <= idx + 1'b1;
                end
            end
        end
    end
endmodule
