// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Test body for NvmeController: models the host side of a PCIe-style
// attachment - a 1MiB host memory served over the DMA port, CSR
// accesses, SQ/CQ rings with doorbells and phase-tag polling.
// RUN=0 by default (see nvme_core_test_body.sv).
`timescale 1ns/1ps
module nvme_controller_test_body #(
    parameter RUN = 0,
    parameter LBA_COUNT = 128
);
    localparam MEM_ADDR_BITS = $clog2(LBA_COUNT) + 7;

    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic [13:0] csr_addr = 0;
    logic        csr_wen = 0;
    logic [31:0] csr_wdata = 0;
    logic [31:0] csr_rdata;
    logic        irq;

    logic        hm_valid, hm_write;
    logic [63:0] hm_addr;
    logic [31:0] hm_wdata;
    logic        hm_ready = 1;
    logic        hm_rvalid = 0;
    logic [31:0] hm_rdata = 0;

    logic [MEM_ADDR_BITS-1:0] mem_addr;
    logic        mem_wen, mem_ren;
    logic [31:0] mem_wdata;
    logic [31:0] mem_rdata;

    NvmeController #(.LBA_COUNT(LBA_COUNT)) dut (
        .i_clk(clk), .i_rst(rst),
        .i_csr_addr(csr_addr), .i_csr_wen(csr_wen), .i_csr_wdata(csr_wdata),
        .o_csr_rdata(csr_rdata), .o_irq(irq),
        .o_hm_valid(hm_valid), .o_hm_write(hm_write), .o_hm_addr(hm_addr),
        .o_hm_wdata(hm_wdata), .i_hm_ready(hm_ready),
        .i_hm_rvalid(hm_rvalid), .i_hm_rdata(hm_rdata),
        .o_mem_addr(mem_addr), .o_mem_wen(mem_wen), .o_mem_wdata(mem_wdata),
        .o_mem_ren(mem_ren), .i_mem_rdata(mem_rdata)
    );

    // Backing RAM model (1-cycle read latency)
    logic [31:0] bmem [0:LBA_COUNT*128-1];
    always @(posedge clk) begin
        if (mem_wen) bmem[mem_addr] <= mem_wdata;
        if (mem_ren) mem_rdata <= bmem[mem_addr];
    end

    // Host memory model: 1MiB, 1-cycle read latency
    logic [31:0] hmem [0:262143];
    always @(posedge clk) begin
        if (hm_valid && hm_ready && hm_write) hmem[hm_addr[21:2]] <= hm_wdata;
        hm_rvalid <= hm_valid && hm_ready && !hm_write;
        if (hm_valid && hm_ready && !hm_write) hm_rdata <= hmem[hm_addr[21:2]];
    end

    int errors = 0;

    task automatic check32(input string what, input logic [31:0] got, input logic [31:0] exp);
        if (got !== exp) begin
            $display("ERROR: %s: got %h expected %h", what, got, exp);
            errors++;
        end
    endtask

    task automatic csr_write(input logic [13:0] addr, input logic [31:0] data);
        @(negedge clk);
        csr_addr = addr; csr_wdata = data; csr_wen = 1;
        @(negedge clk);
        csr_wen = 0;
    endtask

    task automatic csr_read(input logic [13:0] addr, output logic [31:0] data);
        @(negedge clk);
        csr_addr = addr;
        @(negedge clk);
        data = csr_rdata;
    endtask

    // Host memory layout
    localparam ASQ  = 32'h0_0000; // 8 entries
    localparam ACQ  = 32'h0_1000; // 4 entries (exercises phase wrap)
    localparam IDBUF = 32'h0_2000;
    localparam IOCQ = 32'h0_4000; // 4 entries
    localparam IOSQ = 32'h0_5000; // 4 entries
    localparam WBUF0 = 32'h0_8000, WBUF1 = 32'h0_9000;
    localparam RBUF0 = 32'h0_A000, RBUF1 = 32'h0_B000;
    localparam OFSBUF = 32'h0_C800; // PRP1 with 0x800 in-page offset
    localparam OFSBUF2 = 32'h0_D000;

    localparam ASQ_SIZE = 8, ACQ_SIZE = 4, IOQ_SIZE = 4;

    task automatic write_sqe(
        input logic [31:0] base, input int slot,
        input logic [7:0] opc, input logic [15:0] cid, input logic [31:0] nsid,
        input logic [63:0] prp1, input logic [63:0] prp2,
        input logic [31:0] dw10, input logic [31:0] dw11, input logic [31:0] dw12
    );
        int b = (base + slot * 64) >> 2;
        for (int i = 0; i < 16; i++) hmem[b + i] = 32'h0;
        hmem[b + 0]  = {cid, 8'h00, opc};
        hmem[b + 1]  = nsid;
        hmem[b + 6]  = prp1[31:0];
        hmem[b + 7]  = prp1[63:32];
        hmem[b + 8]  = prp2[31:0];
        hmem[b + 9]  = prp2[63:32];
        hmem[b + 10] = dw10;
        hmem[b + 11] = dw11;
        hmem[b + 12] = dw12;
    endtask

    // Poll a CQE until its phase bit matches, then check status/cid.
    task automatic wait_cqe(
        input string what,
        input logic [31:0] cq_base, input int slot, input logic exp_phase,
        input logic [15:0] exp_cid, input logic [14:0] exp_sts,
        output logic [31:0] dw0, output logic [31:0] dw2
    );
        int b = (cq_base + slot * 16) >> 2;
        int t = 0;
        while (((hmem[b + 3] >> 16) & 1) !== exp_phase) begin
            @(negedge clk);
            t++;
            if (t > 200000) begin
                $display("ERROR: %s: CQE timeout (slot %0d)", what, slot);
                errors++;
                return;
            end
        end
        repeat (2) @(negedge clk);
        dw0 = hmem[b + 0];
        dw2 = hmem[b + 2];
        if (hmem[b + 3][15:0] !== exp_cid) begin
            $display("ERROR: %s: cid got %h expected %h", what, hmem[b + 3][15:0], exp_cid);
            errors++;
        end
        if (hmem[b + 3][31:17] !== exp_sts) begin
            $display("ERROR: %s: status got %h expected %h", what, hmem[b + 3][31:17], exp_sts);
            errors++;
        end
    endtask

    int adm_slot = 0;
    int adm_cpl = 0;
    int io_slot = 0;
    int io_cpl = 0;
    logic [31:0] dw0, dw2, d;

    function automatic logic adm_phase();
        return ((adm_cpl / ACQ_SIZE) % 2 == 0) ? 1'b1 : 1'b0;
    endfunction
    function automatic logic io_phase();
        return ((io_cpl / IOQ_SIZE) % 2 == 0) ? 1'b1 : 1'b0;
    endfunction

    task automatic ring_adm();
        adm_slot = (adm_slot + 1) % ASQ_SIZE;
        csr_write(14'h1000, adm_slot);
    endtask
    task automatic ring_io();
        io_slot = (io_slot + 1) % IOQ_SIZE;
        csr_write(14'h1008, io_slot);
    endtask

    int watchdog = 0;
    always @(posedge clk) if (RUN) begin
        watchdog++;
        if (watchdog > 5_000_000) $fatal(1, "TIMEOUT");
    end

    initial if (RUN) begin
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (5) @(negedge clk);

        // ---- registers ----
        csr_read(14'h0000, d); check32("CAP_LO", d, 32'h0F01_003F);
        csr_read(14'h0004, d); check32("CAP_HI", d, 32'h0000_0020);
        csr_read(14'h0008, d); check32("VS", d, 32'h0001_0400);
        csr_read(14'h001C, d); check32("CSTS before EN", d, 32'h0);

        // ---- enable controller ----
        csr_write(14'h0024, ((ACQ_SIZE - 1) << 16) | (ASQ_SIZE - 1)); // AQA
        csr_write(14'h0028, ASQ); csr_write(14'h002C, 0);
        csr_write(14'h0030, ACQ); csr_write(14'h0034, 0);
        csr_write(14'h0014, 32'h0046_0001); // CC: IOSQES=6 IOCQES=4 EN
        csr_read(14'h001C, d); check32("CSTS.RDY", d & 1, 1);

        // ---- admin: Identify Controller ----
        write_sqe(ASQ, adm_slot, 8'h06, 16'h1101, 0, IDBUF, 0, 32'h1, 0, 0);
        ring_adm();
        wait_cqe("identify", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1101, 15'h0, dw0, dw2);
        check32("identify sqhd/sqid", dw2, 32'h0000_0001);
        adm_cpl++;
        check32("identify SN[0]", hmem[(IDBUF >> 2) + 1], 32'h5952_4556);
        check32("identify VER", hmem[(IDBUF >> 2) + 20], 32'h0001_0400);
        check32("identify MDTS", hmem[(IDBUF >> 2) + 19], 32'h0000_0100);

        // ---- irq: pending until CQ head doorbell written ----
        if (irq !== 1'b1) begin $display("ERROR: irq not asserted after CQE"); errors++; end
        csr_write(14'h1004, adm_cpl % ACQ_SIZE); // ACQ head doorbell
        @(negedge clk);
        if (irq !== 1'b0) begin $display("ERROR: irq still asserted after head db"); errors++; end

        // ---- admin: Create I/O CQ / SQ (QID 1) ----
        write_sqe(ASQ, adm_slot, 8'h05, 16'h1102, 0, IOCQ, 0,
                  ((IOQ_SIZE - 1) << 16) | 16'd1, 32'h3, 0);
        ring_adm();
        wait_cqe("create iocq", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1102, 15'h0, dw0, dw2);
        adm_cpl++;
        write_sqe(ASQ, adm_slot, 8'h01, 16'h1103, 0, IOSQ, 0,
                  ((IOQ_SIZE - 1) << 16) | 16'd1, 32'h0001_0001, 0);
        ring_adm();
        wait_cqe("create iosq", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1103, 15'h0, dw0, dw2);
        adm_cpl++;

        // ---- I/O: write 8KiB at LBA 2 (PRP1 + PRP2) ----
        for (int i = 0; i < 1024; i++) hmem[(WBUF0 >> 2) + i] = 32'hA500_0000 + i;
        for (int i = 0; i < 1024; i++) hmem[(WBUF1 >> 2) + i] = 32'hA500_0400 + i;
        write_sqe(IOSQ, io_slot, 8'h01, 16'h2201, 1, WBUF0, WBUF1, 32'd2, 0, 32'd15);
        ring_io();
        wait_cqe("io write", IOCQ, io_cpl % IOQ_SIZE, io_phase(), 16'h2201, 15'h0, dw0, dw2);
        check32("io write sqhd/sqid", dw2, 32'h0001_0001);
        io_cpl++;
        check32("backing[0]", bmem[2 * 128], 32'hA500_0000);
        check32("backing[2047]", bmem[2 * 128 + 2047], 32'hA500_07FF);

        // ---- I/O: read it back ----
        write_sqe(IOSQ, io_slot, 8'h02, 16'h2202, 1, RBUF0, RBUF1, 32'd2, 0, 32'd15);
        ring_io();
        wait_cqe("io read", IOCQ, io_cpl % IOQ_SIZE, io_phase(), 16'h2202, 15'h0, dw0, dw2);
        io_cpl++;
        for (int i = 0; i < 2048; i++) begin
            logic [31:0] got = (i < 1024) ? hmem[(RBUF0 >> 2) + i] : hmem[(RBUF1 >> 2) + i - 1024];
            if (got !== 32'hA500_0000 + i) begin
                $display("ERROR: read data[%0d]: got %h expected %h", i, got, 32'hA500_0000 + i);
                errors++;
            end
        end

        // ---- I/O: out-of-range read -> error, no data phase ----
        write_sqe(IOSQ, io_slot, 8'h02, 16'h2203, 1, RBUF0, 0, 32'd120, 0, 32'd15);
        ring_io();
        wait_cqe("io oor", IOCQ, io_cpl % IOQ_SIZE, io_phase(), 16'h2203, 15'h4080, dw0, dw2);
        io_cpl++;

        // ---- I/O: flushes to wrap the CQ (phase flip) ----
        write_sqe(IOSQ, io_slot, 8'h00, 16'h2204, 1, 0, 0, 0, 0, 0);
        ring_io();
        wait_cqe("io flush", IOCQ, io_cpl % IOQ_SIZE, io_phase(), 16'h2204, 15'h0, dw0, dw2);
        io_cpl++;
        write_sqe(IOSQ, io_slot, 8'h00, 16'h2205, 1, 0, 0, 0, 0, 0);
        ring_io();
        wait_cqe("io flush wrap (phase 0)", IOCQ, io_cpl % IOQ_SIZE, io_phase(), 16'h2205, 15'h0, dw0, dw2);
        io_cpl++;

        // ---- I/O: 1-block read into an offset PRP1 ----
        write_sqe(IOSQ, io_slot, 8'h02, 16'h2206, 1, OFSBUF, 0, 32'd2, 0, 32'd0);
        ring_io();
        wait_cqe("io read prp1-offset", IOCQ, io_cpl % IOQ_SIZE, io_phase(), 16'h2206, 15'h0, dw0, dw2);
        io_cpl++;
        for (int i = 0; i < 128; i++) begin
            if (hmem[(OFSBUF >> 2) + i] !== 32'hA500_0000 + i) begin
                $display("ERROR: offset read[%0d]: got %h", i, hmem[(OFSBUF >> 2) + i]);
                errors++;
            end
        end

        // ---- admin: Identify with PRP1 offset crossing into PRP2 ----
        write_sqe(ASQ, adm_slot, 8'h06, 16'h1104, 0, OFSBUF, OFSBUF2, 32'h1, 0, 0);
        ring_adm();
        wait_cqe("identify offset", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1104, 15'h0, dw0, dw2);
        adm_cpl++;
        for (int i = 0; i < 1024; i++) begin
            logic [31:0] got = (i < 512) ? hmem[(OFSBUF >> 2) + i] : hmem[(OFSBUF2 >> 2) + i - 512];
            if (got !== hmem[(IDBUF >> 2) + i]) begin
                $display("ERROR: identify offset[%0d]: got %h expected %h", i, got, hmem[(IDBUF >> 2) + i]);
                errors++;
            end
        end

        // ---- admin: Get Features NQ; ACQ wraps on the next completion ----
        write_sqe(ASQ, adm_slot, 8'h0A, 16'h1105, 0, 0, 0, 32'h7, 0, 0);
        ring_adm();
        wait_cqe("get features", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1105, 15'h0, dw0, dw2);
        check32("get features dw0", dw0, 0);
        adm_cpl++;
        write_sqe(ASQ, adm_slot, 8'h09, 16'h1106, 0, 0, 0, 32'h7, 0, 0);
        ring_adm();
        wait_cqe("set features wrap (phase 0)", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1106, 15'h0, dw0, dw2);
        adm_cpl++;

        // ---- admin: queue deletion (CQ first must fail) ----
        write_sqe(ASQ, adm_slot, 8'h04, 16'h1107, 0, 0, 0, 32'd1, 0, 0);
        ring_adm();
        wait_cqe("delete iocq early", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1107, 15'h4100, dw0, dw2);
        adm_cpl++;
        write_sqe(ASQ, adm_slot, 8'h00, 16'h1108, 0, 0, 0, 32'd1, 0, 0);
        ring_adm();
        wait_cqe("delete iosq", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1108, 15'h0, dw0, dw2);
        adm_cpl++;
        write_sqe(ASQ, adm_slot, 8'h04, 16'h1109, 0, 0, 0, 32'd1, 0, 0);
        ring_adm();
        wait_cqe("delete iocq", ACQ, adm_cpl % ACQ_SIZE, adm_phase(), 16'h1109, 15'h0, dw0, dw2);
        adm_cpl++;

        if (errors == 0) $display("PASS: nvme_controller");
        else $fatal(1, "FAIL: nvme_controller errors=%0d", errors);
        $finish;
    end
endmodule
