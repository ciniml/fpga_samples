`default_nettype none

module mii_mac_tx #(
    parameter PREAMBLE_CHARACTER = 8'h55,
    parameter SFD_CHARACTER = 8'hd5,
    parameter bit USE_RMII = 0
) (
    input wire clock,
    input wire aresetn,
    
    // MII output
    output reg [3:0] mii_d,
    output reg       mii_en,
    output reg       mii_er,

    // Ethernet payload input
    input  wire [7:0] saxis_tdata,
    input  wire       saxis_tvalid,
    output wire       saxis_tready,
    input  wire       saxis_tuser,
    input  wire       saxis_tlast,

    // Ethernet bypass input (without prepending preamble and appending FCS)
    input  wire [7:0] saxis_bypass_tdata,
    input  wire       saxis_bypass_tvalid,
    output wire       saxis_bypass_tready,
    input  wire       saxis_bypass_tuser,
    input  wire       saxis_bypass_tlast
);

logic [7:0] append_crc_out_tdata;
logic       append_crc_out_tvalid;
logic       append_crc_out_tready;
logic       append_crc_out_tuser = 0;
logic       append_crc_out_tlast;

append_crc append_crc_inst (
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata(saxis_tdata),
    .saxis_tvalid(saxis_tvalid),
    .saxis_tready(saxis_tready),
    .saxis_tuser(saxis_tuser),
    .saxis_tlast(saxis_tlast),

    .maxis_tdata(append_crc_out_tdata),
    .maxis_tvalid(append_crc_out_tvalid),
    .maxis_tready(append_crc_out_tready),
    .maxis_tuser(append_crc_out_tuser),
    .maxis_tlast(append_crc_out_tlast)
);

logic [7:0] prepend_preamble_out_tdata;
logic       prepend_preamble_out_tvalid;
logic       prepend_preamble_out_tready;
logic       prepend_preamble_out_tuser = 0;
logic       prepend_preamble_out_tlast;

prepend_preamble #(
    .PREAMBLE(PREAMBLE_CHARACTER), .SFD(SFD_CHARACTER)
) prepend_preamble_inst (
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata(append_crc_out_tdata),
    .saxis_tvalid(append_crc_out_tvalid),
    .saxis_tready(append_crc_out_tready),
    .saxis_tlast(append_crc_out_tlast),

    .maxis_tdata(prepend_preamble_out_tdata),
    .maxis_tvalid(prepend_preamble_out_tvalid),
    .maxis_tready(prepend_preamble_out_tready),
    .maxis_tlast(prepend_preamble_out_tlast)
);

logic [7:0] mux_out_tdata;
logic       mux_out_tvalid;
logic       mux_out_tready;
logic       mux_out_tuser;
logic       mux_out_tlast;

axis_mux axis_mux_inst (
    .clock(clock),
    .aresetn(aresetn),

    .saxis_0_tdata(prepend_preamble_out_tdata),
    .saxis_0_tvalid(prepend_preamble_out_tvalid),
    .saxis_0_tready(prepend_preamble_out_tready),
    .saxis_0_tuser(prepend_preamble_out_tuser),
    .saxis_0_tlast(prepend_preamble_out_tlast),

    .saxis_1_tdata(saxis_bypass_tdata),
    .saxis_1_tvalid(saxis_bypass_tvalid),
    .saxis_1_tready(saxis_bypass_tready),
    .saxis_1_tuser(saxis_bypass_tuser),
    .saxis_1_tlast(saxis_bypass_tlast),

    .maxis_tdata(mux_out_tdata),
    .maxis_tvalid(mux_out_tvalid),
    .maxis_tready(mux_out_tready),
    .maxis_tuser(mux_out_tuser),
    .maxis_tlast(mux_out_tlast)
);

if( USE_RMII ) begin :use_rmii_block
    axis_to_rmii axis_to_rmii_inst (
        .clock(clock),
        .aresetn(aresetn),

        .saxis_tdata(mux_out_tdata),
        .saxis_tvalid(mux_out_tvalid),
        .saxis_tready(mux_out_tready),
        .saxis_tlast(mux_out_tlast),

        .rmii_d(mii_d[1:0]),
        .rmii_en(mii_en)
    );
    assign mii_d[3:2] = 0;
    assign mii_er = 0;
end
else begin :use_mii_block
    axis_to_mii axis_to_mii_inst (
        .clock(clock),
        .aresetn(aresetn),

        .saxis_tdata(mux_out_tdata),
        .saxis_tvalid(mux_out_tvalid),
        .saxis_tready(mux_out_tready),
        .saxis_tlast(mux_out_tlast),

        .mii_d(mii_d),
        .mii_en(mii_en),
        .mii_er(mii_er)
    );
end

endmodule

`default_nettype wire
