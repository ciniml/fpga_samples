`default_nettype none

module mii_to_axis (
    input wire clock,
    input wire aresetn,
    
    input wire [3:0] mii_d,
    input wire       mii_dv,
    input wire       mii_er,

    output reg  [7:0]  maxis_tdata,
    output reg         maxis_tvalid,
    output reg         maxis_tuser,
    output reg         maxis_tlast
);

localparam SFD = 8'hd5;

logic prev_is_sfd_lower;
logic sfd_detected;

logic phase = 0;

logic prev_in_frame = 0;
logic in_frame = 0;

assign sfd_detected = prev_is_sfd_lower && mii_dv && mii_d == SFD[7:4] && !in_frame;

always_ff @(posedge clock) begin
    if( !aresetn ) begin
        phase <= 0;
        in_frame <= 0;
        prev_in_frame <= 0;
    end
    else begin
        prev_is_sfd_lower <= mii_dv && mii_d == SFD[3:0];
        prev_in_frame <= in_frame;
        phase <= sfd_detected ? 0 : !phase;
        in_frame <=   sfd_detected ? 1
                    : !mii_dv ? 0
                    : in_frame;
    end
end


logic [7:0] tdata = 0;
logic       tuser;

assign tuser = 0;

always_ff @(posedge clock) begin
    if( !aresetn ) begin
        maxis_tdata <= 0;
        maxis_tvalid <= 0;
        maxis_tlast <= 0;
        maxis_tuser <= 0;
        tdata <= 0;
    end
    else begin
        if( mii_dv ) begin
            if( !phase ) begin
                tdata[3:0] <= mii_d;
            end
            else begin
                tdata[7:4] <= mii_d;
            end
        end
        if( prev_in_frame && in_frame && !phase ) begin
            maxis_tdata <= tdata;
            maxis_tuser <= tuser;
            maxis_tvalid <= 1;
            maxis_tlast <= !mii_dv;
        end
        else begin
            maxis_tvalid <= 0;
            maxis_tlast <= 0;
        end
    end
end


endmodule

`default_nettype wire
