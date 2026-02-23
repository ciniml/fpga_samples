`default_nettype none

module remove_crc #(
    parameter DATA_BYTES = 8,
    parameter DATA_BITS = DATA_BYTES*8
) (
    input wire clock,
    input wire aresetn,
    
    input  wire [DATA_BITS-1:0]  saxis_tdata,
    input  wire                  saxis_tvalid,
    output wire                  saxis_tready,
    input  wire [DATA_BYTES-1:0] saxis_tkeep,
    input  wire                  saxis_tlast,
    input  wire                  saxis_tuser,

    output reg   [DATA_BITS-1:0]  maxis_tdata,
    output reg                   maxis_tvalid,
    input  wire                  maxis_tready,
    output reg   [DATA_BYTES-1:0] maxis_tkeep,
    output reg                   maxis_tlast,
    output reg                   maxis_tuser,

    output reg [31:0] crc
);

logic [127:0] buffer_tdata;
logic [15:0]  buffer_tkeep;
logic         buffer_tvalid;
logic         buffer_tready;
logic [1:0]   buffer_tuser;
logic [1:0]   buffer_tlast;

logic [15:0] removed_tkeep;
assign removed_tkeep = buffer_tkeep[7+8] ? { {4+0 {1'b0}}, {4 {1'b1}}, buffer_tkeep[0 +: 8] }
                     : buffer_tkeep[6+8] ? { {4+1 {1'b0}}, {3 {1'b1}}, buffer_tkeep[0 +: 8] }
                     : buffer_tkeep[5+8] ? { {4+2 {1'b0}}, {2 {1'b1}}, buffer_tkeep[0 +: 8] }
                     : buffer_tkeep[4+8] ? { {4+3 {1'b0}}, {1 {1'b1}}, buffer_tkeep[0 +: 8] }
                     : buffer_tkeep[3+8] ? { {4+4 {1'b0}},             buffer_tkeep[0 +: 8] }
                     : buffer_tkeep[2+8] ? { {4+5 {1'b0}},             buffer_tkeep[0 +: 7] }
                     : buffer_tkeep[1+8] ? { {4+6 {1'b0}},             buffer_tkeep[0 +: 6] }
                     : buffer_tkeep[0+8] ? { {4+7 {1'b0}},             buffer_tkeep[0 +: 5] }
                     :                     { {4+8 {1'b0}},             buffer_tkeep[0 +: 4] };

logic [31:0] crc_in_buffer;
assign crc_in_buffer = buffer_tkeep[7+8] ? buffer_tdata[8*12 +: 32]
                     : buffer_tkeep[6+8] ? buffer_tdata[8*11 +: 32]
                     : buffer_tkeep[5+8] ? buffer_tdata[8*10 +: 32]
                     : buffer_tkeep[4+8] ? buffer_tdata[8* 9 +: 32]
                     : buffer_tkeep[3+8] ? buffer_tdata[8* 8 +: 32]
                     : buffer_tkeep[2+8] ? buffer_tdata[8* 7 +: 32]
                     : buffer_tkeep[1+8] ? buffer_tdata[8* 6 +: 32]
                     : buffer_tkeep[0+8] ? buffer_tdata[8* 5 +: 32]
                     :                     buffer_tdata[8* 4 +: 32];


logic flushing;

assign buffer_tready = !maxis_tvalid || maxis_tready;
assign saxis_tready = (!buffer_tvalid || buffer_tready) && !flushing;

always @(posedge clock) begin
    if( !aresetn ) begin
        maxis_tvalid <= 0;
        maxis_tlast <= 0;
        maxis_tuser <= 0;
        maxis_tdata <= 0;
        maxis_tkeep <= 0;

        buffer_tdata <= 0;
        buffer_tkeep <= 0;
        buffer_tuser <= 0;
        buffer_tvalid <= 0;
        buffer_tlast <= 0;

        crc <= 0;

        flushing <= 0;
    end 
    else begin
        if( !maxis_tvalid || maxis_tready ) begin
            if( buffer_tkeep[7:0] != 0 ) begin
                maxis_tvalid <= 1;
                maxis_tdata <= buffer_tdata[63:0];
                maxis_tlast <= buffer_tlast[0];
                maxis_tkeep <= buffer_tkeep[7:0];
                maxis_tuser <= buffer_tuser[0];
                
                if( buffer_tlast[1] && buffer_tkeep[15:8] != 0 && removed_tkeep[15:8] == 0 ) begin // The last word is truncated because it is not longer than 4 bytes.
                    maxis_tlast <= 1;
                    maxis_tuser <= buffer_tuser[1]; // Bypass buffer[0]
                    maxis_tkeep <= removed_tkeep[7:0];
                    crc <= crc_in_buffer;
                    flushing <= 0;
                end
                if( buffer_tlast[0] ) begin
                    flushing <= 0;
                end
                buffer_tkeep[7:0] <= 0;
            end
            else begin
                maxis_tvalid <= 0;
            end
        end
        if( buffer_tvalid && buffer_tready) begin
            buffer_tdata[63:0] <= buffer_tdata[127:64];
            buffer_tlast[0] <= buffer_tlast[1];
            buffer_tuser[0] <= buffer_tuser[1];
            if( buffer_tlast[1] ) begin
                buffer_tkeep[7:0]  <= removed_tkeep[15:8];
                crc <= crc_in_buffer;
            end
            else begin
                buffer_tkeep[7:0]  <= buffer_tkeep[15:8];
            end
            buffer_tvalid <= 0;
        end
        if( saxis_tvalid && saxis_tready ) begin
            buffer_tdata[127:64] <= saxis_tdata;
            buffer_tkeep[15:8] <= saxis_tkeep;
            buffer_tuser[1] <= saxis_tuser;
            buffer_tlast[1] <= saxis_tlast;
            flushing <= saxis_tlast;
            buffer_tvalid <= 1;
        end
        
    end
end

endmodule

`default_nettype wire
