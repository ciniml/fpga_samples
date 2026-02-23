`default_nettype none

module prepend_preamble #(
    parameter [63:0] PREAMBLE = 64'hd5_55_55_55_55_55_55_55
) (
    input wire clock,
    input wire aresetn,
    
    input  wire [63:0] saxis_tdata,
    input  wire        saxis_tvalid,
    output wire        saxis_tready,
    input  wire [7:0]  saxis_tkeep,
    input  wire        saxis_tlast,
    input  wire        saxis_tuser,

    output wire [63:0] maxis_tdata,
    output wire        maxis_tvalid,
    input  wire        maxis_tready,
    output wire [7:0]  maxis_tkeep,
    output wire        maxis_tlast,
    output wire        maxis_tuser
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

simple_fifo #(.DATA_BITS(64+8+1+1), .DEPTH_BITS(2)) fifo(
    .saxis_tdata (fifo_in_tdata ),
    .saxis_tvalid(fifo_in_tvalid),
    .saxis_tready(fifo_in_tready),
    .maxis_tdata (fifo_out_tdata ),
    .maxis_tvalid(fifo_out_tvalid),
    .maxis_tready(fifo_out_tready),
    .*
);

logic  flushing_fifo;

assign fifo_in_tdata = '{tdata: saxis_tdata, tkeep: saxis_tkeep, tuser: saxis_tuser, tlast: saxis_tlast};
assign fifo_in_tvalid = saxis_tvalid && !flushing_fifo;
assign saxis_tready  = !flushing_fifo && fifo_in_tready;

enum { IDLE, OUT_PREAMBLE, OUT_DATA } state;

assign maxis_tvalid = state == OUT_PREAMBLE || (state == OUT_DATA && fifo_out_tvalid);
assign fifo_out_tready = state == OUT_DATA && maxis_tready;

assign maxis_tdata = state == OUT_DATA ? fifo_out_tdata.tdata : PREAMBLE;
assign maxis_tkeep = state == OUT_DATA ? fifo_out_tdata.tkeep : '1;
assign maxis_tuser = state == OUT_DATA && fifo_out_tdata.tuser;
assign maxis_tlast = state == OUT_DATA && fifo_out_tdata.tlast;

always @(posedge clock) begin
    if( !aresetn ) begin
        state <= IDLE;
        flushing_fifo <= 0;
    end 
    else begin
        flushing_fifo <= maxis_tvalid && maxis_tready && maxis_tlast ? 0
                       : saxis_tvalid && saxis_tready && saxis_tlast ? 1
                       : flushing_fifo;
        
        case(state)
        IDLE: begin
            if( fifo_in_tvalid ) begin
                state <= OUT_PREAMBLE;
            end
        end
        OUT_PREAMBLE: begin
            if( maxis_tvalid && maxis_tready ) begin
                state <= OUT_DATA;
            end
        end
        OUT_DATA: begin
            if( maxis_tvalid && maxis_tready && maxis_tlast ) begin
                state <= IDLE;
            end
        end
        endcase
    end
end

endmodule

`default_nettype wire
