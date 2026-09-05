// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Test body for EthIpStack: feeds Ethernet frames on the MAC-RX AXIS
// (no backpressure, like rmii_mac) and checks the replies on the TX
// AXIS with random backpressure. RUN=0 by default.
`timescale 1ns/1ps
module eth_ip_test_body #(
    parameter RUN = 0
);
    logic clk = 0;
    logic rst = 1;
    always #10 clk = ~clk; // 50MHz

    logic [7:0] rx_data = 0;
    logic       rx_valid = 0, rx_user = 0, rx_last = 0;
    logic [7:0] tx_data;
    logic       tx_valid, tx_ready = 0, tx_last;

    EthIpStack dut (
        .i_clk(clk), .i_rst(rst),
        .i_rx_data(rx_data), .i_rx_valid(rx_valid), .i_rx_user(rx_user), .i_rx_last(rx_last),
        .o_tx_data(tx_data), .o_tx_valid(tx_valid), .i_tx_ready(tx_ready), .o_tx_last(tx_last)
    );

    localparam byte unsigned OUR_MAC [0:5] = '{8'h02, 8'hA5, 8'h0F, 8'h01, 8'h02, 8'h03};
    localparam byte unsigned HOST_MAC [0:5] = '{8'hAA, 8'hBB, 8'hCC, 8'h00, 8'h11, 8'h22};

    // TX capture (with random backpressure)
    byte unsigned txq[$];
    int tx_frames = 0;
    always @(negedge clk) tx_ready = ($urandom_range(0, 3) != 0);
    always @(posedge clk) begin
        if (tx_valid && tx_ready) begin
            txq.push_back(tx_data);
            if (tx_last) tx_frames++;
        end
    end

    int errors = 0;
    task automatic check(input string what, input longint got, input longint exp);
        if (got !== exp) begin
            $display("ERROR: %s: got %0h expected %0h", what, got, exp);
            errors++;
        end
    endtask

    task automatic send_frame(input byte unsigned f[0:255], input int n, input bit bad);
        for (int i = 0; i < n; i++) begin
            @(negedge clk);
            rx_valid = 1;
            rx_data = f[i];
            rx_last = (i == n - 1);
            rx_user = bad && (i == n - 1);
            @(posedge clk);
        end
        @(negedge clk);
        rx_valid = 0; rx_last = 0; rx_user = 0;
    endtask

    task automatic wait_frame(input int n);
        int t = 0;
        while (txq.size() < n) begin
            @(negedge clk);
            t++;
            if (t > 100000) begin
                $display("ERROR: TX timeout want %0d have %0d", n, txq.size());
                errors++;
                return;
            end
        end
        // allow tlast bookkeeping to settle
        repeat (4) @(negedge clk);
    endtask

    function automatic logic [15:0] cksum(input byte unsigned f[0:255], input int off, input int n);
        logic [31:0] s = 0;
        for (int i = 0; i < n; i += 2)
            s += {f[off + i], (i + 1 < n) ? f[off + i + 1] : 8'h00};
        while (s[31:16] != 0) s = s[15:0] + s[31:16];
        return ~s[15:0];
    endfunction

    byte unsigned f[0:255];
    int flen;

    task automatic build_icmp(input byte unsigned last_ip, input byte unsigned icmp_type);
        int payload = 56;
        for (int i = 0; i < 256; i++) f[i] = 0;
        for (int i = 0; i < 6; i++) f[i] = OUR_MAC[i];
        for (int i = 0; i < 6; i++) f[6 + i] = HOST_MAC[i];
        f[12] = 8'h08; f[13] = 8'h00;              // IPv4
        f[14] = 8'h45;                             // ver/IHL
        {f[16], f[17]} = 16'(20 + 8 + payload);    // total length
        f[22] = 8'h40; f[23] = 8'h01;              // TTL, ICMP
        f[26] = 8'd192; f[27] = 8'd168; f[28] = 8'd37; f[29] = 8'd1;      // src
        f[30] = 8'd192; f[31] = 8'd168; f[32] = 8'd37; f[33] = last_ip;   // dst
        {f[24], f[25]} = cksum(f, 14, 20);         // IP checksum
        f[34] = icmp_type;                         // echo request
        {f[38], f[39]} = 16'h1234;                 // id
        for (int i = 0; i < payload; i++) f[42 + i] = 8'(i * 3 + 1);
        {f[36], f[37]} = cksum(f, 34, 8 + payload);
        flen = 14 + 20 + 8 + payload;
    endtask

    initial if (RUN) begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge clk);

        // ---- ARP request (broadcast) for 192.168.37.2 ----
        for (int i = 0; i < 256; i++) f[i] = 0;
        for (int i = 0; i < 6; i++) f[i] = 8'hFF;
        for (int i = 0; i < 6; i++) f[6 + i] = HOST_MAC[i];
        f[12] = 8'h08; f[13] = 8'h06;                       // ARP
        f[14] = 0; f[15] = 1; f[16] = 8'h08; f[17] = 0;     // HW/proto
        f[18] = 6; f[19] = 4; f[20] = 0; f[21] = 1;         // sizes, request
        for (int i = 0; i < 6; i++) f[22 + i] = HOST_MAC[i];
        f[28] = 8'd192; f[29] = 8'd168; f[30] = 8'd37; f[31] = 8'd1; // sender IP
        f[38] = 8'd192; f[39] = 8'd168; f[40] = 8'd37; f[41] = 8'd2; // target IP
        send_frame(f, 60, 0);
        wait_frame(42);
        for (int i = 0; i < 6; i++) check("arp dst", txq[i], HOST_MAC[i]);
        for (int i = 0; i < 6; i++) check("arp src", txq[6 + i], OUR_MAC[i]);
        check("arp op", {txq[20], txq[21]}, 16'h0002);
        for (int i = 0; i < 6; i++) check("arp sender hw", txq[22 + i], OUR_MAC[i]);
        check("arp sender ip", {txq[28], txq[29], txq[30], txq[31]}, 32'hC0A82502);
        for (int i = 0; i < 6; i++) check("arp target hw", txq[32 + i], HOST_MAC[i]);
        check("arp target ip", {txq[38], txq[39], txq[40], txq[41]}, 32'hC0A82501);
        check("arp reply len", txq.size(), 42);
        txq.delete();

        // ---- ICMP echo request ----
        build_icmp(8'd2, 8'h08);
        send_frame(f, flen, 0);
        wait_frame(flen);
        check("icmp len", txq.size(), flen);
        for (int i = 0; i < 6; i++) check("icmp dst", txq[i], HOST_MAC[i]);
        for (int i = 0; i < 6; i++) check("icmp src", txq[6 + i], OUR_MAC[i]);
        check("icmp ip src", {txq[26], txq[27], txq[28], txq[29]}, 32'hC0A82502);
        check("icmp ip dst", {txq[30], txq[31], txq[32], txq[33]}, 32'hC0A82501);
        check("icmp type", txq[34], 8'h00);
        begin // verify the ICMP checksum over the reply
            byte unsigned r[0:255];
            for (int i = 0; i < flen; i++) r[i] = txq[i];
            check("icmp cksum", cksum(r, 34, flen - 34), 16'h0000);
            for (int i = 42; i < flen; i++) check("icmp payload", r[i], (3 * (i - 42) + 1) & 255);
        end
        txq.delete();

        // ---- ignored: wrong IP, wrong type, bad FCS ----
        build_icmp(8'd9, 8'h08); send_frame(f, flen, 0); // not our IP
        build_icmp(8'd2, 8'h00); send_frame(f, flen, 0); // echo reply, not request
        build_icmp(8'd2, 8'h08); send_frame(f, flen, 1); // FCS error
        repeat (2000) @(negedge clk);
        check("ignored frames", txq.size(), 0);

        // ---- still alive after the ignored ones ----
        build_icmp(8'd2, 8'h08);
        send_frame(f, flen, 0);
        wait_frame(flen);
        check("second echo len", txq.size(), flen);
        check("second echo type", txq[34], 8'h00);

        if (errors == 0) $display("PASS: eth_ip");
        else $fatal(1, "FAIL: eth_ip errors=%0d", errors);
        $finish;
    end

    int watchdog = 0;
    always @(posedge clk) if (RUN) begin
        watchdog++;
        if (watchdog > 2_000_000) $fatal(1, "TIMEOUT");
    end
endmodule
