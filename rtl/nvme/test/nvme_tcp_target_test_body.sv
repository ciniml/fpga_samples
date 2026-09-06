// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Test body for NvmeTcpTarget: drives the two per-connection byte
// streams as an NVMe/TCP host (ICReq, fabrics Connect / Property,
// Identify, Write via R2T, Read) and checks the PDUs coming back.
// RUN=0 by default (see nvme_core_test_body.sv).
`timescale 1ns/1ps
module nvme_tcp_target_test_body #(
    parameter RUN = 0,
    parameter LBA_COUNT = 128
);
    localparam MEM_ADDR_BITS = $clog2(LBA_COUNT) + 7;

    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic [1:0]  conn_active = 0;
    logic [1:0]  rx_valid = 0;
    logic [1:0]  rx_ready;
    logic [15:0] rx_data = 0;
    logic [1:0]  tx_valid;
    logic [15:0] tx_data;

    logic [MEM_ADDR_BITS-1:0] mem_addr;
    logic        mem_wen, mem_ren;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;

    NvmeTcpTarget #(.LBA_COUNT(LBA_COUNT)) dut (
        .i_clk(clk), .i_rst(rst),
        .i_conn_active(conn_active),
        .i_rx_valid(rx_valid), .o_rx_ready(rx_ready), .i_rx_data(rx_data),
        .o_tx_valid(tx_valid), .i_tx_ready(2'b11), .o_tx_data(tx_data),
        .o_mem_addr(mem_addr), .o_mem_wen(mem_wen), .o_mem_wdata(mem_wdata),
        .o_mem_ren(mem_ren), .i_mem_rdata(mem_rdata), .i_mem_ready(1'b1)
    );

    logic [31:0] bmem [0:LBA_COUNT*128-1];
    always @(posedge clk) begin
        if (mem_wen) bmem[mem_addr] <= mem_wdata;
        if (mem_ren) mem_rdata <= bmem[mem_addr];
    end

    // TX capture queues
    byte unsigned txq0[$], txq1[$];
    always @(posedge clk) begin
        if (tx_valid[0]) txq0.push_back(tx_data[7:0]);
        if (tx_valid[1]) txq1.push_back(tx_data[15:8]);
    end

    int errors = 0;

    task automatic check(input string what, input longint got, input longint exp);
        if (got !== exp) begin
            $display("ERROR: %s: got %0h expected %0h", what, got, exp);
            errors++;
        end
    endtask

    task automatic send_byte(input int c, input byte unsigned b);
        @(negedge clk);
        if (c == 0) begin rx_valid[0] = 1; rx_data[7:0] = b; end
        else begin rx_valid[1] = 1; rx_data[15:8] = b; end
        forever begin
            @(posedge clk);
            if (rx_ready[c]) break;
        end
        @(negedge clk);
        rx_valid[c] = 0;
    endtask

    task automatic send_buf(input int c, input byte unsigned data[4200], input int n);
        for (int i = 0; i < n; i++) send_byte(c, data[i]);
    endtask

    // pop n bytes from a connection's TX queue into buf
    task automatic recv_buf(input int c, output byte unsigned data[4200], input int n);
        int t = 0;
        while ((c == 0 ? txq0.size() : txq1.size()) < n) begin
            @(negedge clk);
            t++;
            if (t > 500000) begin
                $display("ERROR: recv timeout conn %0d want %0d have %0d",
                         c, n, c == 0 ? txq0.size() : txq1.size());
                errors++;
                return;
            end
        end
        for (int i = 0; i < n; i++) data[i] = (c == 0) ? txq0.pop_front() : txq1.pop_front();
    endtask

    function automatic void put32(ref byte unsigned b[4200], input int off, input logic [31:0] v);
        b[off] = v[7:0]; b[off+1] = v[15:8]; b[off+2] = v[23:16]; b[off+3] = v[31:24];
    endfunction
    function automatic logic [31:0] get32(ref byte unsigned b[4200], input int off);
        return {b[off+3], b[off+2], b[off+1], b[off]};
    endfunction

    byte unsigned pdu[4200];
    byte unsigned rsp[4200];

    task automatic make_ch(input byte unsigned t, input int plen);
        for (int i = 0; i < 4200; i++) pdu[i] = 0;
        pdu[0] = t; pdu[2] = 8'd24; put32(pdu, 4, plen);
    endtask

    // CapsuleCmd with a 64-byte SQE built from the arguments
    task automatic send_capsule(
        input int c, input byte unsigned opc, input logic [15:0] cid,
        input logic [31:0] nsid, input logic [31:0] dw10, input logic [31:0] dw11,
        input logic [31:0] dw12, input logic [31:0] dw13
    );
        make_ch(8'h04, 72);
        pdu[2] = 8'd72;
        pdu[8] = opc; pdu[10] = cid[7:0]; pdu[11] = cid[15:8];
        put32(pdu, 12, nsid);
        put32(pdu, 48, dw10); put32(pdu, 52, dw11);
        put32(pdu, 56, dw12); put32(pdu, 60, dw13);
        send_buf(c, pdu, 72);
    endtask

    // wait for a CapsuleResp and check cid/status; dw0 returned
    task automatic expect_resp(input string what, input int c, input logic [15:0] cid,
                               input logic [14:0] sts, output logic [31:0] dw0);
        recv_buf(c, rsp, 24);
        check({what, " resp type"}, rsp[0], 8'h05);
        check({what, " resp cid"}, {rsp[21], rsp[20]}, cid);
        check({what, " resp status"}, {rsp[23], rsp[22]} >> 1, sts);
        dw0 = get32(rsp, 8);
    endtask

    logic [31:0] dw0;
    byte unsigned wdata[4200];
    int t;

    initial if (RUN) begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge clk);
        conn_active[0] = 1;

        // ---- ICReq -> ICResp ----
        make_ch(8'h00, 128);
        pdu[2] = 8'd128;
        send_buf(0, pdu, 128);
        recv_buf(0, rsp, 128);
        check("icresp type", rsp[0], 8'h01);
        check("icresp maxh2cdata", get32(rsp, 12), 32'h0002_0000);

        // ---- Connect (qid 0) ----
        make_ch(8'h04, 72); pdu[2] = 8'd72;
        pdu[8] = 8'h7F; pdu[10] = 8'h01; // cid=1
        pdu[12] = 8'h01;                 // fctype=Connect
        pdu[50] = 8'h00; pdu[51] = 8'h00; // qid 0
        pdu[52] = 8'd31;                  // sqsize
        send_buf(0, pdu, 72);
        expect_resp("connect", 0, 16'h0001, 15'h0, dw0);
        check("connect cntlid", dw0[15:0], 16'd1);

        // ---- Property Get CAP / Set CC / Get CSTS ----
        make_ch(8'h04, 72); pdu[2] = 8'd72;
        pdu[8] = 8'h7F; pdu[10] = 8'h02; pdu[12] = 8'h04; // PropGet
        put32(pdu, 52, 32'h0);                            // CAP
        send_buf(0, pdu, 72);
        expect_resp("propget cap", 0, 16'h0002, 15'h0, dw0);
        check("cap.mqes", dw0[15:0], 16'h000F);

        make_ch(8'h04, 72); pdu[2] = 8'd72;
        pdu[8] = 8'h7F; pdu[10] = 8'h03; pdu[12] = 8'h00; // PropSet
        put32(pdu, 52, 32'h14);                           // CC
        put32(pdu, 56, 32'h0046_0001);
        send_buf(0, pdu, 72);
        expect_resp("propset cc", 0, 16'h0003, 15'h0, dw0);

        make_ch(8'h04, 72); pdu[2] = 8'd72;
        pdu[8] = 8'h7F; pdu[10] = 8'h04; pdu[12] = 8'h04;
        put32(pdu, 52, 32'h1C);                           // CSTS
        send_buf(0, pdu, 72);
        expect_resp("propget csts", 0, 16'h0004, 15'h0, dw0);
        check("csts.rdy", dw0[0], 1);

        // ---- Identify Controller: C2HData + patched fabrics fields ----
        send_capsule(0, 8'h06, 16'h0005, 0, 32'h1, 0, 0, 0);
        recv_buf(0, rsp, 24 + 4096);
        check("idn c2h type", rsp[0], 8'h07);
        check("idn c2h flags LAST", rsp[1], 8'h04);
        check("idn c2h datal", get32(rsp, 16), 32'd4096);
        check("idn SN[0]", get32(rsp, 24 + 4), 32'h5952_4556);   // "VERY"
        check("idn CNTLID", {rsp[24 + 79], rsp[24 + 78]}, 16'd1);
        check("idn SGLS", get32(rsp, 24 + 536), 32'h0030_0001);
        check("idn SUBNQN[0]", get32(rsp, 24 + 768), 32'h2E6E_716E); // "nqn."
        check("idn IOCCSZ", get32(rsp, 24 + 1792), 32'd4);
        expect_resp("identify", 0, 16'h0005, 15'h0, dw0);

        // ---- I/O connection (qid 1) ----
        conn_active[1] = 1;
        make_ch(8'h00, 128); pdu[2] = 8'd128;
        send_buf(1, pdu, 128);
        recv_buf(1, rsp, 128);
        check("icresp2 type", rsp[0], 8'h01);
        make_ch(8'h04, 72); pdu[2] = 8'd72;
        pdu[8] = 8'h7F; pdu[10] = 8'h01; pdu[12] = 8'h01;
        pdu[50] = 8'h01; pdu[52] = 8'd31; // qid 1
        send_buf(1, pdu, 72);
        expect_resp("connect io", 1, 16'h0001, 15'h0, dw0);

        // ---- Write 1 block at LBA 3: R2T flow ----
        send_capsule(1, 8'h01, 16'h0101, 32'h1, 32'd3, 0, 32'd0, 0);
        recv_buf(1, rsp, 24);
        check("r2t type", rsp[0], 8'h09);
        check("r2t cccid", {rsp[9], rsp[8]}, 16'h0101);
        check("r2t r2tl", get32(rsp, 16), 32'd512);
        make_ch(8'h06, 24 + 512); // H2CData
        pdu[1] = 8'h04; pdu[3] = 8'd24;
        pdu[8] = 8'h01; pdu[9] = 8'h01; pdu[10] = 8'h01; // cccid, ttag
        put32(pdu, 16, 32'd512);
        for (int i = 0; i < 512; i++) pdu[24 + i] = (i * 7 + 3) & 8'hFF;
        send_buf(1, pdu, 24 + 512);
        expect_resp("write", 1, 16'h0101, 15'h0, dw0);
        check("bmem[0]", bmem[3 * 128][7:0], 8'h03);

        // ---- Read it back ----
        send_capsule(1, 8'h02, 16'h0102, 32'h1, 32'd3, 0, 32'd0, 0);
        recv_buf(1, rsp, 24 + 512);
        check("read c2h type", rsp[0], 8'h07);
        for (int i = 0; i < 512; i++) begin
            if (rsp[24 + i] !== ((i * 7 + 3) & 8'hFF)) begin
                $display("ERROR: read data[%0d]: got %h", i, rsp[24 + i]);
                errors++;
            end
        end
        expect_resp("read", 1, 16'h0102, 15'h0, dw0);

        // ---- Out-of-range read: error completion, no data ----
        send_capsule(1, 8'h02, 16'h0103, 32'h1, 32'd127, 0, 32'd1, 0);
        expect_resp("read oor", 1, 16'h0103, 15'h4080, dw0);

        if (errors == 0) $display("PASS: nvme_tcp_target");
        else $fatal(1, "FAIL: nvme_tcp_target errors=%0d", errors);
        $finish;
    end

    int watchdog = 0;
    always @(posedge clk) if (RUN) begin
        watchdog++;
        if (watchdog > 5_000_000) $fatal(1, "TIMEOUT");
    end
endmodule
