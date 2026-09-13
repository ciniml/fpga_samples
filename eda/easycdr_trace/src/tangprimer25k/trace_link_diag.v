// Link diagnostics for the trace receiver: event counters in the receive
// clock domain, snapshot + clear on request from the host clock domain.
//
// Host command 'L' (trace_capture) returns 14 bytes:
//   0     status : bit0 PLL lock, bit1 word aligned, bit2 descriptor seen,
//                  bit3 comma watchdog ok, bit4 IP reset active,
//                  bit7 no reply from the receive clock (clock dead)
//   1     VER of the last descriptor (0 = none)
//   2-3   K28.5 commas          (u16 LE, since the previous 'L', saturating)
//   4-5   K28.1 record starts
//   6-7   8b10b decode errors
//   8-9   K28.2 overflow markers
//   10-11 K28.4 descriptors
//   12-13 data words
// A healthy idle link shows commas > 0, errors = 0; records = 0 means the
// transmitter is armed / disabled / not present.
module trace_link_diag (
    input  wire         pclk,
    input  wire         prst,
    input  wire         i_data_en,     // word strobe from the CDR
    input  wire [8:0]   i_word,        // {K, byte}
    input  wire         i_decerr,      // decode error strobe (with i_data_en)
    input  wire [7:0]   i_status,      // quasi-static status bits (see above, bit7 unused)
    input  wire [7:0]   i_desc_ver,

    input  wire         clk_sys,
    input  wire         rst_sys,
    input  wire         i_req,         // one clock: take a snapshot
    output reg          o_done,        // one clock: o_data valid
    output reg  [111:0] o_data         // 14 bytes, byte 0 in [7:0]
);
    localparam [7:0] K28_1 = 8'h3c, K28_2 = 8'h5c, K28_4 = 8'h9c, K28_5 = 8'hbc;

    // request: clk_sys -> pclk
    reg       req_tgl;
    reg [2:0] req_p;
    always @(posedge clk_sys or posedge rst_sys)
        if (rst_sys) req_tgl <= 1'b0; else if (i_req) req_tgl <= ~req_tgl;
    always @(posedge pclk or posedge prst)
        if (prst) req_p <= 3'b000; else req_p <= {req_p[1:0], req_tgl};
    wire snap = req_p[2] ^ req_p[1];

    // counters (pclk)
    reg [15:0] c_comma, c_rec, c_err, c_ovf, c_desc, c_data;
    reg [95:0] snap_cnt;
    reg [7:0]  snap_status, snap_ver;
    reg        ack_tgl;
    wire is_k = i_data_en && i_word[8];
    wire is_d = i_data_en && !i_word[8];
    function [15:0] inc(input [15:0] c, input e);
        inc = (e && c != 16'hffff) ? c + 1'b1 : c;
    endfunction
    always @(posedge pclk or posedge prst) begin
        if (prst) begin
            c_comma <= 0; c_rec <= 0; c_err <= 0; c_ovf <= 0; c_desc <= 0; c_data <= 0;
            snap_cnt <= 0; snap_status <= 0; snap_ver <= 0; ack_tgl <= 1'b0;
        end else begin
            if (snap) begin
                snap_cnt    <= {c_data, c_desc, c_ovf, c_err, c_rec, c_comma};
                snap_status <= i_status;
                snap_ver    <= i_desc_ver;
                ack_tgl     <= ~ack_tgl;
                c_comma <= 0; c_rec <= 0; c_err <= 0; c_ovf <= 0; c_desc <= 0; c_data <= 0;
            end else begin
                c_comma <= inc(c_comma, is_k && i_word[7:0] == K28_5);
                c_rec   <= inc(c_rec,   is_k && i_word[7:0] == K28_1);
                c_ovf   <= inc(c_ovf,   is_k && i_word[7:0] == K28_2);
                c_desc  <= inc(c_desc,  is_k && i_word[7:0] == K28_4);
                c_err   <= inc(c_err,   i_data_en && i_decerr);
                c_data  <= inc(c_data,  is_d);
            end
        end
    end

    // ack: pclk -> clk_sys, with a timeout in case pclk is dead
    reg [2:0]  ack_s;
    reg        waiting;
    reg [15:0] wait_cnt;
    always @(posedge clk_sys or posedge rst_sys) begin
        if (rst_sys) begin
            ack_s <= 3'b000; waiting <= 1'b0; wait_cnt <= 16'd0;
            o_done <= 1'b0; o_data <= 112'd0;
        end else begin
            ack_s  <= {ack_s[1:0], ack_tgl};
            o_done <= 1'b0;
            if (i_req) begin
                waiting  <= 1'b1;
                wait_cnt <= 16'd0;
            end else if (waiting) begin
                wait_cnt <= wait_cnt + 1'b1;
                if (ack_s[2] != ack_s[1]) begin
                    waiting <= 1'b0;
                    o_done  <= 1'b1;
                    o_data  <= {snap_cnt, snap_ver, 1'b0, snap_status[6:0]};
                end else if (&wait_cnt) begin
                    waiting <= 1'b0;
                    o_done  <= 1'b1;
                    o_data  <= {96'd0, 8'd0, 8'h80};   // bit7: receive clock did not answer
                end
            end
        end
    end
endmodule
