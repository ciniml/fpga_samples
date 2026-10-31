// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
//
// Ddr2Ctrl + ddr2_model (Verilator --timing).
//   For every model read delay 0..7 slots (and once with the odd-beat
//   shift): reset, init + auto-calibration, then
//     1. a sequential write stream over 4096 bursts (64 KB: pages, banks),
//        throughput measured
//     2. the same range read back as a stream, compared
//     3. random reads / writes (row hits and misses, read <-> write
//        turnarounds) against a reference, across refreshes
//     4. a few bursts checked directly in the model's array (byte order)
//   PASS when nothing mismatched and the model saw no protocol error.
`timescale 1ns / 1ps
module tb;
    parameter int CL = 4;
    localparam int PCLK_PS = 12000;
    localparam int T_INIT  = 20_000_000; // shortened power-up wait (20 us)
    localparam int AW      = 21;

    logic clk = 1'b0;
    always #6 clk = ~clk;

    logic           rst = 1'b1;
    logic           req_valid = 1'b0;
    logic           req_ready;
    logic           req_we = 1'b0;
    logic [AW-1:0]  req_addr = '0;
    logic [127:0]   req_wdata = '0;
    logic           rd_valid;
    logic [127:0]   rd_data;
    logic           init_done, cal_ok, cal_fail;
    logic [5:0]     rd_sel, rd_sel_odd;
    logic [3:0]     rd_lat;

    logic           cke, odt, cs_n, ras_n, cas_n, we_n;
    logic [1:0]     ba;
    logic [12:0]    a;
    logic [127:0]   dq_out, dq_in;
    logic [3:0]     dq_oe, dqs_oe;
    logic [15:0]    dqs_out, dqs_in;

    logic [2:0]     rd_delay = 3'd0;
    logic           odd_shift = 1'b0;
    int             m_errors, m_refs, m_wr, m_rd;
    logic           m_report = 1'b0;
    logic           m_init;

    Ddr2Ctrl #(
        .PCLK_PS  (PCLK_PS),
        .CL       (CL),
        .T_INIT_PS(T_INIT)
    ) dut (
        .i_clk       (clk),
        .i_rst       (rst),
        .i_req_valid (req_valid),
        .o_req_ready (req_ready),
        .i_req_we    (req_we),
        .i_req_addr  (req_addr),
        .i_req_wdata (req_wdata),
        .o_rd_valid  (rd_valid),
        .o_rd_data   (rd_data),
        .o_init_done (init_done),
        .o_cal_ok    (cal_ok),
        .o_cal_fail  (cal_fail),
        .o_rd_sel    (rd_sel),
        .o_rd_sel_odd(rd_sel_odd),
        .o_rd_lat    (rd_lat),
        .o_cke       (cke),
        .o_odt       (odt),
        .o_cs_n      (cs_n),
        .o_ras_n     (ras_n),
        .o_cas_n     (cas_n),
        .o_we_n      (we_n),
        .o_ba        (ba),
        .o_a         (a),
        .o_dq_out    (dq_out),
        .o_dq_oe     (dq_oe),
        .o_dqs_out   (dqs_out),
        .o_dqs_oe    (dqs_oe),
        .i_dq_in     (dq_in),
        .i_dqs_in    (dqs_in)
    );

    ddr2_model #(
        .CL       (CL),
        .CK_PS    (PCLK_PS / 2),
        .T_INIT_PS(T_INIT)
    ) mdl (
        .clk           (clk),
        .rst           (rst),
        .rd_delay_slots(rd_delay),
        .rd_odd_shift  (odd_shift),
        .report        (m_report),
        .cke           (cke),
        .cs_n          (cs_n),
        .ras_n         (ras_n),
        .cas_n         (cas_n),
        .we_n          (we_n),
        .ba            (ba),
        .a             (a),
        .dq_out        (dq_out),
        .dq_oe         (dq_oe),
        .dqs_out       (dqs_out),
        .dqs_oe        (dqs_oe),
        .dq_in         (dq_in),
        .dqs_in        (dqs_in),
        .errors        (m_errors),
        .ref_count     (m_refs),
        .wr_bursts     (m_wr),
        .rd_bursts     (m_rd),
        .init_done     (m_init)
    );

    // ---- reference and read checking ----
    logic [127:0] ref_mem [int];
    logic [127:0] exp_q [$];
    int           mismatches = 0;
    int           reads_done = 0;

    always @(posedge clk) begin
        if (!rst && rd_valid) begin
            if (exp_q.size() == 0) begin
                $error("read data without a request");
                mismatches++;
            end else begin
                logic [127:0] e;
                e = exp_q.pop_front();
                if (rd_data !== e) begin
                    if (mismatches < 10) $error("read mismatch: got %h expected %h", rd_data, e);
                    mismatches++;
                end
                reads_done++;
            end
        end
    end

    function automatic logic [127:0] pattern(input int addr, input int seed);
        logic [127:0] v;
        for (int i = 0; i < 4; i++) v[32*i +: 32] = (addr * 32'h9E37_79B9) ^ (seed * 32'h85EB_CA6B) ^ (i * 32'hC2B2_AE35) ^ {addr[15:0], 16'(i)};
        return v;
    endfunction

    // Driven at the falling edge (called at a falling edge, returns at the
    // next one after the accepting rising edge).
    task automatic request(input logic we, input int addr, input logic [127:0] d);
        req_valid = 1'b1;
        req_we    = we;
        req_addr  = addr[AW-1:0];
        req_wdata = d;
        while (!req_ready) @(negedge clk);
        if (we) ref_mem[addr] = d;
        else exp_q.push_back(ref_mem.exists(addr) ? ref_mem[addr] : 128'hx);
        @(negedge clk);
        req_valid = 1'b0;
    endtask

    task automatic idle(input int n);
        repeat (n) @(negedge clk);
    endtask

    task automatic drain();
        int n = 0;
        while (exp_q.size() != 0 && n < 1000) begin @(negedge clk); n++; end
        if (exp_q.size() != 0) begin $error("reads outstanding: %0d", exp_q.size()); mismatches++; end
        idle(20);
    endtask

    int t_start, t_cycle = 0;
    always @(posedge clk) t_cycle++;

    task automatic run_once(input int delay, input logic shift);
        int n0;
        rd_delay  = delay[2:0];
        odd_shift = shift;
        rst       = 1'b1;
        ref_mem.delete();
        exp_q.delete();
        idle(10);
        rst = 1'b0;
        while (!init_done) @(negedge clk);
        $display("delay %0d%s: init done at %0d cycles, cal_ok %0d cal_fail %0d RD_LAT %0d RD_SEL %0d / %0d",
                 delay, shift ? " odd-shift" : "", t_cycle, cal_ok, cal_fail, rd_lat, rd_sel, rd_sel_odd);
        if (!cal_ok) mismatches++;

        // 1. sequential write stream
        t_start = t_cycle;
        for (int i = 0; i < 4096; i++) request(1'b1, i, pattern(i, delay));
        $display("  write stream: 4096 bursts in %0d cycles (%.1f MB/s)", t_cycle - t_start,
                 4096.0 * 16.0 / ((t_cycle - t_start) * PCLK_PS * 1e-12) / 1e6);
        // 2. read stream
        t_start = t_cycle;
        n0 = reads_done;
        for (int i = 0; i < 4096; i++) request(1'b0, i, '0);
        drain();
        $display("  read stream:  4096 bursts in %0d cycles", t_cycle - t_start);
        // 3. random traffic (row hits and misses, turnarounds), over refreshes
        for (int i = 0; i < 6000; i++) begin
            int ad;
            logic we;
            case ($urandom_range(0, 3))
                0: ad = $urandom_range(0, 4095);             // written range
                1: ad = 4096 + $urandom_range(0, 63);        // a page next to it
                2: ad = $urandom_range(0, (1 << AW) - 1);     // anywhere
                default: ad = 100 + $urandom_range(0, 7);    // same page
            endcase
            we = $urandom_range(0, 1) || !ref_mem.exists(ad);
            request(we, ad, {$urandom, $urandom, $urandom, $urandom});
            if ($urandom_range(0, 7) == 0) idle($urandom_range(1, 20));
        end
        drain();
        // 4. byte order in the device: burst address -> {row, bank, col}
        foreach (ref_mem[ad]) begin
            if (ad < 64) begin
                longint row  = ad >> 8;
                longint bank = (ad >> 6) & 3;
                longint col  = (ad & 63) << 3;
                longint base = ((row << 11) | (bank << 9) | col) << 1;
                for (int k = 0; k < 16; k++) begin
                    if (mdl.peek(base + k) !== ref_mem[ad][8*k +: 8]) begin
                        if (mismatches < 10) $error("model byte %0d of burst %0d: %h, expected %h", k, ad, mdl.peek(base + k), ref_mem[ad][8*k +: 8]);
                        mismatches++;
                    end
                end
            end
        end
        $display("  reads checked %0d, mismatches %0d", reads_done - n0, mismatches);
        m_report = 1'b1;
        idle(1);
        m_report = 1'b0;
    endtask

    initial begin
        for (int d = 0; d < 8; d++) run_once(d, 1'b0);
        run_once(3, 1'b1);
        // the model prints MODEL FAIL itself (checked by the Makefile)
        if (mismatches == 0) $display("PASS");
        else $display("FAIL (mismatches %0d)", mismatches);
        $finish;
    end

    initial begin
        #400ms;
        $display("FAIL (timeout)");
        $finish;
    end
endmodule
