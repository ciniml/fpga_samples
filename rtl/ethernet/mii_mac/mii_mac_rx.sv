`default_nettype none

module mii_mac_rx #(
    parameter USE_RMII = 0
)(
    input wire clock,
    input wire aresetn,
    
    input wire [3:0] mii_d,
    input wire       mii_dv,
    input wire       mii_er,

    output wire [7:0] maxis_tdata,
    output wire       maxis_tvalid,
    output wire       maxis_tuser,
    output wire       maxis_tlast
);

logic [7:0] mii_to_axis_out_tdata;
logic       mii_to_axis_out_tvalid;
logic       mii_to_axis_out_tready;
logic       mii_to_axis_out_tuser;
logic       mii_to_axis_out_tlast;

if( USE_RMII ) begin :use_rmii_block 
    rmii_to_axis rmii_to_axis_inst (
        .clock(clock),
        .aresetn(aresetn),

        .rmii_d(mii_d[1:0]),
        .rmii_dv(mii_dv),

        .maxis_tdata (mii_to_axis_out_tdata),
        .maxis_tvalid(mii_to_axis_out_tvalid),
        .maxis_tuser (mii_to_axis_out_tuser),
        .maxis_tlast (mii_to_axis_out_tlast)
    );
end
else begin :use_mii_block
    mii_to_axis mii_to_axis_inst (
        .clock(clock),
        .aresetn(aresetn),

        .mii_d(mii_d),
        .mii_dv(mii_dv),
        .mii_er(mii_er),

        .maxis_tdata (mii_to_axis_out_tdata),
        .maxis_tvalid(mii_to_axis_out_tvalid),
        .maxis_tuser (mii_to_axis_out_tuser),
        .maxis_tlast (mii_to_axis_out_tlast)
    );
end

typedef struct packed {
    bit [7:0] tdata;
    bit        tuser;
    bit        tlast;
} fifo_data_t;

fifo_data_t fifo_in_tdata;
logic       fifo_in_tvalid;
logic       fifo_in_tready;

fifo_data_t fifo_out_tdata;
logic       fifo_out_tvalid;
logic       fifo_out_tready;

simple_fifo #(.DATA_BITS($bits(fifo_data_t)), .DEPTH_BITS(4)) fifo_inst (
    .saxis_tdata (fifo_in_tdata ),
    .saxis_tvalid(fifo_in_tvalid),
    .saxis_tready(),
    .maxis_tdata (fifo_out_tdata ),
    .maxis_tvalid(fifo_out_tvalid),
    .maxis_tready(fifo_out_tready),
    .*
);

assign fifo_in_tdata = '{tdata: mii_to_axis_out_tdata, tuser: mii_to_axis_out_tuser, tlast: mii_to_axis_out_tlast};
assign fifo_in_tvalid = mii_to_axis_out_tvalid;

logic [31:0] fcs;
logic [7:0] remove_crc_out_tdata;
logic       remove_crc_out_tvalid;
logic       remove_crc_out_tready;
logic       remove_crc_out_tuser;
logic       remove_crc_out_tlast;

remove_crc remove_crc_inst (
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata (fifo_out_tdata.tdata),
    .saxis_tvalid(fifo_out_tvalid),
    .saxis_tready(fifo_out_tready),
    .saxis_tuser (fifo_out_tdata.tuser),
    .saxis_tlast (fifo_out_tdata.tlast),
    
    .maxis_tdata (remove_crc_out_tdata),
    .maxis_tvalid(remove_crc_out_tvalid),
    .maxis_tready(remove_crc_out_tready),
    .maxis_tuser (remove_crc_out_tuser),
    .maxis_tlast (remove_crc_out_tlast),

    .crc(fcs)
);


logic [31:0] crc;
logic [7:0] crc_mac_out_tdata;
logic       crc_mac_out_tvalid;
logic       crc_mac_out_tready;
logic       crc_mac_out_tuser;
logic       crc_mac_out_tlast;

crc_mac crc_mac_inst(
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata (remove_crc_out_tdata),
    .saxis_tvalid(remove_crc_out_tvalid),
    .saxis_tready(remove_crc_out_tready),
    .saxis_tuser (remove_crc_out_tuser),
    .saxis_tlast (remove_crc_out_tlast),

    .maxis_tdata (crc_mac_out_tdata),
    .maxis_tvalid(crc_mac_out_tvalid),
    .maxis_tready(crc_mac_out_tready),
    .maxis_tuser (crc_mac_out_tuser),
    .maxis_tlast (crc_mac_out_tlast),

    .crc_out(crc)
);

logic is_crc_valid_reg;
logic is_crc_valid;
assign is_crc_valid = crc_mac_out_tvalid && crc_mac_out_tready && crc_mac_out_tlast ? crc == fcs : is_crc_valid_reg;

always @(posedge clock) begin
    if( !aresetn ) begin
        is_crc_valid_reg <= 0;
    end
    else begin
        is_crc_valid_reg <= !(crc_mac_out_tvalid && crc_mac_out_tready) ? is_crc_valid_reg
                          : crc_mac_out_tlast ? crc == fcs
                          : 0;
    end
end

assign maxis_tdata  = crc_mac_out_tdata;
assign maxis_tvalid = crc_mac_out_tvalid;
assign crc_mac_out_tready = 1;
assign maxis_tuser  = !(is_crc_valid && !crc_mac_out_tuser);
assign maxis_tlast  = crc_mac_out_tlast;

endmodule

`default_nettype wire
