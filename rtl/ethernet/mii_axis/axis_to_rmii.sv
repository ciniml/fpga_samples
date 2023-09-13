`default_nettype none

module axis_to_rmii (
    input wire clock,
    input wire aresetn,
    
    output logic [3:0] rmii_d,
    output logic       rmii_en,

    input wire  [7:0]  saxis_tdata,
    input wire         saxis_tvalid,
    output logic       saxis_tready,
    input wire         saxis_tlast
);

logic [7:0] tdata;
logic       tlast;

typedef enum  {
    S_RESET,
    S_IDLE,
    S_PHASE_0,
    S_PHASE_1,
    S_PHASE_2,
    S_PHASE_3,
    S_INTERFRAME
} state_t;

state_t state = S_RESET;

always_comb begin
    case(state)
    S_IDLE: saxis_tready = 1;
    S_PHASE_3: saxis_tready = !tlast;
    default: saxis_tready = 0;
    endcase
end

logic [23:0] interframe = 0;

always_ff @(posedge clock) begin
    if( !aresetn ) begin
        state <= S_RESET;
        tlast <= 0;
        rmii_d <= 0;
        rmii_en <= 0;
    end
    else begin
        case(state)
        S_RESET: begin
            state <= S_IDLE;
            tlast <= 0;
        end
        S_IDLE: begin
            if( saxis_tvalid ) begin
                tdata <= saxis_tdata;
                tlast <= saxis_tlast;
                state <= S_PHASE_0;
            end
        end
        S_PHASE_0: begin
            rmii_d <= tdata[1:0];
            rmii_en <= 1;
            state <= S_PHASE_1;
        end
        S_PHASE_1: begin
            rmii_d <= tdata[3:2];
            rmii_en <= 1;
            state <= S_PHASE_2;
        end
        S_PHASE_2: begin
            rmii_d <= tdata[5:4];
            rmii_en <= 1;
            state <= S_PHASE_3;
        end
        S_PHASE_3: begin
            rmii_d <= tdata[7:6];
            rmii_en <= 1;
            if( !tlast && saxis_tvalid ) begin
                tdata <= saxis_tdata;
                tlast <= saxis_tlast;
                state <= S_PHASE_0;
            end
            else begin
                state <= S_INTERFRAME;
                interframe <= 1;
            end
        end
        S_INTERFRAME: begin
            rmii_en <= 0;
            tlast <= 0;
            interframe <= interframe << 1;
            if( |interframe == 0 ) begin
                state <= S_IDLE;
            end
        end
        endcase
    end
end

endmodule

`default_nettype wire
