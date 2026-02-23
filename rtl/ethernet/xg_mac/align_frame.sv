`default_nettype none

module align_frame #(
    parameter [7:0] SFD      = 8'hd5
) (
    input wire clock,
    input wire aresetn,
    
    input  wire [63:0] saxis_tdata,
    input  wire        saxis_tvalid,
    output wire        saxis_tready,
    input  wire [7:0]  saxis_tkeep,
    input  wire        saxis_tlast,
    input  wire        saxis_tuser,

    output reg  [63:0] maxis_tdata,
    output reg         maxis_tvalid,
    input  wire        maxis_tready,
    output reg  [7:0]  maxis_tkeep,
    output reg         maxis_tlast,
    output reg         maxis_tuser
);


logic [63:0] previous_tdata;
logic [7:0]  previous_tkeep;
logic        previous_tlast;
logic        previous_tuser;

function automatic bit[7:0] get_sfd_pos(bit [63:0] tdata);
    return tdata[8*0 +: 8] == SFD ? 8'b0000_0001
         : tdata[8*1 +: 8] == SFD ? 8'b0000_0010
         : tdata[8*2 +: 8] == SFD ? 8'b0000_0100
         : tdata[8*3 +: 8] == SFD ? 8'b0000_1000
         : tdata[8*4 +: 8] == SFD ? 8'b0001_0000
         : tdata[8*5 +: 8] == SFD ? 8'b0010_0000
         : tdata[8*6 +: 8] == SFD ? 8'b0100_0000
         : tdata[8*7 +: 8] == SFD ? 8'b1000_0000
         :                          8'b0000_0000;
endfunction

function automatic bit is_aligned(bit [63:0] tdata);
    bit [7:0] pos;
    pos = get_sfd_pos(tdata);
    return pos[7];
endfunction


logic is_active;
logic [7:0] sfd_pos;

logic has_sfd;
assign has_sfd = |get_sfd_pos(saxis_tdata);

logic aligned;
assign aligned = sfd_pos[7];

logic [7:0] tkeep;
assign tkeep = saxis_tvalid && saxis_tready ? saxis_tkeep : 0;

logic [15:0] next_tkeep;
assign next_tkeep = sfd_pos[0] ? { {1 {1'b0}}, tkeep, previous_tkeep[7:1] }
                  : sfd_pos[1] ? { {2 {1'b0}}, tkeep, previous_tkeep[7:2] }
                  : sfd_pos[2] ? { {3 {1'b0}}, tkeep, previous_tkeep[7:3] }
                  : sfd_pos[3] ? { {4 {1'b0}}, tkeep, previous_tkeep[7:4] }
                  : sfd_pos[4] ? { {5 {1'b0}}, tkeep, previous_tkeep[7:5] }
                  : sfd_pos[5] ? { {6 {1'b0}}, tkeep, previous_tkeep[7:6] }
                  : sfd_pos[6] ? { {7 {1'b0}}, tkeep, previous_tkeep[7:7] }
                  : sfd_pos[7] ? { {8 {1'b0}}, tkeep }
                  : '0;
logic has_next_beat;
assign has_next_beat = !previous_tlast;

logic [127:0] next_tdata;
assign next_tdata = sfd_pos[0] ? { {1 {8'b0}}, saxis_tdata, previous_tdata[63 -: 8*7] }
                  : sfd_pos[1] ? { {2 {8'b0}}, saxis_tdata, previous_tdata[63 -: 8*6] }
                  : sfd_pos[2] ? { {3 {8'b0}}, saxis_tdata, previous_tdata[63 -: 8*5] }
                  : sfd_pos[3] ? { {4 {8'b0}}, saxis_tdata, previous_tdata[63 -: 8*4] }
                  : sfd_pos[4] ? { {5 {8'b0}}, saxis_tdata, previous_tdata[63 -: 8*3] }
                  : sfd_pos[5] ? { {6 {8'b0}}, saxis_tdata, previous_tdata[63 -: 8*2] }
                  : sfd_pos[6] ? { {7 {8'b0}}, saxis_tdata, previous_tdata[63 -: 8*1] }
                  : sfd_pos[7] ? { {8 {8'b0}}, saxis_tdata }
                  : '0;

logic flushing;

assign saxis_tready = (!maxis_tvalid || maxis_tready) && !flushing;

always @(posedge clock) begin
    if( !aresetn ) begin
        is_active <= 0;
        sfd_pos <= 0;
        previous_tdata <= 0;
        previous_tkeep <= 0;
        previous_tuser <= 0;
        previous_tlast <= 0;

        maxis_tvalid <= 0;
        maxis_tkeep  <= 0;
        maxis_tuser  <= 0;
        maxis_tlast  <= 0;

        flushing <= 0;
    end 
    else begin
        previous_tdata <= saxis_tvalid && saxis_tready ? saxis_tdata : previous_tdata;
        previous_tkeep <= saxis_tvalid && saxis_tready ? saxis_tkeep : previous_tkeep;
        previous_tlast <= saxis_tvalid && saxis_tready ? saxis_tlast : previous_tlast;
        previous_tuser <= saxis_tvalid && saxis_tready ? saxis_tuser : previous_tuser;

        if( maxis_tvalid && maxis_tready ) begin
            maxis_tvalid <= 0;
        end

        if( !is_active ) begin 
            if( saxis_tvalid && saxis_tready && has_sfd ) begin
                sfd_pos <= get_sfd_pos(saxis_tdata);
                is_active <= 1;
            end
        end
        else if( aligned ) begin
            if( saxis_tvalid && saxis_tready ) begin
                maxis_tdata <= saxis_tdata;
                maxis_tkeep <= saxis_tkeep;
                maxis_tlast <= saxis_tlast;
                maxis_tuser <= saxis_tuser;
                maxis_tvalid <= 1;
                if( saxis_tlast ) begin
                    is_active <= 0;
                end 
            end
        end
        else begin   // unaligned
            if( saxis_tvalid && saxis_tready || maxis_tvalid && maxis_tready && flushing) begin
                flushing <= !flushing && |next_tkeep[15:8] && saxis_tlast;
                maxis_tdata  <= next_tdata[63:0];
                maxis_tkeep  <= next_tkeep[7:0];
                maxis_tlast  <= flushing ? previous_tlast : ~|next_tkeep[15:8] && saxis_tlast;
                maxis_tuser  <= flushing ? previous_tuser : ~|next_tkeep[15:8] && saxis_tuser;
                maxis_tvalid <= 1;
                if( flushing || ~|next_tkeep[15:8] && saxis_tlast ) begin
                    is_active <= 0;
                end
            end
        end
    end
end

endmodule

`default_nettype wire
