`default_nettype none

module append_crc (
    input wire clock,
    input wire aresetn,
    
    input  wire [7:0]  saxis_tdata,
    input  wire        saxis_tvalid,
    output wire        saxis_tready,
    input  wire        saxis_tlast,
    input  wire        saxis_tuser,

    output wire [7:0]  maxis_tdata,
    output wire        maxis_tvalid,
    input  wire        maxis_tready,
    output wire        maxis_tlast,
    output wire        maxis_tuser
);

logic [31:0] crc_out;

crc_mac crc_mac_inst(
    .clock(clock),
    .aresetn(aresetn),

    .saxis_tdata (saxis_tdata),
    .saxis_tvalid(saxis_tvalid),
    .saxis_tready(saxis_tready),
    .saxis_tlast (saxis_tlast),
    .saxis_tuser (saxis_tuser),

    .maxis_tdata (input_tdata),
    .maxis_tvalid(input_tvalid),
    .maxis_tready(input_tready),
    .maxis_tlast (input_tlast),
    .maxis_tuser (input_tuser),

    .crc_out(crc_out)
);

logic [7:0] input_tdata;
logic input_tvalid;
logic input_tready;
logic input_tlast;
logic input_tuser;

logic [7:0] output_tdata;
logic       output_tvalid;
logic       output_tready;
logic       output_tlast;
logic       output_tuser;

typedef enum {
    S_RESET,
    S_IDLE,
    S_DATA,
    S_CRC_0,
    S_CRC_1,
    S_CRC_2,
    S_CRC_3
} state_t;

state_t state = S_RESET;

assign maxis_tdata  = output_tdata;
assign maxis_tvalid = output_tvalid;
assign output_tready = maxis_tready;
assign maxis_tlast  = output_tlast && state == S_CRC_3;
assign maxis_tuser  = output_tuser;

always_comb begin
    case(state)
    S_IDLE: begin
        input_tready <= 1;
    end
    S_DATA: begin
        input_tready <= !output_tvalid || output_tvalid && output_tready && !output_tlast;
    end
    default: input_tready <= 0;
    endcase
end

always_ff @(posedge clock) begin
    if( !aresetn ) begin
        state <= S_RESET;
        output_tvalid <= 0;
        output_tdata <= 0;
        output_tuser <= 0;
        output_tlast <= 0;
    end
    else begin
        case( state )
        S_RESET: begin
            state <= S_IDLE;
            output_tvalid <= 0;
            output_tdata <= 0;
            output_tuser <= 0;
            output_tlast <= 0;
        end
        S_IDLE: begin
            if( input_tvalid ) begin
                output_tvalid <= 1;
                output_tdata <= input_tdata;
                output_tlast <= input_tlast;
                output_tuser <= input_tuser;
                state <= S_DATA;
            end
        end
        S_DATA: begin
            if( output_tvalid && output_tready ) begin
                if( output_tlast ) begin
                    output_tdata <= crc_out[7:0];
                    state <= S_CRC_0;
                end
                else begin
                    output_tvalid <= input_tvalid;
                    output_tdata <= input_tdata;
                    output_tuser <= input_tuser;
                    output_tlast <= input_tlast;
                end
            end
            else if( input_tvalid && input_tready ) begin
                output_tvalid <= input_tvalid;
                output_tdata <= input_tdata;
                output_tuser <= input_tuser;
                output_tlast <= input_tlast;
            end
        end
        S_CRC_0: begin
            if( output_tready ) begin
                output_tdata <= crc_out[15:8];
                state <= S_CRC_1;
            end
        end
        S_CRC_1: begin
            if( output_tready ) begin
                output_tdata <= crc_out[23:16];
                state <= S_CRC_2;
            end
        end
        S_CRC_2: begin
            if( output_tready ) begin
                output_tdata <= crc_out[31:24];
                state <= S_CRC_3;
            end
        end
        S_CRC_3: begin
            if( output_tready ) begin
                output_tdata <= 0;
                output_tvalid <= 0;
                output_tlast <= 0;
                state <= S_IDLE;
            end
        end
        endcase
    end
end

endmodule

`default_nettype wire
