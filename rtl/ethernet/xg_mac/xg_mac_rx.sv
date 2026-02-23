`default_nettype none

module xg_mac_rx (
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

logic [63:0] xgmii_to_axis_out_tdata;
logic        xgmii_to_axis_out_tvalid;
logic        xgmii_to_axis_out_tready;
logic [7:0]  xgmii_to_axis_out_tkeep;
logic        xgmii_to_axis_out_tuser;
logic        xgmii_to_axis_out_tlast;

xgmii_to_axis xgmii_to_axis_inst (
    .clock(clock),
    .aresetn(aresetn),

    .xgmii_d(xgmii_d),
    .xgmii_c(xgmii_c),

    .maxis_tdata(xgmii_to_axis_out_tdata),
    .maxis_tvalid(xgmii_to_axis_out_tvalid),
    .maxis_tkeep(xgmii_to_axis_out_tkeep),
    .maxis_tuser(xgmii_to_axis_out_tuser),
    .maxis_tlast(xgmii_to_axis_out_tlast)
);


typedef struct packed {
    bit [63:0] tdata;
    bit [7:0]  tkeep;
    bit        tuser;
    bit        tlast;
} fifo_data_t;

fifo_data_t fifo_in_tdata;
logic       fifo_in_tvalid;
logic       fifo_in_tready;

fifo_data_t fifo_out_tdata;
logic       fifo_out_tvalid;
logic       fifo_out_tready;

simple_fifo #(.DATA_BITS(64+8+1+1), .DEPTH_BITS(4)) fifo_inst (
    .saxis_tdata (fifo_in_tdata ),
    .saxis_tvalid(fifo_in_tvalid),
    .saxis_tready(),
    .maxis_tdata (fifo_out_tdata ),
    .maxis_tvalid(fifo_out_tvalid),
    .maxis_tready(fifo_out_tready),
    .*
);

assign fifo_in_tdata = '{tdata: xgmii_to_axis_out_tdata, tkeep: xgmii_to_axis_out_tkeep, tuser: xgmii_to_axis_out_tuser, tlast: xgmii_to_axis_out_tlast};
assign fifo_in_tvalid = xgmii_to_axis_out_tvalid;

logic [63:0] align_frame_out_tdata;
logic        align_frame_out_tvalid;
logic        align_frame_out_tready;
logic [7:0]  align_frame_out_tkeep;
logic        align_frame_out_tuser;
logic        align_frame_out_tlast;

align_frame align_frame_inst (
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata(fifo_out_tdata.tdata),
    .saxis_tkeep(fifo_out_tdata.tkeep),
    .saxis_tuser(fifo_out_tdata.tuser),
    .saxis_tlast(fifo_out_tdata.tlast),
    .saxis_tvalid(fifo_out_tvalid),
    .saxis_tready(fifo_out_tready),

    .maxis_tdata(align_frame_out_tdata),
    .maxis_tvalid(align_frame_out_tvalid),
    .maxis_tready(align_frame_out_tready),
    .maxis_tkeep(align_frame_out_tkeep),
    .maxis_tuser(align_frame_out_tuser),
    .maxis_tlast(align_frame_out_tlast)
);

logic [31:0] fcs;
logic [63:0] remove_crc_out_tdata;
logic        remove_crc_out_tvalid;
logic        remove_crc_out_tready;
logic [7:0]  remove_crc_out_tkeep;
logic        remove_crc_out_tuser;
logic        remove_crc_out_tlast;

remove_crc remove_crc_inst (
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata (align_frame_out_tdata),
    .saxis_tvalid(align_frame_out_tvalid),
    .saxis_tready(align_frame_out_tready),
    .saxis_tkeep (align_frame_out_tkeep),
    .saxis_tuser (align_frame_out_tuser),
    .saxis_tlast (align_frame_out_tlast),
    
    .maxis_tdata (remove_crc_out_tdata),
    .maxis_tvalid(remove_crc_out_tvalid),
    .maxis_tready(remove_crc_out_tready),
    .maxis_tkeep (remove_crc_out_tkeep),
    .maxis_tuser (remove_crc_out_tuser),
    .maxis_tlast (remove_crc_out_tlast),

    .crc(fcs)
);



logic [31:0] crc;
logic [63:0] crc_mac_out_tdata;
logic        crc_mac_out_tvalid;
logic        crc_mac_out_tready;
logic [7:0]  crc_mac_out_tkeep;
logic        crc_mac_out_tuser;
logic        crc_mac_out_tlast;

crc_mac crc_mac_inst(
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata (remove_crc_out_tdata),
    .saxis_tvalid(remove_crc_out_tvalid),
    .saxis_tready(remove_crc_out_tready),
    .saxis_tkeep (remove_crc_out_tkeep),
    .saxis_tuser (remove_crc_out_tuser),
    .saxis_tlast (remove_crc_out_tlast),

    .maxis_tdata (crc_mac_out_tdata),
    .maxis_tvalid(crc_mac_out_tvalid),
    .maxis_tready(crc_mac_out_tready),
    .maxis_tkeep (crc_mac_out_tkeep),
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
assign maxis_tkeep  = crc_mac_out_tkeep;
assign maxis_tuser  = !(is_crc_valid && !crc_mac_out_tuser);
assign maxis_tlast  = crc_mac_out_tlast;

endmodule

`default_nettype wire
