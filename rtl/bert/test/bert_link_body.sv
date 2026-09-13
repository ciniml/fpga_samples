// BERT loopback: BertCore TX (8 bits/clk) -> serial wire (with optional
// bit offset, inversion, bit reversal at the deserializer) -> 16-bit words
// with 50% valid -> BertCore RX. Driven through BertHost commands.
`timescale 1ns/1ps
module bert_link_body #(
    parameter int  BIT_OFFSET = 3,    // wire bits of phase between TX and RX word framing
    parameter bit  WIRE_INVERT = 0,
    parameter bit  WORD_BITREV = 0,   // deserializer packs MSB-first (EasyCDR 1.9.12 style)
    parameter bit  RUN = 0
) ();
    logic lclk = 0, hclk = 0, rst = 1;
    always #4  lclk = ~lclk;   // 125MHz link clock
    always #10 hclk = ~hclk;   // 50MHz host clock

    // ---- DUT ----
    logic [7:0]  tx_data;
    logic        rx_valid;
    logic [15:0] rx_data;
    logic        locked;
    logic        reg_req, reg_wr;
    logic [7:0]  reg_addr, reg_wdat, reg_rdat;
    logic        h_rx_valid = 0, h_tx_valid;
    logic [7:0]  h_rx_data = 0, h_tx_data;

    BertCore #(.TX_WIDTH(8), .RX_WIDTH(16)) core (
        .i_clk(lclk), .i_rst(rst), .o_tx_data(tx_data),
        .i_rx_valid(rx_valid), .i_rx_data(rx_data), .i_link_ok(1'b1),
        .o_ext_ctrl(), .i_ext_status(8'h5a), .o_dbg_addr(), .i_dbg_data(8'h00),
        .i_reg_req(reg_req), .i_reg_wr(reg_wr), .i_reg_addr(reg_addr), .i_reg_wdat(reg_wdat), .o_reg_rdat(reg_rdat),
        .o_locked(locked));
    BertHost host (
        .i_clk(hclk), .i_rst(rst),
        .i_rx_valid(h_rx_valid), .i_rx_data(h_rx_data), .o_tx_valid(h_tx_valid), .o_tx_data(h_tx_data), .i_tx_ready(1'b1),
        .i_lclk(lclk), .i_lrst(rst),
        .o_reg_req(reg_req), .o_reg_wr(reg_wr), .o_reg_addr(reg_addr), .o_reg_wdat(reg_wdat), .i_reg_rdat(reg_rdat));

    // ---- wire model: serialize 8 bits/clk, gather 16 bits with a phase offset
    logic        wire_bits[$];
    logic        rx_fault = 0;       // force wire to 0 (link loss)
    int          flip_next = 0;      // number of upcoming wire bits to flip
    logic [15:0] shreg;
    int          nbits = 0;
    always @(posedge lclk) begin
        rx_valid <= 0;
        for (int i = 0; i < 8; i++) begin
            logic b = tx_data[i] ^ WIRE_INVERT;
            if (rx_fault) b = 0;
            if (flip_next > 0) begin b = ~b; flip_next--; end
            wire_bits.push_back(b);
        end
        // deserializer: consumes 16 bits every other clock (50% valid)
        if (wire_bits.size() >= 16 + BIT_OFFSET && nbits == 0) begin
            for (int i = 0; i < BIT_OFFSET; i++) void'(wire_bits.pop_front());
            nbits = 1;
        end
        if (nbits == 1 && wire_bits.size() >= 16 && !rx_valid_gate) begin
            for (int i = 0; i < 16; i++) begin
                logic b = wire_bits.pop_front();
                if (WORD_BITREV) shreg[15 - i] = b; else shreg[i] = b;
            end
            rx_data  <= shreg;
            rx_valid <= 1;
        end
    end
    logic rx_valid_gate = 0;
    always @(posedge lclk) rx_valid_gate <= rx_valid;   // one word every 2 clocks

    // ---- host helpers ----
    logic [7:0] resp[$];
    always @(posedge hclk) if (h_tx_valid) resp.push_back(h_tx_data);
    task automatic hsend(input logic [7:0] b);
        @(negedge hclk); h_rx_valid = 1; h_rx_data = b;
        @(negedge hclk); h_rx_valid = 0;
    endtask
    task automatic wreg(input logic [7:0] a, input logic [7:0] d);
        resp.delete(); hsend("W"); hsend(a); hsend(d);
        wait (resp.size() == 1);
        if (resp[0] != "k") begin $display("ERROR: write ack %02x", resp[0]); errors++; end
    endtask
    function automatic logic [7:0] rreg_last(); return resp[0]; endfunction
    task automatic rreg(input logic [7:0] a, output logic [7:0] d);
        resp.delete(); hsend("R"); hsend(a);
        wait (resp.size() == 1); d = resp[0];
    endtask
    task automatic snapshot(output longint bits, output longint errs, output int unlocks);
        logic [7:0] ctrl;
        rreg(8'h00, ctrl);
        wreg(8'h00, ctrl | 8'h08);            // SNAP
        resp.delete(); hsend("B"); hsend(8'h10); hsend(8'd20);
        wait (resp.size() == 20);
        bits = 0; errs = 0; unlocks = 0;
        for (int i = 7; i >= 0; i--) bits = (bits << 8) | resp[i];
        for (int i = 7; i >= 0; i--) errs = (errs << 8) | resp[8 + i];
        for (int i = 3; i >= 0; i--) unlocks = (unlocks << 8) | resp[16 + i];
    endtask
    task automatic clear_counters();
        logic [7:0] ctrl; rreg(8'h00, ctrl); wreg(8'h00, ctrl | 8'h04);
    endtask
    task automatic check(input string what, input bit cond);
        if (!cond) begin $display("ERROR: %s", what); errors++; end else $display("ok: %s", what);
    endtask
    int errors = 0;
    longint bits, errs; int unlocks;
    logic [7:0] st, ctrl_base;

    initial if (RUN) begin
        repeat (5) @(posedge hclk); rst = 0;
        #200;
        // identify
        resp.delete(); hsend("I"); wait (resp.size() == 5);
        check("ident", resp[0] == "B" && resp[1] == "E" && resp[2] == "R" && resp[3] == "T" && resp[4] == 8'h01);

        // configure RX conditioning to match the wire model
        ctrl_base = 8'h03 | (WIRE_INVERT ? 8'h20 : 8'h00) | (WORD_BITREV ? 8'h40 : 8'h00);
        wreg(8'h00, ctrl_base);

        // 1. lock on PRBS7 (default), zero errors
        #5000;
        rreg(8'h08, st);
        check("locked (PRBS7)", st[0] == 1 && st[1] == 1);
        clear_counters(); #20000;
        snapshot(bits, errs, unlocks);
        check($sformatf("PRBS7 clean: bits=%0d errs=%0d", bits, errs), bits > 1000 && errs == 0 && unlocks == 0);

        // 2. inject single errors via CTRL.INJECT: counted exactly once each
        clear_counters();
        for (int i = 0; i < 5; i++) begin wreg(8'h00, ctrl_base | 8'h10); #400; end
        #3000;
        snapshot(bits, errs, unlocks);
        check($sformatf("5 injected errors counted exactly: errs=%0d", errs), errs == 5 && unlocks == 0);

        // 3. wire-level random error burst of 3 bits: counted as 3
        clear_counters(); #200;
        flip_next = 3; #3000;
        snapshot(bits, errs, unlocks);
        check($sformatf("3 wire bit errors: errs=%0d", errs), errs == 3);

        // 4. switch TX+RX to each PRBS and confirm lock, zero errors
        for (int sel = 1; sel <= 4; sel++) begin
            wreg(8'h02, sel); wreg(8'h03, sel); #6000;
            clear_counters(); #10000;
            snapshot(bits, errs, unlocks);
            rreg(8'h08, st);
            check($sformatf("PRBS sel %0d: lock=%0d errs=%0d", sel, st[0], errs), st[0] == 1 && errs == 0);
        end
        wreg(8'h02, 0); wreg(8'h03, 0); #6000;

        // 5. pattern mismatch (TX PRBS9, RX PRBS7): no lock, no bits counted
        wreg(8'h02, 1); #6000; clear_counters(); #6000;
        rreg(8'h08, st); snapshot(bits, errs, unlocks);
        check("mismatched PRBS: no lock", st[0] == 0);
        wreg(8'h02, 0); #6000;

        // 6. link loss: wire forced to 0 -> lock drops, unlock counted, no false lock on zeros
        rreg(8'h08, st); check("relocked before fault", st[0] == 1);
        clear_counters();
        rx_fault = 1; #6000;
        rreg(8'h08, st); snapshot(bits, errs, unlocks);
        check($sformatf("link loss: lock=%0d unlocks=%0d", st[0], unlocks), st[0] == 0 && unlocks == 1);
        #20000; rreg(8'h08, st);
        check("all-zero wire never locks", st[0] == 0);
        rx_fault = 0; #6000;
        rreg(8'h08, st); check("relock after fault", st[0] == 1);

        // 7. TX zero mode -> RX sees constant, no lock; fixed/clock modes run without lock
        wreg(8'h01, 3); #6000; rreg(8'h08, st); check("TX zero: no lock", st[0] == 0);
        wreg(8'h01, 2); #6000; rreg(8'h08, st); check("TX clock: no PRBS lock", st[0] == 0);
        wreg(8'h01, 0); #6000; rreg(8'h08, st); check("back to PRBS: lock", st[0] == 1);

        // 8. TX invert + RX invert together still lock
        wreg(8'h00, ctrl_base ^ 8'h80 ^ 8'h20); #6000; clear_counters(); #6000;
        rreg(8'h08, st); snapshot(bits, errs, unlocks);
        check("tx_invert & rx_invert", st[0] == 1 && errs == 0);

        if (errors == 0) $display("PASS"); else $fatal(1, "FAIL: %0d errors", errors);
        $finish;
    end
    initial if (RUN) begin #5_000_000; $fatal(1, "TIMEOUT"); end
endmodule
