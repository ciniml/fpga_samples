`default_nettype none

module crc_mac (
    input wire clock,
    input wire aresetn,
    
    input  wire [63:0] saxis_tdata,
    input  wire        saxis_tvalid,
    output wire        saxis_tready,
    input  wire  [7:0] saxis_tkeep,
    input  wire        saxis_tlast,
    input  wire        saxis_tuser,

    output wire [63:0] maxis_tdata,
    output wire        maxis_tvalid,
    input  wire        maxis_tready,
    output wire  [7:0] maxis_tkeep,
    output wire        maxis_tlast,
    output wire        maxis_tuser,

    output wire  [31:0] crc_out
);

// Pass-through AXI Stream
assign maxis_tdata = saxis_tdata;
assign maxis_tvalid = saxis_tvalid;
assign saxis_tready = maxis_tready;
assign maxis_tkeep = saxis_tkeep;
assign maxis_tlast = saxis_tlast;
assign maxis_tuser = saxis_tuser;

localparam [31:0] POLYNOMIAL = 32'b1110_1101_1011_1000_1000_0011_0010_0000;

wire [63:0] tdata_mask;
assign tdata_mask = saxis_tkeep[7] ? {64 {1'b1} }
                  : saxis_tkeep[6] ? {{8*1 {1'b0}}, {(64 - 8*1) {1'b1}}}
                  : saxis_tkeep[5] ? {{8*2 {1'b0}}, {(64 - 8*2) {1'b1}}}
                  : saxis_tkeep[4] ? {{8*3 {1'b0}}, {(64 - 8*3) {1'b1}}}
                  : saxis_tkeep[3] ? {{8*4 {1'b0}}, {(64 - 8*4) {1'b1}}}
                  : saxis_tkeep[2] ? {{8*5 {1'b0}}, {(64 - 8*5) {1'b1}}}
                  : saxis_tkeep[1] ? {{8*6 {1'b0}}, {(64 - 8*6) {1'b1}}}
                  : saxis_tkeep[0] ? {{8*7 {1'b0}}, {(64 - 8*7) {1'b1}}}
                  : 0;
wire [63:0] tdata_masked;
assign tdata_masked = saxis_tdata & tdata_mask;

reg  [31:0] remainder;
wire [63:0] rem_stage[64:0];

assign rem_stage[0] = {tdata_masked[63:32], remainder ^ tdata_masked[31:0]};
generate 
for(genvar i = 0; i < 64; i = i + 1) begin
    assign rem_stage[i+1] = {1'b0, rem_stage[i][63:33], rem_stage[i][32:1] ^ (rem_stage[i][0] ? POLYNOMIAL : 32'b0)};
end
endgenerate

wire [31:0] remainder_next;
assign remainder_next = saxis_tkeep[7] ? rem_stage[64 - 8*0][31:0]
                      : saxis_tkeep[6] ? rem_stage[64 - 8*1][31:0]
                      : saxis_tkeep[5] ? rem_stage[64 - 8*2][31:0]
                      : saxis_tkeep[4] ? rem_stage[64 - 8*3][31:0]
                      : saxis_tkeep[3] ? rem_stage[64 - 8*4][31:0]
                      : saxis_tkeep[2] ? rem_stage[64 - 8*5][31:0]
                      : saxis_tkeep[1] ? rem_stage[64 - 8*6][31:0]
                      : saxis_tkeep[0] ? rem_stage[64 - 8*7][31:0]
                      :                  rem_stage[64 - 8*8][31:0];

reg crc_out_reg;
assign crc_out = saxis_tvalid && saxis_tready && saxis_tlast ? ~remainder_next : ~crc_out_reg;

always @(posedge clock) begin
    if( !aresetn ) begin
        remainder <= {32 {1'b1}};
        crc_out_reg   <= 0;
    end
    else begin
        remainder <= saxis_tvalid && saxis_tready ? (saxis_tlast ? {32 {1'b1}} : remainder_next) : remainder;
        crc_out_reg <= crc_out;
    end
end

endmodule

`default_nettype wire
