`default_nettype none

module crc_mac (
    input wire clock,
    input wire aresetn,
    
    input  wire [7:0] saxis_tdata,
    input  wire       saxis_tvalid,
    output wire       saxis_tready,
    input  wire       saxis_tlast,
    input  wire       saxis_tuser,

    output wire [7:0] maxis_tdata,
    output wire       maxis_tvalid,
    input  wire       maxis_tready,
    output wire       maxis_tlast,
    output wire       maxis_tuser,

    output wire  [31:0] crc_out
);

// Pass-through AXI Stream
assign maxis_tdata = saxis_tdata;
assign maxis_tvalid = saxis_tvalid;
assign saxis_tready = maxis_tready;
assign maxis_tlast = saxis_tlast;
assign maxis_tuser = saxis_tuser;

localparam [31:0] POLYNOMIAL = 32'b1110_1101_1011_1000_1000_0011_0010_0000;

reg  [31:0] remainder;
wire [31:0] rem_stage[8:0];

assign rem_stage[0] = {remainder[31:8], remainder[7:0] ^ saxis_tdata};
generate 
for(genvar i = 0; i < 8; i = i + 1) begin
    assign rem_stage[i+1] = {1'b0, rem_stage[i][31:1] ^ (rem_stage[i][0] ? POLYNOMIAL : 32'b0)};
end
endgenerate

wire [31:0] remainder_next;
assign remainder_next = rem_stage[8];

reg [31:0] crc_out_reg;
assign crc_out = saxis_tvalid && saxis_tready && saxis_tlast ? ~remainder_next : crc_out_reg;

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
