// Symbol injector for the loopback self-test transmitter: replaces the trace
// core's 10-bit symbol stream with a host-loaded list of raw symbols, so the
// receiver (EasyCDR IP) can be probed with arbitrary code groups (running
// disparity violations, invalid codes, every K code, shifted commas ...).
//
// Host side (clk_sys): the list is written one symbol at a time (i_wr_*),
// then i_set latches {mode, len}: mode 0 = pass the core stream, 1 = play the
// list once then pass, 2 = loop the list. Symbol bit 0 is the first bit on
// the wire (same convention as easycdr_trace_tx / OSER10 D0).
module trace_sym_inject #(
    parameter AW = 6                   // list depth 2^AW symbols
) (
    input  wire          clk_sys,
    input  wire          rst_sys,
    input  wire          i_wr_valid,
    input  wire [AW-1:0] i_wr_idx,
    input  wire [9:0]    i_wr_data,
    input  wire          i_set,
    input  wire [1:0]    i_mode,
    input  wire [AW:0]   i_len,         // 1..2^AW

    input  wire          txclk,
    input  wire          txrstn,
    input  wire [9:0]    i_core_sym,
    output reg  [9:0]    o_sym,
    output reg           o_active       // 1 while list symbols are on the wire
);
    reg [9:0]  list [0:(1<<AW)-1];
    reg [1:0]  mode_s;
    reg [AW:0] len_s;
    reg        set_tgl;
    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys) begin
            mode_s  <= 2'd0;
            len_s   <= 0;
            set_tgl <= 1'b0;
        end else begin
            if (i_wr_valid) list[i_wr_idx] <= i_wr_data;
            if (i_set) begin
                mode_s  <= i_mode;
                len_s   <= i_len;
                set_tgl <= ~set_tgl;
            end
        end
    end

    // tx domain: mode/len are quasi-static (written before set), captured on the toggle
    reg [2:0]  set_t;
    reg [1:0]  mode_t;
    reg [AW:0] len_t;
    reg [AW:0] idx;
    wire       set_evt = set_t[2] ^ set_t[1];
    wire       last    = (idx == len_t - 1'b1);
    always @(posedge txclk or negedge txrstn) begin
        if (!txrstn) begin
            set_t    <= 3'b000;
            mode_t   <= 2'd0;
            len_t    <= 0;
            idx      <= 0;
            o_active <= 1'b0;
            o_sym    <= 10'd0;
        end else begin
            set_t <= {set_t[1:0], set_tgl};
            if (set_evt) begin
                mode_t   <= mode_s;
                len_t    <= len_s;
                idx      <= 0;
                o_active <= (mode_s != 2'd0) && (len_s != 0);
            end else if (o_active) begin
                if (last) begin
                    idx <= 0;
                    if (mode_t == 2'd1) o_active <= 1'b0;   // one-shot done
                end else begin
                    idx <= idx + 1'b1;
                end
            end
            o_sym <= o_active ? list[idx[AW-1:0]] : i_core_sym;
        end
    end
endmodule
