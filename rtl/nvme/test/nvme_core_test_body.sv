// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Test body for NvmeCore: acts as the "transport" (feeds SQEs, moves the
// h2c/c2h data streams, receives completions) and provides the backing
// RAM model. RUN=0 by default so that -Wno-MULTITOP builds don't run it.
`timescale 1ns/1ps
module nvme_core_test_body #(
    parameter RUN = 0,
    parameter LBA_COUNT = 128
);
    localparam MEM_ADDR_BITS = $clog2(LBA_COUNT) + 7;

    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic        sq_valid = 0, sq_admin = 0;
    logic        sq_ready;
    logic [31:0] sq_data = 0;

    logic        cpl_valid;
    logic        cpl_ready = 0;
    logic [15:0] cpl_cid;
    logic [14:0] cpl_status;
    logic [31:0] cpl_dw0;

    logic        h2c_valid = 0;
    logic        h2c_ready;
    logic [31:0] h2c_data = 0;

    logic        c2h_valid;
    logic        c2h_ready = 0;
    logic [31:0] c2h_data;
    logic        c2h_last;

    logic [MEM_ADDR_BITS-1:0] mem_addr;
    logic        mem_wen, mem_ren;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;

    NvmeCore #(.LBA_COUNT(LBA_COUNT)) dut (
        .i_clk(clk), .i_rst(rst),
        .i_sq_valid(sq_valid), .o_sq_ready(sq_ready),
        .i_sq_data(sq_data), .i_sq_is_admin(sq_admin),
        .o_cpl_valid(cpl_valid), .i_cpl_ready(cpl_ready),
        .o_cpl_cid(cpl_cid), .o_cpl_status(cpl_status), .o_cpl_dw0(cpl_dw0),
        .i_h2c_valid(h2c_valid), .o_h2c_ready(h2c_ready), .i_h2c_data(h2c_data),
        .o_c2h_valid(c2h_valid), .i_c2h_ready(c2h_ready),
        .o_c2h_data(c2h_data), .o_c2h_last(c2h_last),
        .o_mem_addr(mem_addr), .o_mem_wen(mem_wen), .o_mem_wdata(mem_wdata),
        .o_mem_ren(mem_ren), .i_mem_rdata(mem_rdata)
    );

    // Backing RAM model: dword-wide, 1-cycle read latency
    logic [31:0] mem [0:LBA_COUNT*128-1];
    always @(posedge clk) begin
        if (mem_wen) mem[mem_addr] <= mem_wdata;
        if (mem_ren) mem_rdata <= mem[mem_addr];
    end

    int errors = 0;

    // NVMe status field values as this core reports them (DNR set)
    localparam logic [14:0] STS_OK           = 15'h0000;
    localparam logic [14:0] STS_INVALID_OPC  = 15'h4001;
    localparam logic [14:0] STS_INVALID_FLD  = 15'h4002;
    localparam logic [14:0] STS_INVALID_NSID = 15'h400B;
    localparam logic [14:0] STS_LBA_RANGE    = 15'h4080;

    task automatic check32(input string what, input logic [31:0] got, input logic [31:0] exp);
        if (got !== exp) begin
            $display("ERROR: %s: got %h expected %h", what, got, exp);
            errors++;
        end
    endtask

    function automatic void make_sqe(
        output logic [31:0] d [0:15],
        input  logic [7:0]  opc,
        input  logic [15:0] cid,
        input  logic [31:0] nsid,
        input  logic [31:0] dw10,
        input  logic [31:0] dw11,
        input  logic [31:0] dw12
    );
        for (int i = 0; i < 16; i++) d[i] = 32'h0;
        d[0]  = {cid, 8'h00, opc};
        d[1]  = nsid;
        d[10] = dw10;
        d[11] = dw11;
        d[12] = dw12;
    endfunction

    task automatic send_sqe(input bit admin, input logic [31:0] d [0:15]);
        for (int i = 0; i < 16; i++) begin
            @(negedge clk);
            sq_valid = 1;
            sq_admin = admin;
            sq_data  = d[i];
            forever begin
                @(posedge clk);
                if (sq_ready) break;
            end
        end
        @(negedge clk);
        sq_valid = 0;
    endtask

    task automatic get_cpl(input string what, input logic [15:0] exp_cid, input logic [14:0] exp_sts);
        cpl_ready = 0;
        @(negedge clk);
        cpl_ready = 1;
        forever begin
            @(posedge clk);
            if (cpl_valid) break;
        end
        if (cpl_cid !== exp_cid) begin
            $display("ERROR: %s: cid got %h expected %h", what, cpl_cid, exp_cid);
            errors++;
        end
        if (cpl_status !== exp_sts) begin
            $display("ERROR: %s: status got %h expected %h", what, cpl_status, exp_sts);
            errors++;
        end
        @(negedge clk);
        cpl_ready = 0;
    endtask

    // Receive n dwords on c2h into cbuf; check that last is asserted
    // exactly on the final dword. bp enables random backpressure.
    logic [31:0] cbuf [0:1023];
    task automatic recv_c2h(input string what, input int n, input bit bp);
        int i = 0;
        while (i < n) begin
            @(negedge clk);
            c2h_ready = bp ? ($urandom_range(0, 3) != 0) : 1'b1;
            @(posedge clk);
            if (c2h_valid && c2h_ready) begin
                if (i < 1024) cbuf[i] = c2h_data;
                if (c2h_last !== (i == n - 1)) begin
                    $display("ERROR: %s: c2h_last=%b at dword %0d of %0d", what, c2h_last, i, n);
                    errors++;
                end
                i++;
            end
        end
        @(negedge clk);
        c2h_ready = 0;
    endtask

    task automatic send_h2c(input int n, input logic [31:0] base);
        for (int i = 0; i < n; i++) begin
            @(negedge clk);
            h2c_valid = 1;
            h2c_data  = base + i;
            forever begin
                @(posedge clk);
                if (h2c_ready) break;
            end
        end
        @(negedge clk);
        h2c_valid = 0;
    endtask

    logic [31:0] sqe [0:15];

    int watchdog = 0;
    always @(posedge clk) if (RUN) begin
        watchdog++;
        if (watchdog > 2_000_000) $fatal(1, "TIMEOUT");
    end

    initial if (RUN) begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge clk);

        // ---- Identify Controller ----
        make_sqe(sqe, 8'h06, 16'h1101, 32'h0, 32'h0000_0001, 32'h0, 32'h0);
        send_sqe(1, sqe);
        recv_c2h("identify ctrl", 1024, 0);
        get_cpl("identify ctrl", 16'h1101, STS_OK);
        check32("idn ctrl SN[0]", cbuf[1], 32'h5952_4556);   // "VERY"
        check32("idn ctrl VER", cbuf[20], 32'h0001_0400);    // NVMe 1.4
        check32("idn ctrl SQES/CQES", cbuf[128], 32'h0000_4466);
        check32("idn ctrl NN", cbuf[129], 32'h0000_0001);

        // ---- Identify Namespace (NSID 1) ----
        make_sqe(sqe, 8'h06, 16'h1102, 32'h1, 32'h0000_0000, 32'h0, 32'h0);
        send_sqe(1, sqe);
        recv_c2h("identify ns", 1024, 1);
        get_cpl("identify ns", 16'h1102, STS_OK);
        check32("idn ns NSZE", cbuf[0], LBA_COUNT);
        check32("idn ns NCAP", cbuf[2], LBA_COUNT);
        check32("idn ns LBAF0", cbuf[32], 32'h0009_0000);    // LBADS=9

        // ---- Identify Namespace with bad NSID -> error, no data ----
        make_sqe(sqe, 8'h06, 16'h1103, 32'h5, 32'h0000_0000, 32'h0, 32'h0);
        send_sqe(1, sqe);
        get_cpl("identify bad nsid", 16'h1103, STS_INVALID_NSID);

        // ---- Identify Active NS list ----
        make_sqe(sqe, 8'h06, 16'h1104, 32'h0, 32'h0000_0002, 32'h0, 32'h0);
        send_sqe(1, sqe);
        recv_c2h("identify ns list", 1024, 0);
        get_cpl("identify ns list", 16'h1104, STS_OK);
        check32("ns list[0]", cbuf[0], 32'h0000_0001);
        check32("ns list[1]", cbuf[1], 32'h0000_0000);

        // ---- Identify NS descriptor list (NSID 1) ----
        make_sqe(sqe, 8'h06, 16'h1107, 32'h1, 32'h0000_0003, 32'h0, 32'h0);
        send_sqe(1, sqe);
        recv_c2h("identify ns desc", 1024, 0);
        get_cpl("identify ns desc", 16'h1107, STS_OK);
        check32("ns desc NIDT/NIDL", cbuf[0], 32'h0000_0801);
        check32("ns desc EUI64[0]", cbuf[1], 32'h5952_4556);
        check32("ns desc CSI desc", cbuf[3], 32'h0000_0104);

        // ---- Set Features: Number of Queues ----
        make_sqe(sqe, 8'h09, 16'h1105, 32'h0, 32'h0000_0007, 32'h0001_0001, 32'h0);
        send_sqe(1, sqe);
        get_cpl("set features NQ", 16'h1105, STS_OK);
        check32("set features NQ dw0", cpl_dw0, 32'h0);

        // ---- unknown admin opcode ----
        make_sqe(sqe, 8'hC0, 16'h1106, 32'h0, 32'h0, 32'h0, 32'h0);
        send_sqe(1, sqe);
        get_cpl("bad admin opc", 16'h1106, STS_INVALID_OPC);

        // ---- Write 2 blocks at LBA 3 ----
        make_sqe(sqe, 8'h01, 16'h2201, 32'h1, 32'd3, 32'h0, 32'd1); // NLB=1 -> 2 blocks
        send_sqe(0, sqe);
        send_h2c(256, 32'hA500_0000);
        get_cpl("write", 16'h2201, STS_OK);
        check32("mem after write [0]", mem[3*128], 32'hA500_0000);
        check32("mem after write [255]", mem[3*128 + 255], 32'hA500_00FF);

        // ---- Read them back (with backpressure) ----
        make_sqe(sqe, 8'h02, 16'h2202, 32'h1, 32'd3, 32'h0, 32'd1);
        send_sqe(0, sqe);
        recv_c2h("read", 256, 1);
        get_cpl("read", 16'h2202, STS_OK);
        for (int i = 0; i < 256; i++) begin
            if (cbuf[i] !== 32'hA500_0000 + i) begin
                $display("ERROR: read data[%0d]: got %h expected %h", i, cbuf[i], 32'hA500_0000 + i);
                errors++;
            end
        end

        // ---- Read out of range: LBA 127, 2 blocks -> 129 > 128 ----
        make_sqe(sqe, 8'h02, 16'h2203, 32'h1, 32'd127, 32'h0, 32'd1);
        send_sqe(0, sqe);
        get_cpl("read out of range", 16'h2203, STS_LBA_RANGE);

        // ---- Read with bad NSID ----
        make_sqe(sqe, 8'h02, 16'h2204, 32'h2, 32'd0, 32'h0, 32'd0);
        send_sqe(0, sqe);
        get_cpl("read bad nsid", 16'h2204, STS_INVALID_NSID);

        // ---- Flush ----
        make_sqe(sqe, 8'h00, 16'h2205, 32'h1, 32'h0, 32'h0, 32'h0);
        send_sqe(0, sqe);
        get_cpl("flush", 16'h2205, STS_OK);

        // ---- unknown NVM opcode ----
        make_sqe(sqe, 8'h7F, 16'h2206, 32'h1, 32'h0, 32'h0, 32'h0);
        send_sqe(0, sqe);
        get_cpl("bad nvm opc", 16'h2206, STS_INVALID_OPC);

        // ---- last-block read: LBA 127, 1 block ----
        make_sqe(sqe, 8'h01, 16'h2207, 32'h1, 32'd127, 32'h0, 32'd0);
        send_sqe(0, sqe);
        send_h2c(128, 32'h5A5A_0000);
        get_cpl("write last block", 16'h2207, STS_OK);
        make_sqe(sqe, 8'h02, 16'h2208, 32'h1, 32'd127, 32'h0, 32'd0);
        send_sqe(0, sqe);
        recv_c2h("read last block", 128, 0);
        get_cpl("read last block", 16'h2208, STS_OK);
        check32("last block data[0]", cbuf[0], 32'h5A5A_0000);
        check32("last block data[127]", cbuf[127], 32'h5A5A_007F);

        if (errors == 0) $display("PASS: nvme_core");
        else $fatal(1, "FAIL: nvme_core errors=%0d", errors);
        $finish;
    end
endmodule
