`default_nettype none

module xgmii_to_axis (
    input wire clock,
    input wire aresetn,
    
    input wire [63:0] xgmii_d,
    input wire [7:0] xgmii_c,

    output reg  [63:0] maxis_tdata,
    output reg         maxis_tvalid,
    output reg  [7:0]  maxis_tkeep,
    output reg         maxis_tuser,
    output reg         maxis_tlast
);

reg [63:0] xgmii_d_reg;
reg [7:0]  xgmii_c_reg;

wire sof_shift0;
wire sof_shift4;
wire sof;
wire eof;
wire err;
wire short;

reg shift4; // Did the current frame start from 4th byte?

assign sof_shift4 = xgmii_c[4] && xgmii_d[8*4 +: 8] == 8'hfb;
assign sof_shift0 = xgmii_c[0] && xgmii_d[8*0 +: 8] == 8'hfb;
assign sof = sof_shift0 || sof_shift4;

assign eof = (xgmii_c[0] && xgmii_d[ 0 +: 8] == 8'hfd) 
          || (xgmii_c[1] && xgmii_d[ 8 +: 8] == 8'hfd)
          || (xgmii_c[2] && xgmii_d[16 +: 8] == 8'hfd)
          || (xgmii_c[3] && xgmii_d[24 +: 8] == 8'hfd)
          || (xgmii_c[4] && xgmii_d[32 +: 8] == 8'hfd)
          || (xgmii_c[5] && xgmii_d[40 +: 8] == 8'hfd)
          || (xgmii_c[6] && xgmii_d[48 +: 8] == 8'hfd)
          || (xgmii_c[7] && xgmii_d[56 +: 8] == 8'hfd);
assign err = (xgmii_c[0] && xgmii_d[ 0 +: 8] == 8'hfe) 
          || (xgmii_c[1] && xgmii_d[ 8 +: 8] == 8'hfe)
          || (xgmii_c[2] && xgmii_d[16 +: 8] == 8'hfe)
          || (xgmii_c[3] && xgmii_d[24 +: 8] == 8'hfe)
          || (xgmii_c[4] && xgmii_d[32 +: 8] == 8'hfe)
          || (xgmii_c[5] && xgmii_d[40 +: 8] == 8'hfe)
          || (xgmii_c[6] && xgmii_d[48 +: 8] == 8'hfe)
          || (xgmii_c[7] && xgmii_d[56 +: 8] == 8'hfe);

wire short_shift0;
wire short_shift4;

assign short_shift0 = (xgmii_c[0] && (xgmii_d[ 0 +: 8] == 8'hfd || xgmii_d[ 0 +: 8] == 8'hfe)) 
                   || (xgmii_c[1] && (xgmii_d[ 8 +: 8] == 8'hfd || xgmii_d[ 8 +: 8] == 8'hfe));
assign short_shift4 = (xgmii_c[0] && (xgmii_d[ 0 +: 8] == 8'hfd || xgmii_d[ 0 +: 8] == 8'hfe)) 
                   || (xgmii_c[1] && (xgmii_d[ 8 +: 8] == 8'hfd || xgmii_d[ 8 +: 8] == 8'hfe))
                   || (xgmii_c[2] && (xgmii_d[16 +: 8] == 8'hfd || xgmii_d[16 +: 8] == 8'hfe))
                   || (xgmii_c[3] && (xgmii_d[24 +: 8] == 8'hfd || xgmii_d[24 +: 8] == 8'hfe))
                   || (xgmii_c[4] && (xgmii_d[32 +: 8] == 8'hfd || xgmii_d[32 +: 8] == 8'hfe))
                   || (xgmii_c[5] && (xgmii_d[40 +: 8] == 8'hfd || xgmii_d[40 +: 8] == 8'hfe));
assign short = (!shift4 && short_shift0) || (shift4 && short_shift4);

wire [63:0] tdata_shift0;
wire [63:0] tdata_shift4;
wire [63:0] tdata;
wire [7:0]  tkeep_shift0;
wire [7:0]  tkeep_shift4;
wire [7:0]  tkeep;
wire        tlast;
wire        tuser;

assign tdata_shift0 =  { xgmii_d[7:0], xgmii_d_reg[63:8] };
assign tdata_shift4 =  { xgmii_d[39:0], xgmii_d_reg[63:40] };
assign tkeep_shift0 = ~{ xgmii_c[0], xgmii_c_reg[7:1] };
assign tkeep_shift4 = ~{ xgmii_c[4:0], xgmii_c_reg[7:5] };

assign tdata = shift4 ? tdata_shift4 : tdata_shift0;
assign tkeep = shift4 ? tkeep_shift4 : tkeep_shift0;
assign tlast = eof || err;
assign tuser = err;

reg  tlast_reg;
reg  tuser_reg;

reg  in_frame_reg;

always @(posedge clock) begin
    if( !aresetn ) begin
        xgmii_d_reg <= 0;
        xgmii_c_reg <= 0;
        tlast_reg <= 0;
        tuser_reg <= 0;
        in_frame_reg <= 0;
        maxis_tdata <= 0;
        maxis_tvalid <= 0;
        maxis_tkeep <= {8 {1'b1}};
        maxis_tuser <= 0;
        maxis_tlast <= 0;
        shift4 <= 0;
    end
    else begin
        xgmii_d_reg <= xgmii_d;
        xgmii_c_reg <= xgmii_c;
        
        shift4 <= sof_shift4 ? 1 : sof_shift0 ? 0 : shift4;
        
        tlast_reg <= tlast;
        tuser_reg <= tuser;

        in_frame_reg <= sof ? 1 
                      : tlast_reg || (tlast && short) ? 0
                      : in_frame_reg;
        maxis_tvalid <= in_frame_reg;
        maxis_tdata  <= tdata;
        maxis_tkeep  <= tkeep;
        maxis_tlast  <= tlast_reg || (tlast && short);
        maxis_tuser  <= tuser_reg || (tuser && short);
    end
end

endmodule

`default_nettype wire
