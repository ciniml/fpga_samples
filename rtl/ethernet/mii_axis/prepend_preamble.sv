`default_nettype none

module prepend_preamble #(
    parameter bit [7:0] PREAMBLE = 8'h55,
    parameter bit [7:0] SFD = 8'hd5,
    parameter int PREAMBLE_LENGTH = 7
) (
    input wire clock,
    input wire aresetn,

    input  wire  [7:0]  saxis_tdata,
    input  wire         saxis_tvalid,
    output reg          saxis_tready,
    input  wire         saxis_tlast,

    output reg   [7:0]  maxis_tdata,
    output reg          maxis_tvalid,
    input  wire         maxis_tready,
    output reg          maxis_tlast
);

logic [$clog2(PREAMBLE_LENGTH)-1:0] preamble_count = 0;

typedef enum  {
    S_RESET,
    S_IDLE,
    S_PREAMBLE,
    S_SFD,
    S_DATA
} state_t;


state_t state = S_RESET;

always_comb begin
    case(state)
    S_SFD: begin
        saxis_tready <= maxis_tready;
    end
    S_DATA: begin
        saxis_tready <= !maxis_tvalid || maxis_tvalid && maxis_tready && !maxis_tlast;
    end
    default: saxis_tready <= 0;
    endcase
end

always_ff @(posedge clock) begin
    if( !aresetn ) begin
        maxis_tdata <= 0;
        maxis_tvalid <= 0;
        maxis_tlast <= 0;
    end
    else begin
        case(state)
        S_RESET: begin
            state <= S_IDLE;
            maxis_tlast <= 0;
        end
        S_IDLE: begin
            if( saxis_tvalid ) begin
                preamble_count <= PREAMBLE_LENGTH - 1;
                maxis_tdata <= PREAMBLE;
                maxis_tvalid <= 1;
                maxis_tlast <= 0;
                state <= S_PREAMBLE;
            end
        end
        S_PREAMBLE: begin
            if( maxis_tready ) begin
                preamble_count <= preamble_count - 1;
                if( preamble_count == 0 )  begin
                    maxis_tdata <= SFD;
                    state <= S_SFD;
                end
            end
        end
        S_SFD: begin
            if( maxis_tready ) begin
                maxis_tdata <= saxis_tdata;
                maxis_tlast <= saxis_tlast;
                state <= S_DATA;
            end
        end
        S_DATA: begin
            if( maxis_tvalid && maxis_tready ) begin
                if( maxis_tlast ) begin
                    maxis_tvalid <= 0;
                    state <= S_IDLE;
                end
                else begin
                    maxis_tvalid <= saxis_tvalid;
                    maxis_tdata <= saxis_tdata;
                    maxis_tlast <= saxis_tlast;
                end
            end
            else if( saxis_tvalid && saxis_tready ) begin
                maxis_tvalid <= saxis_tvalid;
                maxis_tdata <= saxis_tdata;
                maxis_tlast <= saxis_tlast;
            end
        end
        endcase
    end
end

endmodule

`default_nettype wire
