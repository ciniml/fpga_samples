// Re-frames the {K flag, byte} word stream from the EasyCDR receiver into
// trace records: [K28.1][ts LSB..MSB][data LSB..MSB].
// K28.5 commas and K28.3 fillers interleaved inside a record are ignored;
// K28.1 restarts a record, K28.2 (overflow marker) is flagged.
// K28.4 starts a 4-byte descriptor ([VER][WIDTH][TS_BITS][flags]) which is
// latched to o_desc_* (quasi-static once the link is up).
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
    output reg                ovf_seen,  // pulse on K28.2
    output reg  [7:0]         o_desc_ver,    // 0 until a descriptor is seen
    output reg  [7:0]         o_desc_width,
    output reg  [7:0]         o_desc_tsbits,
    output reg  [7:0]         o_desc_flags,
    output wire               o_desc_busy    // descriptor bytes in flight
);
    localparam REC_BYTES = (TS_BITS + WIDTH) / 8;
    localparam REC_BITS  = TS_BITS + WIDTH;
    localparam [7:0] K28_1 = 8'h3c;
    localparam [7:0] K28_2 = 8'h5c;
    localparam [7:0] K28_4 = 8'h9c;

    reg                active;
    reg [7:0]          idx;
    reg [REC_BITS-1:0] acc;     // {data, ts}
    reg                desc_active;
    reg [1:0]          desc_idx;
    reg [23:0]         desc_acc;
    assign o_desc_busy = desc_active;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            active      <= 1'b0;
            desc_active <= 1'b0;
            desc_idx    <= 2'd0;
            desc_acc    <= 24'd0;
            o_desc_ver    <= 8'd0;
            o_desc_width  <= 8'd0;
            o_desc_tsbits <= 8'd0;
            o_desc_flags  <= 8'd0;
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
                        active      <= 1'b1;
                        desc_active <= 1'b0;
                        idx    <= 8'd0;
                    end else if (in_word[7:0] == K28_2) begin
                        ovf_seen <= 1'b1;
                    end else if (in_word[7:0] == K28_4) begin
                        active      <= 1'b0;
                        desc_active <= 1'b1;
                        desc_idx    <= 2'd0;
                    end
                    // other K codes (comma / filler): ignore
                end else if (desc_active) begin
                    if (desc_idx == 2'd3) begin
                        {o_desc_flags, o_desc_tsbits, o_desc_width, o_desc_ver}
                            <= {in_word[7:0], desc_acc};
                        desc_active <= 1'b0;
                    end
                    desc_acc <= {in_word[7:0], desc_acc[23:8]};
                    desc_idx <= desc_idx + 1'b1;
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
