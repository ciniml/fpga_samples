`default_nettype none

module axis_to_xgmii (
    input wire clock,
    input wire aresetn,
    
    output reg [63:0] xgmii_d,
    output reg  [7:0] xgmii_c,

    input  wire [63:0] saxis_tdata,
    input  wire        saxis_tvalid,
    output reg        saxis_tready,
    input  wire  [7:0] saxis_tkeep,
    input  wire        saxis_tuser,
    input  wire        saxis_tlast
);


wire sof;
wire eof;
wire err;

reg last_aligned;
reg last_aligned_err;
reg in_frame;

reg [71: 0] d_buffer;
reg [ 8: 0] c_buffer;

assign sof = !in_frame && saxis_tvalid && saxis_tready;
assign eof = saxis_tvalid && saxis_tready && saxis_tlast;
assign err = (in_frame && !saxis_tvalid) || (eof && saxis_tuser);

wire [8:0] terminator;

assign terminator = {1'b0, saxis_tkeep} ^ {saxis_tkeep, 1'b1};

wire [71:0] d_buffer_next;
wire [ 8:0] c_buffer_next;

assign d_buffer_next[7:0] = sof ? 8'hfb : d_buffer[71:64];
assign c_buffer_next[0] = sof ? 1'b1 : c_buffer[8];
generate
for(genvar i = 0; i < 8; i = i + 1) begin
    assign d_buffer_next[i*8+8 +: 8] = sof || in_frame ? (saxis_tkeep[i] ? saxis_tdata[i*8 +: 8] : terminator[i] ? (err ? 8'hfe : 8'hfd) : 8'h07)
                                     : last_aligned_err && i == 0 ? 8'hfe
                                     : last_aligned     && i == 0 ? 8'hfd
                                     : 8'h07;
    assign c_buffer_next[i+1] = !( (sof || in_frame) && saxis_tkeep[i] );
end
endgenerate

always @(posedge clock) begin
    if( !aresetn ) begin
        saxis_tready <= 0;
        in_frame <= 0;
        last_aligned <= 0;
        last_aligned_err <= 0;
        d_buffer <= {9 {8'h07} };
        c_buffer <= {9 {1'b1} };
        xgmii_d <= {8 {8'h07} };
        xgmii_c <= {8 {1'b1} };
    end
    else begin
        saxis_tready <= !(eof || err);
        
        xgmii_d <= d_buffer[63:0];
        xgmii_c <= c_buffer[7:0];

        in_frame <= eof || err ? 0 
                  : sof ? 1
                  : in_frame;
        
        last_aligned <= eof && saxis_tkeep == 8'b1111_1111;
        last_aligned_err <= err && saxis_tkeep == 8'b1111_1111;

        d_buffer <= d_buffer_next;
        c_buffer <= c_buffer_next;
    end
end

endmodule

`default_nettype wire
