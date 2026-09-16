// End-to-end control-path test (device-primitive-free):
//
//   host bytes -> trace_capture ('X') -> FIFO -> ManchesterTx @50MHz
//     -> wire -> ManchesterRx @100MHz -> CtrlFrameRx -> TraceCtrlRegs
//     -> easycdr_trace_tx (enable / ignore mask / desc_req / soft reset)
//     -> 8b10b symbols -> displayport_decoder_8b10b -> trace_rx_decoder
//     -> trace_capture buffer -> 'D' dump -> record check
//
// Everything except the PLL/OSER10/IBUF path of the real designs.
`timescale 1ns/1ps
module e2e_ctrl_tb #(
    parameter real SCLK_PERIOD = 37.037,  // sample clock period [ns] (27MHz as on the Nano9K demo)
    parameter int  TX_WIDTH    = 16       // transmitter width; the RX side takes it from the descriptor
) ();
    localparam MB = TX_WIDTH / 8;         // control register byte offsets follow the width
    localparam A_TMASK = 8'h0c, A_TVAL = 8'h0c + MB, A_POST = 8'h0c + 2*MB;
    localparam ADDR_BITS = 8;             // small buffer for fast sim
    localparam ENTRIES   = 1 << ADDR_BITS;

    logic clk100 = 0, clk50 = 0, sclk = 0, rst = 1;
    always #5  clk100 = ~clk100;
    always #10 clk50  = ~clk50;
    always #(SCLK_PERIOD/2) sclk = ~sclk;
    wire rstn = ~rst;

    // ---------------- trace transmitter side (clk100) ----------------
    logic [TX_WIDTH-1:0] trace_sig = '0;
    logic        soft_reset, trace_en, desc_req;
    logic [TX_WIDTH-1:0] ignore_mask;
    wire         trace_rstn = rstn & ~soft_reset;
    wire  [9:0]  tx_symbol;

    localparam [31:0] CFG_HASH = 32'h02d268ca;   // tracemap.py maps/nano9k_demo.map
    easycdr_trace_tx #(.WIDTH(TX_WIDTH), .TS_BITS(24), .DESC_INTERVAL(4096), .CFG_HASH(CFG_HASH)) u_trace_tx(
        .sclk(sclk), .srstn(1'b1), .sig(trace_sig),
        .clk(clk100), .rstn(trace_rstn),
        .i_enable(trace_en), .i_ignore_mask(ignore_mask), .i_desc_req(desc_req),
        .i_periodic_en(periodic_en), .i_change_dis(change_dis), .i_period(period),
        .i_arm(arm), .i_trig_mask(trig_mask), .i_trig_value(trig_value), .i_post(post),
        .o_symbol(tx_symbol), .o_overflow(), .o_armed(), .o_triggered(), .o_done());
    logic arm, periodic_en, change_dis; logic [23:0] period; logic [TX_WIDTH-1:0] trig_mask, trig_value; logic [15:0] post;

    // 8b10b decode (same clock domain; symbol-per-cycle)
    wire       dec_valid, dec_is_k, dec_err;
    wire [7:0] dec_data;
    displayport_decoder_8b10b u_dec(
        .i_clk(clk100), .i_rstn(trace_rstn), .i_valid(1'b1), .i_symbol(tx_symbol),
        .o_valid(dec_valid), .o_data(dec_data), .o_is_k(dec_is_k), .o_code_err(dec_err));
    wire [8:0] rx_word = {dec_is_k, dec_data};
    localparam [7:0] K28_1 = 8'h3c, K28_2 = 8'h5c, K28_5 = 8'hbc, K28_3 = 8'h7c;
    wire desc_busy;
    wire cap_valid = dec_valid && !desc_busy &&
                     (!dec_is_k || dec_data == K28_1 || dec_data == K28_2);

    wire        rec_valid;
    wire [31:0] rec_ts;
    wire [63:0] rec_data;
    wire [7:0]  desc_ver, desc_width, desc_tsbits, desc_flags;
    wire [31:0] desc_hash;
    trace_rx_decoder #(.MAX_WIDTH(64), .MAX_TS_BITS(32)) u_rxdec(
        .clk(clk100), .rst(rst), .in_valid(dec_valid), .in_word(rx_word),
        .rec_valid(rec_valid), .rec_ts(rec_ts), .rec_data(rec_data), .ovf_seen(),
        .o_desc_ver(desc_ver), .o_desc_width(desc_width),
        .o_desc_tsbits(desc_tsbits), .o_desc_flags(desc_flags), .o_desc_hash(desc_hash),
        .o_desc_busy(desc_busy));

    // ---------------- host side (clk50) ----------------
    logic       h_rx_valid = 0;
    logic [7:0] h_rx_data = 0;
    wire        h_tx_valid;
    wire  [7:0] h_tx_data;
    wire        fwd_valid;
    wire  [7:0] fwd_data;

    trace_capture #(.ADDR_BITS(ADDR_BITS), .DATA_BITS(9), .MAX_WIDTH(64)) u_cap(
        .pclk(clk100), .prst(rst), .in_valid(cap_valid), .in_data(rx_word),
        .rec_valid(rec_valid), .rec_data(rec_data),
        .i_desc_ver(desc_ver), .i_desc_width(desc_width), .i_desc_tsbits(desc_tsbits), .i_desc_flags(desc_flags), .i_desc_hash(desc_hash),
        .clk_sys(clk50), .rst_sys(rst),
        .h_rx_valid(h_rx_valid), .h_rx_data(h_rx_data),
        .h_tx_valid(h_tx_valid), .h_tx_data(h_tx_data), .h_tx_ready(1'b1),
        .o_fwd_valid(fwd_valid), .o_fwd_data(fwd_data),
        .o_diag_req(diag_req), .i_diag_done(diag_done), .i_diag_data(diag_data));
    wire diag_req, diag_done; wire [111:0] diag_data;
    trace_link_diag u_diag(
        .pclk(clk100), .prst(rst), .i_data_en(dec_valid), .i_word(rx_word), .i_decerr(dec_err),
        .i_status({4'b0, 1'b1, desc_ver != 8'd0, 1'b1, 1'b1}), .i_desc_ver(desc_ver),
        .clk_sys(clk50), .rst_sys(rst), .i_req(diag_req), .o_done(diag_done), .o_data(diag_data));

    // forward FIFO + Manchester TX (as in the 25K top)
    logic [7:0] cfifo [0:15];
    logic [4:0] cwp = 0, crp = 0;
    wire cf_empty = (cwp == crp);
    wire ctrl_tx_ready, ctrl_txd;
    always @(posedge clk50) begin
        if (fwd_valid) begin cfifo[cwp[3:0]] <= fwd_data; cwp <= cwp + 1'b1; end
        if (ctrl_tx_ready && !cf_empty) crp <= crp + 1'b1;
    end
    ManchesterTx #(.BIT_CYCLES(25)) u_mtx(
        .i_clk(clk50), .i_rst(rst), .i_valid(!cf_empty), .i_data(cfifo[crp[3:0]]),
        .o_ready(ctrl_tx_ready), .o_txd(ctrl_txd));

    // ---------------- reverse channel RX (clk100, as in the Nano9K top)
    wire       cb_valid, cb_err;
    wire [7:0] cb_data;
    ManchesterRx #(.BIT_CYCLES(50)) u_mrx(
        .i_clk(clk100), .i_rst(rst), .i_rxd(ctrl_txd),
        .o_valid(cb_valid), .o_data(cb_data), .o_err(cb_err), .o_link());
    wire       wr_valid;
    wire [7:0] wr_addr, wr_data;
    CtrlFrameRx #(.GAP_TIMEOUT(65536)) u_cfrx(
        .i_clk(clk100), .i_rst(rst), .i_valid(cb_valid), .i_data(cb_data), .i_err(cb_err),
        .o_wr_valid(wr_valid), .o_wr_addr(wr_addr), .o_wr_data(wr_data), .o_frame_err());
    TraceCtrlRegs #(.WIDTH(TX_WIDTH), .RESET_CYCLES(64)) u_regs(
        .i_clk(clk100), .i_rst(rst), .i_wr_valid(wr_valid), .i_wr_addr(wr_addr), .i_wr_data(wr_data),
        .o_soft_reset(soft_reset), .o_enable(trace_en), .o_desc_req(desc_req),
        .o_ignore_mask(ignore_mask), .o_arm(arm), .o_periodic_en(periodic_en), .o_change_dis(change_dis),
        .o_period(period), .o_trig_mask(trig_mask), .o_trig_value(trig_value), .o_post(post));

    // ---------------- host driver / scoreboard ----------------
    int errors = 0;
    int rec_count = 0;
    logic [31:0] last_ts;
    logic [7:0] resp[$];
    always @(posedge clk50) if (h_tx_valid) resp.push_back(h_tx_data);
    always @(posedge clk100) if (rec_valid) begin rec_count++; last_ts = rec_ts; end

    task automatic hsend(input logic [7:0] b);
        @(negedge clk50); h_rx_valid = 1; h_rx_data = b;
        @(negedge clk50); h_rx_valid = 0;
    endtask
    function automatic logic [7:0] crc8(input logic [7:0] a, input logic [7:0] d);
        logic [7:0] c = 0;
        c ^= a; for (int i = 0; i < 8; i++) c = c[7] ? {c[6:0], 1'b0} ^ 8'h07 : {c[6:0], 1'b0};
        c ^= d; for (int i = 0; i < 8; i++) c = c[7] ? {c[6:0], 1'b0} ^ 8'h07 : {c[6:0], 1'b0};
        return c;
    endfunction
    // 'X' command with one control frame
    task automatic ctrl_write(input logic [7:0] addr, input logic [7:0] data);
        hsend("X"); hsend(8'd4);
        hsend(8'ha5); hsend(addr); hsend(data); hsend(crc8(addr, data));
        #40000;   // 4 bytes x 12 bit-times x 500ns + margin
    endtask
    task automatic check(input string what, input bit cond);
        if (!cond) begin $display("ERROR: %s", what); errors++; end
        else $display("ok: %s", what);
    endtask

    // decode a dump into records
    typedef struct { logic [23:0] ts; logic [63:0] data; } rec_t;
    localparam RL = 3 + MB;              // record bytes after K28.1
    rec_t recs[$];
    task automatic dump_and_parse();
        int n0;
        recs.delete(); resp.delete();
        hsend("D");
        wait (resp.size() == ENTRIES * 2);
        for (int i = 0; i < ENTRIES; ) begin
            logic k = resp[2*i][0];
            logic [7:0] b = resp[2*i+1];
            if (k && b == K28_1 && i + RL < ENTRIES) begin
                automatic bit clean = 1;
                for (int j = 1; j <= RL; j++) if (resp[2*(i+j)][0]) clean = 0;
                if (clean) begin
                    automatic rec_t r;
                    r.ts   = {resp[2*(i+3)+1], resp[2*(i+2)+1], resp[2*(i+1)+1]};
                    r.data = '0;
                    for (int j = 0; j < MB; j++) r.data[j*8 +: 8] = resp[2*(i+4+j)+1];
                    recs.push_back(r); i += 1 + RL; continue;
                end
            end
            i++;
        end
    endtask

    initial begin
        repeat (10) @(posedge clk50); rst = 0;
        #1000;

        // 0. descriptor is sent periodically -> latched at the decoder
        wait (desc_ver != 0);
        check("descriptor latched", desc_ver == 8'h02 && desc_width == TX_WIDTH[7:0] && desc_tsbits == 8'd24);
        check($sformatf("descriptor hash %08x", desc_hash), desc_hash == CFG_HASH);
        check("desc flags: enabled", desc_flags[0] == 1'b1);

        // 1. '?' returns descriptor + local ADDR_BITS
        repeat (4) @(posedge clk50);   // let the 2FF clk_sys sync settle
        resp.delete();
        hsend("?");
        wait (resp.size() == 8);
        check("'?' reply", resp[0] == 8'h02 && resp[1] == TX_WIDTH[7:0] && resp[2] == 8'd24 && resp[3] == ADDR_BITS[7:0]);
        check("'?' hash", {resp[7], resp[6], resp[5], resp[4]} == CFG_HASH);
        if (errors) $display("  '?' got: %02x %02x %02x %02x", resp[0], resp[1], resp[2], resp[3]);

        // 2. ignore mask: mask off bit 15..8, capture, only low-byte changes
        ctrl_write(8'h05, 8'hff);            // IGNORE_MASK[15:8] = ff
        check("mask set", ignore_mask[15:0] == 16'hff00);
        resp.delete(); hsend("S");
        #2000;
        rec_count = 0;
        for (int i = 0; i < 8; i++) begin
            @(negedge clk100); trace_sig[3:0] = i[3:0];  // visible changes
            @(negedge clk100); trace_sig[15]  = ~trace_sig[15]; // masked
            #500;
        end
        // masked toggles (8) must not add records: only the 8 visible
        // changes trigger (the record still samples bit15's current value)
        check($sformatf("mask suppresses triggers (recs=%0d)", rec_count),
              rec_count >= 7 && rec_count <= 10);
        // fill the rest of the 256-entry buffer so the capture freezes
        for (int i = 0; i < 60; i++) begin
            @(negedge clk100); trace_sig[3:0] = ~trace_sig[3:0];
            #500;
        end
        wait (resp.size() == 1);
        check("capture frozen ack", resp[0] == "K");
        dump_and_parse();
        begin
            automatic int vis = 0, msk = 0;
            for (int i = 1; i < recs.size(); i++) begin
                if ((recs[i].data[3:0] ^ recs[i-1].data[3:0]) != 0) vis++;
            end
            check($sformatf("records captured (records=%0d)", recs.size()), recs.size() >= 30);
        end

        // 3. disable: rec_valid must stay silent while trace_en = 0
        // (note: 'X' control frames are ignored while a capture is armed -
        //  configure first, then arm)
        ctrl_write(8'h00, 8'h00);            // ENABLE=0
        check("disabled", trace_en == 1'b0);
        #5000;
        rec_count = 0;
        for (int i = 0; i < 6; i++) begin
            @(negedge clk100); trace_sig[3:0] = ~trace_sig[3:0];
            #500;
        end
        #5000;
        check("no records while disabled", rec_count == 0);
        ctrl_write(8'h00, 8'h02);            // ENABLE=1 (emits one record)
        #5000;
        check("re-enable emits a record", rec_count >= 1);

        // 4. soft reset restarts the timestamp counter
        ctrl_write(8'h00, 8'h03);            // RESET | ENABLE
        #3000;                               // reset (64 cyc) + re-init record
        rec_count = 0;
        @(negedge clk100); trace_sig[3:0] = ~trace_sig[3:0];
        wait (rec_count != 0);
        check("ts restarted after soft reset", last_ts < 24'd3000);
        if (errors) $display("  last_ts = %0d", last_ts);

        // 5b. periodic sampling: change detection off, period 100 sample clocks -> 10 records in 1000 sclk
        ctrl_write(8'h08, 8'h03);            // PERIODIC | CHG_DIS
        ctrl_write(8'h09, 8'h64); ctrl_write(8'h0a, 8'h00); ctrl_write(8'h0b, 8'h00);   // 100
        #2000; rec_count = 0;
        #(SCLK_PERIOD * 1000);
        check($sformatf("periodic records ~10 in 1000 sclk at 100-cycle period (got %0d)", rec_count), rec_count >= 9 && rec_count <= 11);
        @(negedge clk100); trace_sig[3:0] = ~trace_sig[3:0]; #5000;
        ctrl_write(8'h08, 8'h00);            // back to change detection
        // 5c. TX trigger: arm on bit8 == 1, post = 3 records
        ctrl_write(A_TMASK, 8'h00); ctrl_write(A_TMASK + 1, 8'h01);   // TRIG_MASK = 0x0100
        ctrl_write(A_TVAL, 8'h00);  ctrl_write(A_TVAL + 1, 8'h01);    // TRIG_VALUE = 0x0100
        ctrl_write(A_POST, 8'h03);  ctrl_write(A_POST + 1, 8'h00);    // POST = 3
        ctrl_write(8'h00, 8'h0e);                              // ARM | ENABLE | DESC_REQ (flags refresh)
        #3000; rec_count = 0;
        for (int i = 0; i < 4; i++) begin @(negedge clk100); trace_sig[3:0] = ~trace_sig[3:0]; #500; end
        check($sformatf("armed: no records before trigger (got %0d)", rec_count), rec_count == 0);
        check("flags: armed", desc_flags[1] == 1'b1);
        @(negedge clk100); trace_sig[8] = 1'b1;               // trigger
        #500;
        for (int i = 0; i < 6; i++) begin @(negedge clk100); trace_sig[3:0] = ~trace_sig[3:0]; #500; end
        #2000;
        check($sformatf("trigger sample + 3 post records (got %0d)", rec_count), rec_count == 4);
        wait (desc_flags[3] == 1'b1 || $time > 500_000_000);
        check("flags: done", desc_flags[3] == 1'b1);
        @(negedge clk100); trace_sig[8] = 1'b0;
        ctrl_write(8'h00, 8'h0e); #2000;                       // re-arm (+ descriptor)
        check("flags: armed again", desc_flags[1] == 1'b1);
        ctrl_write(A_POST, 8'h00); ctrl_write(A_POST + 1, 8'h00);    // POST = 0 (unlimited)
        ctrl_write(8'h00, 8'h0a); @(negedge clk100); trace_sig[8] = 1'b1; #2000; rec_count = 0;
        ctrl_write(8'h00, 8'h06);                              // DESC_REQ for the 'triggered' flag
        for (int i = 0; i < 6; i++) begin @(negedge clk100); trace_sig[3:0] = ~trace_sig[3:0]; #500; end
        #2000;
        check($sformatf("post=0: unlimited after trigger (got %0d)", rec_count), rec_count == 6);
        check("flags: triggered", desc_flags[2] == 1'b1);

        // 6. link diagnostics: counters since the previous 'L' (the first 'L' clears the
        // reset artefacts: the tb decoder flags the encoder's reset-state symbol once per reset)
        resp.delete(); hsend("L"); wait (resp.size() == 14);
        resp.delete();
        for (int i = 0; i < 6; i++) begin @(negedge clk100); trace_sig[3:0] = ~trace_sig[3:0]; #500; end
        #2000;
        hsend("L"); wait (resp.size() == 14);
        check($sformatf("'L' status 0x%02x ver %0d commas %0d recs %0d errs %0d", resp[0], resp[1],
              {resp[3], resp[2]}, {resp[5], resp[4]}, {resp[7], resp[6]}),
              resp[0] == 8'h0f && resp[1] == 8'h02 && {resp[3], resp[2]} > 16'd10 && {resp[5], resp[4]} >= 16'd6 && {resp[7], resp[6]} == 16'd0);
        resp.delete(); hsend("L"); wait (resp.size() == 14);
        check($sformatf("'L' counters cleared (recs %0d)", {resp[5], resp[4]}), {resp[5], resp[4]} < 16'd6);

        // 5. desc_req: descriptor immediately (flags reflect enable)
        ctrl_write(8'h00, 8'h06);            // DESC_REQ | ENABLE
        #10000;
        check("desc still enabled flag", desc_flags[0] == 1'b1);

        if (errors == 0) $display("PASS (SCLK_PERIOD=%0.3f TX_WIDTH=%0d)", SCLK_PERIOD, TX_WIDTH); else $fatal(1, "FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #80_000_000;
        $fatal(1, "TIMEOUT");
    end
endmodule
