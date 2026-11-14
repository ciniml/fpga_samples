// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Directed test of the cartridge reader: status, power sequencing, reads with MBC5 banking,
// write whitelist (refused writes must never reach the bus), RAM mode (enable only in the mode,
// RAM reads with /CS, disabled again by the reader on 'A' 0 / watchdog / host loss / removal),
// removal while powered.
`timescale 1ns/1ps
module tb_cart_unit;
    logic clk = 0, rst = 1, cart_det = 0, switch_on = 1, host_ok = 1;
    always #8.333 clk = ~clk;
    logic rx_valid = 0, rx_ready, tx_valid, tx_ready = 1;
    logic [7:0] rx_data = 0, tx_data;
    int n_writes, n_violations, n_ram_reads, errors = 0;
    logic ram_enabled;

    cart_sim_top #(.MBC(5), .ROM_CODE(5), .RAM_CODE(3)) dut (.*);

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
    function automatic byte ramb(int i); return dut.u_cart.ram[i]; endfunction
    task automatic ram_mode(bit on, output byte f);
        byte r[$];
        send("A"); send(on); recv(2, r);
        f = (r.size() == 2 && r[0] == "A") ? r[1] : 8'h00;
    endtask
    task automatic expect_ram_off(string why);
        byte s[$];
        repeat (2000) @(posedge clk);
        status(s);
        if (s[3][7] || s[7][0] || ram_enabled) begin
            $display("FAIL: %s: RAM mode %b / reader RAM on %b / cartridge RAM enabled %b", why, s[3][7], s[7][0], ram_enabled);
            errors++;
        end
    endtask

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
        ram_mode(1, res);
        if (res[7]) begin $display("FAIL: RAM mode granted without power"); errors++; end

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
        write(16'h4000, 8'h10, res); if (res != 1) begin $display("FAIL: 4000 <- 10 not refused"); errors++; end
        write(16'h0000, 8'h00, res); if (res != 0) begin $display("FAIL: RAM disable refused"); errors++; end
        if (n_writes != w0 + 1) begin $display("FAIL: refused writes reached the bus (%0d)", n_writes - w0); errors++; end
        status(s);
        if (s[5] != 5) begin $display("FAIL: reject count %0d", s[5]); errors++; end
        // without RAM mode a read of 0xA000 does not select the RAM
        read(16'hA000, 16, r);
        foreach (r[i]) if (r[i] != 8'hFF) begin $display("FAIL: RAM read without RAM mode gave %h", r[i]); errors++; break; end
        if (n_ram_reads) begin $display("FAIL: %0d RAM reads without RAM mode", n_ram_reads); errors++; end

        // RAM mode: enable, bank 2, read; writes to RAM still refused
        ram_mode(1, res);
        if (!res[7]) begin $display("FAIL: RAM mode refused (flags %h)", res); errors++; end
        write(16'h0000, 8'h0A, res); if (res != 0) begin $display("FAIL: RAM enable in RAM mode: %0d", res); errors++; end
        status(s);
        if (!s[7][0] || !ram_enabled) begin $display("FAIL: RAM not enabled (%h, %b)", s[7], ram_enabled); errors++; end
        write(16'h4000, 8'h02, res); if (res != 0) begin $display("FAIL: RAM bank: %0d", res); errors++; end
        read(16'hA000, 256, r);
        foreach (r[i]) if (r[i] != ramb(2 * 8192 + i)) begin $display("FAIL: RAM bank 2 byte %0d: %h != %h", i, r[i], ramb(2 * 8192 + i)); errors++; break; end
        read(16'hBF00, 256, r);
        foreach (r[i]) if (r[i] != ramb(2 * 8192 + 16'h1F00 + i)) begin $display("FAIL: RAM bank 2 end byte %0d", i); errors++; break; end
        if (n_ram_reads != 512) begin $display("FAIL: %0d RAM reads for 512", n_ram_reads); errors++; end
        w0 = n_writes;
        write(16'hA000, 8'h12, res); if (res != 1) begin $display("FAIL: RAM write not refused in RAM mode"); errors++; end
        write(16'h0000, 8'h0B, res); if (res != 1) begin $display("FAIL: 0000 <- 0B not refused"); errors++; end
        if (n_writes != w0) begin $display("FAIL: refused writes reached the bus in RAM mode"); errors++; end
        // 'A' 0: the reader disables the RAM itself (one bus write of its own)
        w0 = n_writes;
        ram_mode(0, res);
        expect_ram_off("after 'A' 0");
        if (n_writes != w0 + 1) begin $display("FAIL: %0d bus writes for the automatic disable", n_writes - w0); errors++; end
        write(16'h0000, 8'h0A, res); if (res != 1) begin $display("FAIL: RAM enable accepted after RAM mode"); errors++; end
        // watchdog: 1 s (SIM_HZ clocks) without a command
        ram_mode(1, res); write(16'h0000, 8'h0A, res);
        repeat (62000) @(posedge clk);
        expect_ram_off("watchdog");
        // the host goes away (USB unconfigured)
        ram_mode(1, res); write(16'h0000, 8'h0A, res);
        host_ok = 0;
        expect_ram_off("host lost");
        host_ok = 1;
        ram_mode(1, res);
        if (!res[7]) begin $display("FAIL: RAM mode refused after the host came back"); errors++; end
        ram_mode(0, res);

        // 64 KiB read (len 0) is streamed in full
        read(16'h0000, 0, r);
        if (r.size() != 65536) begin $display("FAIL: len-0 read gave %0d bytes", r.size()); errors++; end

        // removal while powered and the RAM enabled: the reader disables the RAM before the power
        // goes down (the model flags a power-down with the RAM enabled)
        ram_mode(1, res); write(16'h0000, 8'h0A, res);
        if (!ram_enabled) begin $display("FAIL: RAM not enabled before removal"); errors++; end
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
        else $display("TEST PASSED (%0d bus writes, %0d RAM reads)", n_writes, n_ram_reads);
        $finish;
    end
    initial begin #2s; $display("FAIL: global timeout"); $finish; end
endmodule
