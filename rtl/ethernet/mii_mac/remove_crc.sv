`default_nettype none

module remove_crc (
    input wire clock,
    input wire aresetn,
    
    input  wire [7:0] saxis_tdata,
    input  wire       saxis_tvalid,
    output reg       saxis_tready,
    input  wire       saxis_tlast,
    input  wire       saxis_tuser,

    output reg   [7:0]  maxis_tdata,
    output reg          maxis_tvalid,
    input  wire         maxis_tready,
    output reg          maxis_tlast,
    output reg          maxis_tuser,

    output reg [31:0] crc
);

logic [31:0] buffer;

typedef enum {
    S_RESET,
    S_FILL_0,
    S_FILL_1,
    S_FILL_2,
    S_FILL_3,
    S_DATA
} state_t;

state_t state = S_RESET;

always_comb begin
    case(state)
    S_FILL_0: saxis_tready <= 1;
    S_FILL_1: saxis_tready <= 1;
    S_FILL_2: saxis_tready <= 1;
    S_FILL_3: saxis_tready <= 1;
    S_DATA: begin
        saxis_tready <= !maxis_tvalid || maxis_tvalid && maxis_tready && !maxis_tlast;
    end
    default: saxis_tready <= 0;
    endcase
end


always_ff @(posedge clock) begin
    if( !aresetn ) begin
        state <= S_RESET;
    end 
    else begin
        case( state )
        S_RESET: begin
            state <= S_FILL_0;
            maxis_tvalid <= 0;
            maxis_tlast <= 0;
            crc <= 0;
        end
        S_FILL_0: begin
            if( saxis_tvalid ) begin
                buffer[7:0] <= saxis_tdata;
                if( saxis_tlast ) begin
                    state <= S_FILL_0;
                end
                else begin
                    state <= S_FILL_1;
                end
            end
        end
        S_FILL_1: begin
            if( saxis_tvalid ) begin
                buffer[15:8] <= saxis_tdata;
                if( saxis_tlast ) begin
                    state <= S_FILL_0;
                end
                else begin
                    state <= S_FILL_2;
                end
            end
        end
        S_FILL_2: begin
            if( saxis_tvalid ) begin
                buffer[23:16] <= saxis_tdata;
                if( saxis_tlast ) begin
                    state <= S_FILL_0;
                end
                else begin
                    state <= S_FILL_3;
                end
            end
        end
        S_FILL_3: begin
            if( saxis_tvalid ) begin
                buffer[31:24] <= saxis_tdata;
                if( saxis_tlast ) begin
                    state <= S_FILL_0;
                end
                else begin
                    state <= S_DATA;
                end
            end
        end
        S_DATA: begin
            if( maxis_tvalid && maxis_tready ) begin
                if( maxis_tlast ) begin
                    maxis_tvalid <= 0;
                    maxis_tlast <= 0;
                    state <= S_FILL_0;
                end
                else if( saxis_tvalid && saxis_tready ) begin
                    maxis_tdata <= buffer[7:0];
                    maxis_tvalid <= 1;
                    maxis_tlast <= saxis_tlast;
                    maxis_tuser <= saxis_tuser;
                    buffer[23:0] <= buffer[31:8];
                    buffer[31:24] <= saxis_tdata;
                end
                else begin
                    maxis_tvalid <= 0;
                end
            end
            else if( saxis_tvalid && saxis_tready ) begin
                maxis_tdata <= buffer[7:0];
                maxis_tvalid <= 1;
                maxis_tlast <= saxis_tlast;
                maxis_tuser <= saxis_tuser;
                buffer[23:0] <= buffer[31:8];
                buffer[31:24] <= saxis_tdata;
            end

            if( saxis_tvalid && saxis_tready && saxis_tlast ) begin
                crc <= {saxis_tdata, buffer[31:8]};
            end
        end
        endcase
        
    end
end

endmodule

`default_nettype wire
