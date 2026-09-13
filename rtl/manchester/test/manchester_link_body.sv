// Manchester TX -> RX loopback test body.
//   TX_PERIOD / RX_PERIOD : clock periods [ns] (RX may differ to model
//                           crystal offset; BIT_CYCLES is the same on both)
//   INVERT                : 1 = wire polarity inverted (must not decode)
`timescale 1ns/1ps
module manchester_link_body #(
    parameter real TX_PERIOD = 10.0,
    parameter real RX_PERIOD = 10.0,
    parameter int  BIT_CYCLES = 20,
    parameter bit  INVERT = 0,
    parameter int  NBYTES = 300,
    parameter bit  RUN = 0
) ();
    logic tclk = 0, rclk = 0, rst = 1;
    always #(TX_PERIOD/2) tclk = ~tclk;
    always #(RX_PERIOD/2) rclk = ~rclk;

    logic       tx_valid = 0, tx_ready;
    logic [7:0] tx_data = 0;
    logic       txd, wire_d;
    logic       rx_valid, rx_err, rx_link;
    logic [7:0] rx_data;
    logic       force_line = 0, force_lvl = 0;   // link-loss test
    assign wire_d = force_line ? force_lvl : (txd ^ INVERT);

    ManchesterTx #(.BIT_CYCLES(BIT_CYCLES)) tx (
        .i_clk(tclk), .i_rst(rst), .i_valid(tx_valid), .i_data(tx_data), .o_ready(tx_ready), .o_txd(txd));
    ManchesterRx #(.BIT_CYCLES(BIT_CYCLES)) rx (
        .i_clk(rclk), .i_rst(rst), .i_rxd(wire_d),
        .o_valid(rx_valid), .o_data(rx_data), .o_err(rx_err), .o_link(rx_link));

    // ---- wire monitor: run length (DC balance) ----
    real     half_ns = TX_PERIOD * BIT_CYCLES / 2.0;
    real     last_edge = 0, max_run = 0;
    logic    prev_wire = 0;
    always @(wire_d) begin
        if ($realtime - last_edge > max_run) max_run = $realtime - last_edge;
        last_edge = $realtime;
    end

    // ---- scoreboard ----
    logic [7:0] sent[$];
    int got = 0, errors = 0, err_pulses = 0;
    always @(posedge rclk) begin
        if (rx_valid) begin
            if (sent.size() == 0) begin
                $display("ERROR: unexpected byte %02x", rx_data); errors++;
            end else if (rx_data !== sent[0]) begin
                $display("ERROR: byte %0d: got %02x expected %02x", got, rx_data, sent[0]); errors++;
                void'(sent.pop_front());
            end else void'(sent.pop_front());
            got++;
        end
        if (rx_err) err_pulses++;
    end

    task automatic send(input logic [7:0] b);
        @(negedge tclk);
        tx_valid = 1; tx_data = b;
        do @(posedge tclk); while (!tx_ready);
        sent.push_back(b);
        @(negedge tclk);
        tx_valid = 0;
    endtask

    task automatic wait_bits(input int n);
        repeat (n * BIT_CYCLES) @(posedge tclk);
    endtask

    initial if (RUN) begin
        repeat (5) @(posedge tclk); rst = 0;
        wait_bits(20);
        if (!rx_link) begin $display("ERROR: link not detected on idle"); errors++; end

        // 1. random bytes, random gaps (0..3 idle bits), and back-to-back
        for (int i = 0; i < NBYTES; i++) begin
            send($urandom);
            if ($urandom % 3 == 0) wait_bits($urandom % 4);
        end
        send(8'h00); send(8'hff); send(8'h55); send(8'haa); send(8'h01); send(8'h80);
        wait_bits(40);
        if (INVERT) begin
            if (got != 0) begin $display("ERROR: inverted polarity decoded %0d bytes", got); errors++; end
            $display("inverted: %0d error pulses (expected: many, no data)", err_pulses);
        end else begin
            if (sent.size() != 0) begin $display("ERROR: %0d bytes not received", sent.size()); errors++; end
            if (err_pulses != 0) begin $display("ERROR: %0d error pulses", err_pulses); errors++; end
        end
        // max run: SYNC high (3 half-bits) may merge with a preceding '1' second half -> 4
        if (max_run > 4.2 * half_ns) begin $display("ERROR: max run %.1f ns > 4 half-bits", max_run); errors++; end
        $display("received %0d bytes, max run %.2f half-bits", got, max_run / half_ns);

        if (!INVERT) begin
            // 2. link loss: freeze the wire, o_link must drop, then recover
            force_line = 1;
            wait_bits(8);
            if (rx_link) begin $display("ERROR: link still up with a frozen wire"); errors++; end
            force_line = 0;
            wait_bits(8);
            if (!rx_link) begin $display("ERROR: link did not recover"); errors++; end
            // data after recovery
            got = 0;
            send(8'h3c); send(8'hc3);
            wait_bits(30);
            if (sent.size() != 0) begin $display("ERROR: bytes lost after link recovery"); errors++; end

            // 3. corrupted byte: bit-bang a byte with wrong parity on the wire
            err_pulses = 0; got = 0;
            bitbang(8'h5a, 1'b1 /*bad parity*/);
            wait_bits(30);
            if (err_pulses != 1 || got != 0) begin
                $display("ERROR: bad parity: err=%0d valid=%0d", err_pulses, got); errors++;
            end
            // 4. false SYNC (high run but no low run) must be flagged, not decoded
            err_pulses = 0; got = 0;
            bitbang_false_sync();
            wait_bits(30);
            if (got != 0) begin $display("ERROR: false sync decoded a byte"); errors++; end
            // healthy byte afterwards
            got = 0; send(8'h96); wait_bits(30);
            if (sent.size() != 0) begin $display("ERROR: byte lost after false sync"); errors++; end
        end

        if (errors == 0) $display("PASS"); else $fatal(1, "FAIL: %0d errors", errors);
        $finish;
    end

    // drive the wire directly (TX output overridden) for error injection
    task automatic half(input logic v);
        force_lvl = v; repeat (BIT_CYCLES/2) @(posedge tclk);
    endtask
    task automatic bitbang(input logic [7:0] b, input logic flip_parity);
        logic p = (^b) ^ flip_parity;
        force_line = 1;
        // keep the line idling '1' first so the receiver sees a normal preamble
        repeat (3) begin half(0); half(1); end
        half(1); half(1); half(1); half(0); half(0); half(0);
        for (int i = 0; i < 8; i++) begin half(~b[i]); half(b[i]); end
        half(~p); half(p);
        repeat (3) begin half(0); half(1); end
        force_line = 0;
    endtask
    task automatic bitbang_false_sync();
        force_line = 1;
        repeat (3) begin half(0); half(1); end
        half(1); half(1); half(1); half(0); half(1); half(0);   // low part too short
        repeat (10) begin half(0); half(1); end
        force_line = 0;
    endtask
endmodule
