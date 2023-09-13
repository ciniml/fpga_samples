`default_nettype none

module axis_mux (
    input wire clock,
    input wire aresetn,

    output reg [7:0]  maxis_tdata,
    output reg        maxis_tvalid,
    input  wire       maxis_tready,
    output reg        maxis_tuser,
    output reg        maxis_tlast,

    input  wire [7:0] saxis_0_tdata,
    input  wire       saxis_0_tvalid,
    output reg        saxis_0_tready,
    input  wire       saxis_0_tuser,
    input  wire       saxis_0_tlast,

    input  wire [7:0] saxis_1_tdata,
    input  wire       saxis_1_tvalid,
    output reg        saxis_1_tready,
    input  wire       saxis_1_tuser,
    input  wire       saxis_1_tlast
);

typedef enum {
    IDLE,       // No operation
    OUTPUT0,    // Output stream 0
    OUTPUT1     // Output stream 1
} state_t;

state_t state = IDLE;

// TREADY
always_comb begin
    case(state)
    IDLE: begin 
        saxis_0_tready <= 0;
        saxis_1_tready <= 0;
    end
    OUTPUT0: begin
        saxis_0_tready <= !maxis_tvalid || maxis_tready;
        saxis_1_tready <= 0;
    end
    OUTPUT1: begin
        saxis_0_tready <= 0;
        saxis_1_tready <= !maxis_tvalid || maxis_tready;
    end
    endcase
end

always_ff @(posedge clock) begin
    if( !aresetn ) begin
        state <= IDLE;
        maxis_tvalid <= 0;
    end
    else begin
        if( maxis_tvalid && maxis_tready ) begin
            maxis_tvalid <= 0;
        end

        case(state)
        IDLE: begin
            if( saxis_0_tvalid ) begin
                state <= OUTPUT0;
            end
            else if( saxis_1_tvalid ) begin
                state <= OUTPUT1;
            end
        end
        OUTPUT0: begin
            if(saxis_0_tvalid && saxis_0_tready) begin
                maxis_tvalid <= 1;
                maxis_tdata <= saxis_0_tdata;
                maxis_tuser <= saxis_0_tuser;
                maxis_tlast <= saxis_0_tlast;
                if( saxis_0_tlast ) begin
                    state <= IDLE;
                end
            end
        end
        OUTPUT1: begin
            if(saxis_1_tvalid && saxis_1_tready) begin
                maxis_tvalid <= 1;
                maxis_tdata <= saxis_1_tdata;
                maxis_tuser <= saxis_1_tuser;
                maxis_tlast <= saxis_1_tlast;
                if( saxis_1_tlast ) begin
                    state <= IDLE;
                end
            end
        end
        endcase
    end
end

endmodule

`default_nettype wire
