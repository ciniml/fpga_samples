`default_nettype none

module append_crc #(
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

    output wire [DATA_BITS-1:0]  maxis_tdata,
    output wire                  maxis_tvalid,
    input  wire                  maxis_tready,
    output wire [DATA_BYTES-1:0] maxis_tkeep,
    output wire                  maxis_tlast,
    output wire                  maxis_tuser
);

logic [31:0] crc;

crc_mac crc_mac_inst(
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata (saxis_tdata),
    .saxis_tvalid(saxis_tvalid),
    .saxis_tready(saxis_tready),
    .saxis_tkeep (saxis_tkeep),
    .saxis_tlast (saxis_tlast),
    .saxis_tuser (saxis_tuser),

    .maxis_tdata (input_tdata),
    .maxis_tvalid(input_tvalid),
    .maxis_tready(input_tready),
    .maxis_tkeep (input_tkeep),
    .maxis_tlast (input_tlast),
    .maxis_tuser (input_tuser),

    .crc_out(crc)
);

logic [63:0] input_tdata;
logic input_tvalid;
logic input_tready;
logic [7:0] input_tkeep;
logic input_tlast;
logic input_tuser;

logic [95:0] appended_tdata;
assign appended_tdata = input_tkeep[7] ? { crc, input_tdata[0 +: 8*8] }
                      : input_tkeep[6] ? { {1 {8'h0}}, crc, input_tdata[0 +: 8*7] }
                      : input_tkeep[5] ? { {2 {8'h0}}, crc, input_tdata[0 +: 8*6] }
                      : input_tkeep[4] ? { {3 {8'h0}}, crc, input_tdata[0 +: 8*5] }
                      : input_tkeep[3] ? { {4 {8'h0}}, crc, input_tdata[0 +: 8*4] }
                      : input_tkeep[2] ? { {5 {8'h0}}, crc, input_tdata[0 +: 8*3] }
                      : input_tkeep[1] ? { {6 {8'h0}}, crc, input_tdata[0 +: 8*2] }
                      : input_tkeep[0] ? { {7 {8'h0}}, crc, input_tdata[0 +: 8*1] }
                      :                  { {8 {8'h0}}, crc };
logic [11:0] appended_tkeep;
assign appended_tkeep = input_tkeep[7] ? 12'b1111_1111_1111
                      : input_tkeep[6] ? 12'b0111_1111_1111
                      : input_tkeep[5] ? 12'b0011_1111_1111
                      : input_tkeep[4] ? 12'b0001_1111_1111
                      : input_tkeep[3] ? 12'b0000_1111_1111
                      : input_tkeep[2] ? 12'b0000_0111_1111
                      : input_tkeep[1] ? 12'b0000_0011_1111
                      : input_tkeep[0] ? 12'b0000_0001_1111
                      :                  12'b0000_0000_1111;
logic appended_use_next_beat;
assign appended_use_next_beat = |input_tkeep[7:4];

logic [63:0] output_tdata;
logic        output_tvalid;
logic        output_tready;
logic [7:0]  output_tkeep;
logic        output_tlast;
logic        output_tuser;

logic        has_overflowed_data;
logic [31:0] overflowed_tdata;
logic [3:0]  overflowed_tkeep;
logic        overflowed_tuser;

assign input_tready = !has_overflowed_data && (!output_tvalid || output_tready);

assign maxis_tdata   = output_tdata;
assign maxis_tvalid  = output_tvalid;
assign maxis_tkeep   = output_tkeep;
assign maxis_tlast   = output_tlast;
assign maxis_tuser   = output_tuser;
assign output_tready = maxis_tready;

always @(posedge clock) begin
    if( !aresetn ) begin
        has_overflowed_data <= 0;
        
        output_tdata  <= 0;
        output_tvalid <= 0;
        output_tkeep  <= 0;
        output_tlast  <= 0;
        output_tuser  <= 0;

        overflowed_tdata <= 0;
        overflowed_tkeep <= 0;
        overflowed_tuser <= 0;
    end 
    else begin
        if( input_tvalid && input_tready ) begin
            if( input_tlast && appended_use_next_beat ) begin
                output_tvalid <= 1;
                output_tlast <= 0;
                output_tuser <= 0;
                output_tkeep <= appended_tkeep[7:0];
                output_tdata <= appended_tdata[63:0];
                
                overflowed_tuser <= input_tuser;
                overflowed_tkeep <= appended_tkeep[11:8];
                overflowed_tdata <= appended_tdata[95:64];

                has_overflowed_data <= 1;
            end
            else begin
                output_tvalid <= 1;
                output_tdata <= appended_tdata[63:0];
                output_tuser <= input_tuser;
                output_tkeep <= appended_tkeep[7:0];
                output_tlast <= input_tlast;
            end
        end
        else if( output_tvalid && output_tready && has_overflowed_data ) begin
            output_tvalid <= 1;
            output_tlast <= 1;
            output_tuser <= overflowed_tuser;
            output_tkeep <= {4'b0, overflowed_tkeep};
            output_tdata <= {32'b0, overflowed_tdata};
            has_overflowed_data <= 0;
        end
        else if( output_tvalid && output_tready ) begin
            output_tvalid <= 0;
        end
    end
end

endmodule

`default_nettype wire
