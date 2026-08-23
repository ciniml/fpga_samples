// Phase 3: trace frontend.
//
// Samples a WIDTH-bit signal in the link clock domain, records a
// timestamped entry whenever it changes, and serializes the records into
// the link byte stream:
//
//   [K28.1][ts 7:0][ts 15:8][ts 23:16][data 7:0][data 15:8]
//
// K28.2 is emitted (once per event) when the record FIFO overflowed and
// records were dropped. The timestamp counts link parallel-clock cycles
// (10ns at 1Gbps).
module trace_frontend #(
    parameter TS_BITS = 24
) (
    input  wire        clk,
    input  wire        rstn,
    input  wire [15:0] sig,      // asynchronous trace inputs allowed

    // byte stream towards easycdr_trace_tx_core
    output reg         o_valid,
    output reg         o_is_k,
    output reg  [7:0]  o_data,
    input  wire        i_ready
);
    localparam [7:0] K28_1 = 8'h3c;  // start of record
    localparam [7:0] K28_2 = 8'h5c;  // overflow notification

    //------------------------------------------------------------------
    // input synchronizer + change detector + timestamp
    //------------------------------------------------------------------
    reg [15:0] sig_meta, sig_s, sig_prev;
    reg        init_done;
    reg [TS_BITS-1:0] ts;

    always @(posedge clk) begin
        sig_meta <= sig;
        sig_s    <= sig_meta;
    end

    //------------------------------------------------------------------
    // record FIFO: {ts, data}, 16 entries
    //------------------------------------------------------------------
    reg [TS_BITS+16-1:0] fifo [0:15];
    reg [4:0] wp, rp;
    wire fifo_empty = (wp == rp);
    wire fifo_full  = (wp[4] != rp[4]) && (wp[3:0] == rp[3:0]);
    reg  ovf_pending;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sig_prev  <= 16'h0000;
            init_done <= 1'b0;
            ts        <= {TS_BITS{1'b0}};
            wp        <= 5'd0;
            ovf_pending <= 1'b0;
        end else begin
            ts <= ts + 1'b1;
            if (!init_done || sig_s != sig_prev) begin
                sig_prev  <= sig_s;
                init_done <= 1'b1;
                if (!fifo_full) begin
                    fifo[wp[3:0]] <= {ts, sig_s};
                    wp <= wp + 1'b1;
                end else begin
                    ovf_pending <= 1'b1;   // record dropped
                end
            end
            if (ovf_ack)
                ovf_pending <= 1'b0;
        end
    end

    //------------------------------------------------------------------
    // byte serializer
    //------------------------------------------------------------------
    localparam SB_IDLE = 3'd0;  // emit K28.1/K28.2 or nothing
    localparam SB_TS0  = 3'd1;
    localparam SB_TS1  = 3'd2;
    localparam SB_TS2  = 3'd3;
    localparam SB_D0   = 3'd4;
    localparam SB_D1   = 3'd5;

    reg [2:0] sb;
    reg [TS_BITS+16-1:0] cur;
    reg ovf_ack;

    wire consumed = o_valid && i_ready;
    wire can_load = !o_valid || i_ready;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            sb      <= SB_IDLE;
            rp      <= 5'd0;
            cur     <= {(TS_BITS+16){1'b0}};
            o_valid <= 1'b0;
            o_is_k  <= 1'b0;
            o_data  <= 8'h00;
            ovf_ack <= 1'b0;
        end else begin
            ovf_ack <= 1'b0;
            if (can_load) begin
                case (sb)
                SB_IDLE: begin
                    if (ovf_pending && !ovf_ack) begin
                        o_valid <= 1'b1;
                        o_is_k  <= 1'b1;
                        o_data  <= K28_2;
                        ovf_ack <= 1'b1;
                    end else if (!fifo_empty) begin
                        cur     <= fifo[rp[3:0]];
                        rp      <= rp + 1'b1;
                        o_valid <= 1'b1;
                        o_is_k  <= 1'b1;
                        o_data  <= K28_1;
                        sb      <= SB_TS0;
                    end else begin
                        o_valid <= 1'b0;
                    end
                end
                SB_TS0: begin o_valid<=1'b1; o_is_k<=1'b0; o_data<=cur[16 +: 8];         sb<=SB_TS1; end
                SB_TS1: begin o_valid<=1'b1; o_is_k<=1'b0; o_data<=cur[24 +: 8];         sb<=SB_TS2; end
                SB_TS2: begin o_valid<=1'b1; o_is_k<=1'b0; o_data<=cur[TS_BITS+16-1 -: 8]; sb<=SB_D0; end
                SB_D0:  begin o_valid<=1'b1; o_is_k<=1'b0; o_data<=cur[7:0];             sb<=SB_D1; end
                SB_D1:  begin o_valid<=1'b1; o_is_k<=1'b0; o_data<=cur[15:8];            sb<=SB_IDLE; end
                default: sb <= SB_IDLE;
                endcase
            end
        end
    end

endmodule
