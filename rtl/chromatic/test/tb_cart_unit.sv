// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Directed test of the cartridge reader: status, power sequencing, reads with MBC5 banking,
// write whitelist (refused writes must never reach the bus), removal while powered.
`timescale 1ns/1ps
module tb_cart_unit;
    logic clk = 0, rst = 1, cart_det = 0, switch_on = 1;
    always #8.333 clk = ~clk;
    logic rx_valid = 0, rx_ready, tx_valid, tx_ready = 1;
    logic [7:0] rx_data = 0, tx_data;
    int n_writes, n_violations, errors = 0;

    cart_sim_top #(.MBC(5), .ROM_CODE(5)) dut (.*);

    byte rxq[$];
    always @(posedge clk) if (tx_valid && tx_ready) rxq.push_back(tx_data);

    task automatic send(byte b);
        @(negedge clk); rx_valid = 1; rx_data = b;
        do @(posedge clk); while (!rx_ready);
        @(negedge clk); rx_valid = 0;
    endtask
    task automatic recv(int n, output byte r[$], input int timeout = 2000000);
        int t = 0;
        while (rxq.size() < n && t < timeout) begin @(posedge clk); t++; end
        if (rxq.size() < n) begin $display("FAIL: timeout waiting for %0d bytes (got %0d)", n, rxq.size()); errors++; end
        r = {};
        repeat (n) if (rxq.size()) r.push_back(rxq.pop_front());
    endtask
    task automatic status(output byte s[$]);
        send("S"); recv(8, s);
        if (s.size() == 8 && (s[0] != "C" || s[1] != "R")) begin $display("FAIL: bad status magic"); errors++; end
    endtask
    task automatic read(int addr, int len, output byte r[$]);
        send("R"); send(addr[7:0]); send(addr[15:8]); send(len[7:0]); send(len[15:8]);
        recv(len == 0 ? 65536 : len, r, 4000000);
    endtask
    task automatic write(int addr, byte data, output byte res);
        byte r[$];
        send("W"); send(addr[7:0]); send(addr[15:8]); send(data);
        recv(2, r);
        res = (r.size() == 2 && r[0] == "W") ? r[1] : 8'hEE;
    endtask
    function automatic byte romb(int i); return dut.u_cart.rom[i]; endfunction

    initial begin
        byte s[$], r[$], res;
        int w0;
        repeat (10) @(posedge clk); rst = 0;
        repeat (100) @(posedge clk);

        // no cartridge: power request refused
        status(s);
        if (s[3][0] !== 1'b0) begin $display("FAIL: cart detected without a cartridge"); errors++; end
        send("P"); send(1); recv(2, r);
        if (r[1][2]) begin $display("FAIL: power granted without a cartridge"); errors++; end
        write(16'h2000, 8'h01, res);
        if (res != 2) begin $display("FAIL: write while unpowered returned %0d", res); errors++; end

        // insert, power up
        cart_det = 1;
        repeat (2000) @(posedge clk);
        send("P"); send(1); recv(2, r);
        if (!r[1][2]) begin $display("FAIL: power not granted"); errors++; end
        for (int i = 0; i < 200; i++) begin
            status(s);
            if (s[3][4]) break;
            repeat (500) @(posedge clk);
        end
        if (!s[3][4]) begin $display("FAIL: bus never ready (flags %h)", s[3]); errors++; end
        else $display("bus ready, flags %h", s[3]);

        // header and bank 0
        read(16'h0100, 80, r);
        foreach (r[i]) if (r[i] != romb(16'h100 + i)) begin
            $display("FAIL: bank0 %h: %h != %h", 16'h100 + i, r[i], romb(16'h100 + i)); errors++; break;
        end
        // MBC5 bank 0x1A3 (with bit 8)
        w0 = n_writes;
        write(16'h2000, 8'hA3, res); if (res != 0) begin $display("FAIL: 2000 write %0d", res); errors++; end
        write(16'h3000, 8'h01, res); if (res != 0) begin $display("FAIL: 3000 write %0d", res); errors++; end
        read(16'h4000, 256, r);
        foreach (r[i]) if (r[i] != romb((9'h1A3 % 64) * 16384 + i)) begin
            $display("FAIL: bank %h byte %0d", 9'h1A3 % 64, i); errors++; break;
        end
        read(16'h7F00, 256, r);
        foreach (r[i]) if (r[i] != romb((9'h1A3 % 64) * 16384 + 16'h3F00 + i)) begin
            $display("FAIL: bank end byte %0d", i); errors++; break;
        end
        if (n_writes != w0 + 2) begin $display("FAIL: %0d bus writes for 2 requests", n_writes - w0); errors++; end

        // refused writes: flash command addresses, cartridge RAM, RAM enable
        w0 = n_writes;
        write(16'h0555, 8'hAA, res); if (res != 1) begin $display("FAIL: 0555 not refused"); errors++; end
        write(16'h2AAA, 8'h55, res); if (res != 1) begin $display("FAIL: 2AAA not refused"); errors++; end
        write(16'hA000, 8'h12, res); if (res != 1) begin $display("FAIL: A000 not refused"); errors++; end
        write(16'h0000, 8'h0A, res); if (res != 1) begin $display("FAIL: RAM enable not refused"); errors++; end
        write(16'h0000, 8'h00, res); if (res != 0) begin $display("FAIL: RAM disable refused"); errors++; end
        if (n_writes != w0 + 1) begin $display("FAIL: refused writes reached the bus (%0d)", n_writes - w0); errors++; end
        status(s);
        if (s[5] != 4) begin $display("FAIL: reject count %0d", s[5]); errors++; end

        // 64 KiB read (len 0) is streamed in full
        read(16'h0000, 0, r);
        if (r.size() != 65536) begin $display("FAIL: len-0 read gave %0d bytes", r.size()); errors++; end

        // removal while powered: power drops, bus goes Low, reads return FF with err
        cart_det = 0;
        repeat (20000) @(posedge clk);
        status(s);
        if (s[3][3] || s[3][2]) begin $display("FAIL: still powered after removal (flags %h)", s[3]); errors++; end
        read(16'h0000, 4, r);
        status(s);
        if (!s[6][0]) begin $display("FAIL: read-while-off error flag not set"); errors++; end

        repeat (100) @(posedge clk);
        if (n_violations) errors += n_violations;
        if (errors) $display("TEST FAILED (%0d errors, %0d violations)", errors, n_violations);
        else $display("TEST PASSED (%0d bus writes)", n_writes);
        $finish;
    end
    initial begin #2s; $display("FAIL: global timeout"); $finish; end
endmodule
