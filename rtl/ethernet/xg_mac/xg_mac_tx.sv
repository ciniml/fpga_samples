`default_nettype none

module xg_mac_tx #(
    parameter PREAMBLE_CHARACTER = 8'h55,
    parameter SFD_CHARACTER = 8'hd5,
    parameter SHORT_PREAMBLE = 1
) (
    input wire clock,
    input wire aresetn,
    
    output reg [63:0] xgmii_d,
    output reg  [7:0] xgmii_c,

    input  wire [63:0] saxis_tdata,
    input  wire        saxis_tvalid,
    output wire        saxis_tready,
    input  wire  [7:0] saxis_tkeep,
    input  wire        saxis_tuser,
    input  wire        saxis_tlast
);

logic [63:0] append_crc_out_tdata;
logic        append_crc_out_tvalid;
logic        append_crc_out_tready;
logic [7:0]  append_crc_out_tkeep;
logic        append_crc_out_tuser;
logic        append_crc_out_tlast;

append_crc append_crc_inst (
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata(saxis_tdata),
    .saxis_tvalid(saxis_tvalid),
    .saxis_tready(saxis_tready),
    .saxis_tkeep(saxis_tkeep),
    .saxis_tuser(saxis_tuser),
    .saxis_tlast(saxis_tlast),

    .maxis_tdata(append_crc_out_tdata),
    .maxis_tvalid(append_crc_out_tvalid),
    .maxis_tready(append_crc_out_tready),
    .maxis_tkeep(append_crc_out_tkeep),
    .maxis_tuser(append_crc_out_tuser),
    .maxis_tlast(append_crc_out_tlast)
);

generate
if( !SHORT_PREAMBLE ) begin

    logic [63:0] prepend_preamble_out_tdata;
    logic        prepend_preamble_out_tvalid;
    logic        prepend_preamble_out_tready;
    logic [7:0]  prepend_preamble_out_tkeep;
    logic        prepend_preamble_out_tuser;
    logic        prepend_preamble_out_tlast;

    localparam bit [63:0] PREAMBLE = {SFD_CHARACTER, {7 {PREAMBLE_CHARACTER}}};
    prepend_preamble #(.PREAMBLE(PREAMBLE)) prepend_preamble_inst (
        .clock(clock),
        .aresetn(aresetn),

        .saxis_tdata(append_crc_out_tdata),
        .saxis_tvalid(append_crc_out_tvalid),
        .saxis_tready(append_crc_out_tready),
        .saxis_tkeep(append_crc_out_tkeep),
        .saxis_tuser(append_crc_out_tuser),
        .saxis_tlast(append_crc_out_tlast),

        .maxis_tdata(prepend_preamble_out_tdata),
        .maxis_tvalid(prepend_preamble_out_tvalid),
        .maxis_tready(prepend_preamble_out_tready),
        .maxis_tkeep(prepend_preamble_out_tkeep),
        .maxis_tuser(prepend_preamble_out_tuser),
        .maxis_tlast(prepend_preamble_out_tlast)
    );

    axis_to_xgmii axis_to_xgmii_inst (
        .clock(clock),
        .aresetn(aresetn),

        .saxis_tdata(prepend_preamble_out_tdata),
        .saxis_tvalid(prepend_preamble_out_tvalid),
        .saxis_tready(prepend_preamble_out_tready),
        .saxis_tkeep(prepend_preamble_out_tkeep),
        .saxis_tuser(prepend_preamble_out_tuser),
        .saxis_tlast(prepend_preamble_out_tlast),

        .xgmii_d(xgmii_d),
        .xgmii_c(xgmii_c)
    );
end
else begin
     axis_to_xgmii_preamble #(
        .SFD_CHARACTER(SFD_CHARACTER),
        .PREAMBLE_CHARACTER(PREAMBLE_CHARACTER)
     ) axis_to_xgmii_preamble_inst (
        .clock(clock),
        .aresetn(aresetn),

        .saxis_tdata(append_crc_out_tdata),
        .saxis_tvalid(append_crc_out_tvalid),
        .saxis_tready(append_crc_out_tready),
        .saxis_tkeep(append_crc_out_tkeep),
        .saxis_tuser(append_crc_out_tuser),
        .saxis_tlast(append_crc_out_tlast),

        .xgmii_d(xgmii_d),
        .xgmii_c(xgmii_c)
    );
end
endgenerate

endmodule

`default_nettype wire
