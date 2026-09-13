// Control channel end-to-end: bytes -> ManchesterTx -> wire -> ManchesterRx
// -> CtrlFrameRx -> TraceCtrlRegs. Frames are built host-side (as the
// browser will do), including the CRC-8.
`timescale 1ns/1ps
module ctrl_frame_body #(
    parameter int BIT_CYCLES = 16,
    parameter int WIDTH = 16,
    parameter bit RUN = 0
) ();
    logic clk = 0, rst = 1;
    always #5 clk = ~clk;

    logic       tx_valid = 0, tx_ready;
    logic [7:0] tx_data = 0;
    logic       txd, drop = 0;
    logic       rx_valid, rx_err, rx_link;
    logic [7:0] rx_data;
    logic       wr_valid, frame_ok, frame_err;
    logic [7:0] wr_addr, wr_data;
    logic       soft_reset, enable, desc_req;
    logic [WIDTH-1:0] ignore_mask;

    ManchesterTx #(.BIT_CYCLES(BIT_CYCLES)) tx (
        .i_clk(clk), .i_rst(rst), .i_valid(tx_valid), .i_data(tx_data), .o_ready(tx_ready), .o_txd(txd));
    // `drop` freezes the wire to lose bytes in flight
    ManchesterRx #(.BIT_CYCLES(BIT_CYCLES)) rx (
        .i_clk(clk), .i_rst(rst), .i_rxd(drop ? 1'b0 : txd),
        .o_valid(rx_valid), .o_data(rx_data), .o_err(rx_err), .o_link(rx_link));
    CtrlFrameRx #(.GAP_TIMEOUT(BIT_CYCLES * 40)) frx (
        .i_clk(clk), .i_rst(rst), .i_valid(rx_valid), .i_data(rx_data), .i_err(rx_err),
        .o_wr_valid(wr_valid), .o_wr_addr(wr_addr), .o_wr_data(wr_data), .o_frame_err(frame_err));
    assign frame_ok = wr_valid;
    TraceCtrlRegs #(.WIDTH(WIDTH), .RESET_CYCLES(16)) regs (
        .i_clk(clk), .i_rst(rst), .i_wr_valid(wr_valid), .i_wr_addr(wr_addr), .i_wr_data(wr_data),
        .o_soft_reset(soft_reset), .o_enable(enable), .o_desc_req(desc_req), .o_ignore_mask(ignore_mask),
        .o_arm(arm), .o_periodic_en(periodic_en), .o_change_dis(change_dis), .o_period(period),
        .o_trig_mask(trig_mask), .o_trig_value(trig_value), .o_post(post));
    logic arm, periodic_en, change_dis; logic [23:0] period; logic [WIDTH-1:0] trig_mask, trig_value; logic [15:0] post;
    int arms = 0; always @(posedge clk) if (arm) arms++;

    int errors = 0, oks = 0, errs = 0, writes = 0, resets = 0, descs = 0;
    logic sr_q = 0;
    always @(posedge clk) begin
        if (frame_ok) oks++;
        if (frame_err) errs++;
        if (wr_valid) writes++;
        if (desc_req) descs++;
        sr_q <= soft_reset; if (soft_reset && !sr_q) resets++;
    end

    function automatic logic [7:0] crc8(input logic [7:0] a, input logic [7:0] d);
        logic [7:0] c = 0;
        c ^= a; for (int b = 0; b < 8; b++) c = c[7] ? {c[6:0], 1'b0} ^ 8'h07 : {c[6:0], 1'b0};
        c ^= d; for (int b = 0; b < 8; b++) c = c[7] ? {c[6:0], 1'b0} ^ 8'h07 : {c[6:0], 1'b0};
        return c;
    endfunction

    task automatic send(input logic [7:0] b);
        @(negedge clk); tx_valid = 1; tx_data = b;
        do @(posedge clk); while (!tx_ready);
        @(negedge clk); tx_valid = 0;
    endtask

    // frame(addr, data[0..n-1]): n consecutive single-byte write frames
    task automatic frame(input logic [7:0] addr, input logic [7:0] data[6], input int n, input bit bad_crc = 0);
        for (int i = 0; i < n; i++) begin
            send(8'ha5); send(addr + i); send(data[i]);
            send(crc8(addr + i, data[i]) ^ (bad_crc ? 8'h01 : 8'h00));
        end
    endtask

    task automatic wait_bits(input int n);
        repeat (n * BIT_CYCLES) @(posedge clk);
    endtask

    task automatic check(input string what, input bit cond);
        if (!cond) begin $display("ERROR: %s", what); errors++; end
    endtask

    logic [7:0] d[6];
    initial if (RUN) begin
        repeat (5) @(posedge clk); rst = 0;
        wait_bits(20);
        check("enable default 1", enable == 1);

        // 1. ignore mask write (2 bytes at 0x04)
        d[0] = 8'h34; d[1] = 8'h12;
        frame(8'h04, d, 2); wait_bits(20);
        check("mask written", ignore_mask == 16'h1234);
        check("2 frames ok", oks == 2 && errs == 0 && writes == 2);

        // 2. CTRL: reset + disable; then desc request with enable
        d[0] = 8'h01; frame(8'h00, d, 1); wait_bits(20);
        check("soft reset pulsed", resets == 1);
        check("reset self-clears", soft_reset == 0);
        check("enable cleared", enable == 0);
        d[0] = 8'h06; frame(8'h00, d, 1); wait_bits(20);
        check("desc_req pulsed once", descs == 1);
        check("enable set", enable == 1);
        check("mask untouched", ignore_mask == 16'h1234);

        // 3. bad CRC: nothing written
        d[0] = 8'hff; d[1] = 8'hff;
        frame(8'h04, d, 2, 1); wait_bits(20);
        check("bad crc rejected", ignore_mask == 16'h1234 && errs == 2 && oks == 4);

        // 4. SOF byte inside the payload, 4-byte frame, a5 as data
        d[0] = 8'ha5; d[1] = 8'ha5; d[2] = 8'h00; d[3] = 8'h00;
        frame(8'h04, d, 4); wait_bits(30);
        check("a5 payload ok", ignore_mask == 16'ha5a5 && oks == 8 && errs == 2);

        // 5. truncated frame (SOF, ADDR only) then a good one: gap timeout resyncs
        send(8'ha5); send(8'h04); wait_bits(70);
        check("truncated frame -> err", errs == 3);
        d[0] = 8'h01; d[1] = 8'h00; frame(8'h04, d, 2); wait_bits(20);
        check("after truncated frame", ignore_mask == 16'h0001 && oks == 10);

        // 6. byte lost mid-frame (wire frozen during byte 3), gap timeout recovers
        fork
            begin d[0] = 8'h55; d[1] = 8'haa; frame(8'h04, d, 2); end
            begin wait_bits(12 * 2 + 2); drop = 1; wait_bits(12); drop = 0; end
        join
        wait_bits(60);
        check("lost byte -> first write dropped", ignore_mask == 16'haa01);
        d[0] = 8'h77; d[1] = 8'h66; frame(8'h04, d, 2); wait_bits(20);
        check("recovered after loss", ignore_mask == 16'h6677);

        // 6b. new registers: MODE, PERIOD, TRIG_MASK/VALUE, POST, ARM
        d[0] = 8'h03; frame(8'h08, d, 1);
        d[0] = 8'h40; d[1] = 8'h42; d[2] = 8'h0f; frame(8'h09, d, 3);
        d[0] = 8'h34; d[1] = 8'h12; frame(8'h0c, d, 2);
        d[0] = 8'h78; d[1] = 8'h56; frame(8'h0e, d, 2);
        d[0] = 8'h10; d[1] = 8'h27; frame(8'h10, d, 2);
        d[0] = 8'h0a; frame(8'h00, d, 1); wait_bits(20);
        check("MODE", periodic_en == 1 && change_dis == 1);
        check("PERIOD", period == 24'h0f4240);
        check("TRIG_MASK/VALUE", trig_mask == 16'h1234 && trig_value == 16'h5678);
        check("POST", post == 16'h2710);
        check("ARM pulsed once", arms == 1);

        // 7. back-to-back frames
        d[0] = 8'h11; frame(8'h04, d, 1);
        d[0] = 8'h22; frame(8'h05, d, 1);
        d[0] = 8'h02; frame(8'h00, d, 1);
        wait_bits(20);
        check("back-to-back", ignore_mask == 16'h2211 && enable == 1 && resets == 1);

        $display("frames ok=%0d err=%0d writes=%0d resets=%0d desc=%0d", oks, errs, writes, resets, descs);
        if (errors == 0) $display("PASS"); else $fatal(1, "FAIL: %0d errors", errors);
        $finish;
    end
endmodule
