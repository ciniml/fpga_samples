// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Device-level test: Usb3Top + Usb3Device against the PIPE host model.
// Enumeration (descriptors, address, configuration), vendor requests,
// STALL, EP1 bulk OUT / IN byte streams with NRDY/ERDY flow control.
`timescale 1ns/1ps
// RUN: Verilator runs every test body of include_files as an implicit top in every test, so the
// body only acts when instantiated with RUN = 1 (TbUsb3Prim's test wrappers); it ends with $finish
// on success, $fatal on failure (veryl test counts a $finish as success)
module usb3_device_test_body #(parameter bit RUN = 0);
    logic clk = 0;
    logic rst = 1;
    always #4 clk = ~clk;
    initial if (RUN) begin repeat (6_000_000) @(posedge clk); $fatal(1, "TIMEOUT at stage %s", stage); end
    string stage = "init";

    logic [31:0] rx_data, tx_data; logic [3:0] rx_k, tx_k; logic rx_valid; logic [2:0] rx_status;
    logic rx_elecidle, phy_status, power_present, tx_elecidle, tx_detectrx, rx_polarity, rx_termination;
    logic [1:0] power_down;
    logic rx_hp_valid; logic [95:0] rx_hp_hdr;
    logic dpp_start, dpp_valid, dpp_end, dpp_err; logic [31:0] dpp_data; logic [3:0] dpp_be;
    logic tx_hp_valid, tx_dpp, tx_hp_ready, tx_hp_idle; logic [95:0] tx_hp_hdr; logic [10:0] tx_dpp_len; logic [12:0] tx_dpp_base;
    logic dpp_rd; logic [12:0] dpp_addr; logic [31:0] dpp_rdata;
    logic [4:0] ltssm_state; logic in_u0, u0_entry, hot_reset, warm_reset, link_configured;
    logic dev_configured, dev_reset; logic [6:0] dev_address; logic [15:0] vendor_reg;
    logic [31:0] vendor_status = 32'hCAFE1234;
    // register port: a small register file (32 x 16 bits), read back as {~addr, value}
    logic reg_wr; logic [7:0] reg_addr; logic [15:0] reg_wdata; logic [15:0] regs[32];
    wire [31:0] reg_rdata = {8'(~reg_addr), 8'h0, regs[reg_addr[4:0]]};
    always @(posedge clk) if (reg_wr) regs[reg_addr[4:0]] <= reg_wdata;
    logic app_rx_valid, app_rx_ready = 1, app_tx_valid = 0, app_tx_ready; logic [7:0] app_rx_data, app_tx_data = 0;
    logic app_txw_valid = 0, app_txw_ready; logic [31:0] app_txw_data = 0;
    logic [7:0] q2_short[$];

    Usb3Top #(.TSEQ_COUNT(64)) dut(.i_clk(clk), .i_rst(rst),
        .i_rx_data(rx_data), .i_rx_k(rx_k), .i_rx_valid(rx_valid), .i_rx_status(rx_status), .i_rx_elecidle(rx_elecidle),
        .i_phy_status(phy_status), .i_power_present(power_present),
        .o_tx_data(tx_data), .o_tx_k(tx_k), .o_tx_elecidle(tx_elecidle), .o_tx_detectrx(tx_detectrx),
        .o_power_down(power_down), .o_rx_polarity(rx_polarity), .o_rx_termination(rx_termination),
        .o_rx_hp_valid(rx_hp_valid), .o_rx_hp_hdr(rx_hp_hdr),
        .o_dpp_start(dpp_start), .o_dpp_valid(dpp_valid), .o_dpp_data(dpp_data), .o_dpp_be(dpp_be), .o_dpp_end(dpp_end), .o_dpp_err(dpp_err),
        .i_tx_hp_valid(tx_hp_valid), .i_tx_hp_hdr(tx_hp_hdr), .i_tx_dpp(tx_dpp), .i_tx_dpp_len(tx_dpp_len), .i_tx_dpp_base(tx_dpp_base),
        .o_tx_hp_ready(tx_hp_ready), .o_tx_hp_idle(tx_hp_idle),
        .o_dpp_rd(dpp_rd), .o_dpp_addr(dpp_addr), .i_dpp_data(dpp_rdata),
        .o_ltssm_state(ltssm_state), .o_in_u0(in_u0), .o_u0_entry(u0_entry), .o_hot_reset(hot_reset), .o_warm_reset(warm_reset),
        .o_configured(link_configured));

    Usb3Device #(.STREAM_FLUSH_US(20)) dev(.i_clk(clk), .i_rst(rst),
        .i_in_u0(in_u0), .i_hot_reset(hot_reset), .i_warm_reset(warm_reset),
        .i_rx_hp_valid(rx_hp_valid), .i_rx_hp_hdr(rx_hp_hdr),
        .i_dpp_start(dpp_start), .i_dpp_valid(dpp_valid), .i_dpp_data(dpp_data), .i_dpp_be(dpp_be), .i_dpp_end(dpp_end), .i_dpp_err(dpp_err),
        .o_tx_hp_valid(tx_hp_valid), .o_tx_hp_hdr(tx_hp_hdr), .o_tx_dpp(tx_dpp), .o_tx_dpp_len(tx_dpp_len), .o_tx_dpp_base(tx_dpp_base),
        .i_tx_hp_ready(tx_hp_ready), .i_dpp_rd(dpp_rd), .i_dpp_addr(dpp_addr), .o_dpp_data(dpp_rdata),
        .o_configured(dev_configured), .o_address(dev_address), .o_reset(dev_reset),
        .o_vendor_reg(vendor_reg), .i_vendor_status(vendor_status),
        .o_reg_wr(reg_wr), .o_reg_addr(reg_addr), .o_reg_wdata(reg_wdata), .i_reg_rdata(reg_rdata),
        .o_rx_valid(app_rx_valid), .o_rx_data(app_rx_data), .i_rx_ready(app_rx_ready),
        .i_tx_valid(app_tx_valid), .i_tx_data(app_tx_data), .o_tx_ready(app_tx_ready),
        .i_txw_valid(app_txw_valid), .i_txw_data(app_txw_data), .o_txw_ready(app_txw_ready));

    usb3_host_bfm host(.clk(clk), .rst(rst),
        .d_tx_data(tx_data), .d_tx_k(tx_k), .d_tx_elecidle(tx_elecidle), .d_tx_detectrx(tx_detectrx),
        .d_power_down(power_down), .d_rx_polarity(rx_polarity), .d_rx_termination(rx_termination),
        .d_rx_data(rx_data), .d_rx_k(rx_k), .d_rx_valid(rx_valid), .d_rx_status(rx_status), .d_rx_elecidle(rx_elecidle),
        .d_phy_status(phy_status), .d_power_present(power_present));

    // application side
    logic [7:0] app_rx_q[$];
    always @(posedge clk) if (app_rx_valid && app_rx_ready) app_rx_q.push_back(app_rx_data);
    task automatic app_send(logic [7:0] b[$]);
        for (int i = 0; i < b.size(); i++) begin
            app_tx_data = b[i]; app_tx_valid = 1;
            @(posedge clk); while (!app_tx_ready) @(posedge clk);
        end
        app_tx_valid = 0;
    endtask
    // the same through the 32-bit entry (length a multiple of 4)
    // the same through the 32-bit entry (length a multiple of 4): a clocked valid/ready driver fed
    // from a queue (a task stepping clock edges itself raced the DUT's flops)
    logic [31:0] txw_q[$];
    always @(posedge clk) begin
        if (app_txw_valid && app_txw_ready) void'(txw_q.pop_front());
        if (txw_q.size() > (app_txw_valid && app_txw_ready ? 0 : 0)) begin
            app_txw_valid <= 1; app_txw_data <= txw_q[0];
        end else begin
            app_txw_valid <= 0;
        end
    end
    task automatic app_send_words(logic [7:0] b[$]);
        for (int i = 0; i < b.size(); i += 4) txw_q.push_back({b[i + 3], b[i + 2], b[i + 1], b[i]});
        do @(posedge clk); while (txw_q.size() != 0);
    endtask
    // background helpers (Verilator's fork/join is not reliable with nested tasks)
    logic [7:0] app_q[$];
    int app_go = 0, app_delay = 0, app_done = 0;
    initial if (RUN) forever begin
        @(posedge clk);
        if (app_go) begin
            app_go = 0;
            repeat (app_delay) @(posedge clk);
            app_send(app_q);
            app_done = 1;
        end
    end
    int ready_after = 0;
    initial if (RUN) forever begin
        @(posedge clk);
        if (ready_after > 0) begin
            ready_after--;
            if (ready_after == 0) app_rx_ready = 1;
        end
    end

`ifdef USB3_DBG
    logic [4:0] st_q;
    always @(posedge clk) begin
        if (ltssm_state != st_q) $display("t=%0t LTSSM %0d -> %0d", $time, st_q, ltssm_state);
        st_q <= ltssm_state;
        if (rx_hp_valid) $display("t=%0t dev: HP %024x", $time, rx_hp_hdr);
        if (tx_hp_valid && tx_hp_ready) $display("t=%0t dev: send HP %024x dpp=%0d len=%0d base=%03x", $time, tx_hp_hdr, tx_dpp, tx_dpp_len, tx_dpp_base);
        if (dpp_rd) $display("t=%0t dev: dpp_rd addr %03x (rom_q %08x) -> next rdata", $time, dpp_addr, dev.rom_q);
        if (dut.u_framer.state >= 8) $display("t=%0t framer st=%0d data=%08x rdata=%08x", $time, dut.u_framer.state, dut.u_framer.o_data, dpp_rdata);
    end
`endif

    int errors = 0;
    task automatic fail(string m); $display("FAIL [%s] %s", stage, m); errors++; endtask
    task automatic wait_clk(int n); repeat (n) @(posedge clk); endtask

    logic [7:0] d[$], q[$];
    int res;
    initial if (RUN) begin
        wait_clk(5); @(negedge clk); rst = 0; wait_clk(5);
        stage = "linkup";
        host.link_up(64);
        begin int n = 0; while (!link_configured && n < 20000) begin @(posedge clk); n++; end end
        if (!link_configured) fail("link not configured");
        wait_clk(100);

        // ---------------------------------------------------------------- device descriptor
        stage = "get device";
        host.control_xfer(8'h80, 8'h06, 16'h0100, 0, 18, d, res);
        if (res != 0) fail($sformatf("result %0d", res));
        if (d.size() != 18) fail($sformatf("len %0d", d.size()));
        else begin
            $display("device descriptor: %p", d);
            if (d[0] != 18 || d[1] != 1 || {d[3], d[2]} != 16'h0310 || d[7] != 9) fail("device descriptor fields");
            if ({d[9], d[8]} != 16'h1209 || {d[11], d[10]} != 16'h0001) fail("vid/pid");
        end
        // short read
        host.control_xfer(8'h80, 8'h06, 16'h0100, 0, 8, d, res);
        if (res != 0 || d.size() != 8) fail("short device descriptor");

        // ---------------------------------------------------------------- address
        stage = "set address";
        host.control_xfer(8'h00, 8'h05, 16'd5, 0, 0, d, res);
        if (res != 0) fail("set address");
        wait_clk(10);
        if (dev_address != 5) fail($sformatf("address %0d", dev_address));
        host.dev_address = 5;

        // ---------------------------------------------------------------- configuration / BOS / strings
        stage = "get config";
        host.control_xfer(8'h80, 8'h06, 16'h0200, 0, 9, d, res);
        if (res != 0 || d.size() != 9 || {d[3], d[2]} != 44) fail("config header");
        host.control_xfer(8'h80, 8'h06, 16'h0200, 0, 255, d, res);
        if (res != 0 || d.size() != 44) fail($sformatf("config full %0d", d.size()));
        else begin
            if (d[9] != 9 || d[10] != 4) fail("interface");
            if (d[18] != 7 || d[19] != 5 || d[20] != 8'h01 || {d[23], d[22]} != 1024) fail("ep out");
            if (d[25] != 6 || d[26] != 8'h30) fail("ep companion");
            if (d[31] != 7 || d[33] != 8'h81) fail("ep in");
        end
        stage = "get bos";
        host.control_xfer(8'h80, 8'h06, 16'h0F00, 0, 5, d, res);
        if (res != 0 || d.size() != 5 || d[1] != 8'h0F || {d[3], d[2]} != 50) fail("bos header");
        host.control_xfer(8'h80, 8'h06, 16'h0F00, 0, 50, d, res);
        if (res != 0 || d.size() != 50) fail("bos full");
        else if (d[5] != 7 || d[7] != 2 || d[12] != 10 || d[14] != 3 || d[22] != 28 || d[24] != 5) fail("bos capabilities");
        stage = "get string";
        host.control_xfer(8'h80, 8'h06, 16'h0300, 0, 255, d, res);
        if (res != 0 || d.size() != 4 || {d[3], d[2]} != 16'h0409) fail("string 0");
        host.control_xfer(8'h80, 8'h06, 16'h0302, 16'h0409, 255, d, res);
        if (res != 0 || d.size() != 28 || d[2] != "U") fail("string 2");
        // unsupported descriptor -> STALL
        stage = "stall";
        host.control_xfer(8'h80, 8'h06, 16'h0600, 0, 10, d, res);
        if (res != 1) fail($sformatf("qualifier not stalled (%0d)", res));
        host.control_xfer(8'h80, 8'h06, 16'h0100, 0, 18, d, res);   // still works afterwards
        if (res != 0 || d.size() != 18) fail("after stall");

        // ---------------------------------------------------------------- configure
        stage = "set config";
        host.control_xfer(8'h00, 8'h09, 16'd1, 0, 0, d, res);
        if (res != 0) fail("set configuration");
        wait_clk(10);
        if (!dev_configured) fail("not configured");
        host.control_xfer(8'h80, 8'h08, 0, 0, 1, d, res);
        if (res != 0 || d.size() != 1 || d[0] != 1) fail("get configuration");
        host.control_xfer(8'h80, 8'h00, 0, 0, 2, d, res);
        if (res != 0 || d.size() != 2 || d[0] != 0) fail("get status");
        d.delete(); for (int i = 0; i < 6; i++) d.push_back(i);
        host.control_xfer(8'h00, 8'h30, 0, 0, 6, d, res);   // SET_SEL with 6 bytes OUT
        if (res != 0) fail("set sel");
        host.control_xfer(8'h00, 8'h31, 16'd40, 0, 0, d, res);
        if (res != 0) fail("set isoch delay");
        host.control_xfer(8'h00, 8'h03, 16'd48, 0, 0, d, res); // U1_ENABLE
        if (res != 0) fail("u1 enable");

        // ---------------------------------------------------------------- vendor requests
        stage = "vendor";
        host.control_xfer(8'h40, 8'h02, 16'hBEEF, 0, 0, d, res);
        if (res != 0 || vendor_reg != 16'hBEEF) fail("vendor out");
        host.control_xfer(8'hC0, 8'h01, 0, 0, 4, d, res);
        if (res != 0 || d.size() != 4 || {d[3], d[2], d[1], d[0]} != 32'hCAFE1234) fail("vendor in");
        // register port: write two registers, read them back
        host.control_xfer(8'h40, 8'h03, 16'h1234, 16'h0005, 0, d, res);
        if (res != 0) fail("reg write 5");
        host.control_xfer(8'h40, 8'h03, 16'hABCD, 16'h0011, 0, d, res);
        if (res != 0) fail("reg write 0x11");
        host.control_xfer(8'hC0, 8'h04, 0, 16'h0005, 4, d, res);
        if (res != 0 || d.size() != 4 || {d[3], d[2], d[1], d[0]} != 32'hFA001234) fail("reg read 5");
        host.control_xfer(8'hC0, 8'h04, 0, 16'h0011, 4, d, res);
        if (res != 0 || d.size() != 4 || {d[3], d[2], d[1], d[0]} != 32'hEE00ABCD) fail("reg read 0x11");
        host.control_xfer(8'hC0, 8'h20, 0, 7, 30, d, res);
        if (res != 0 || d.size() != 30 || d[0] != 10 || d[8] != 30) fail("ms os 2.0 set");

        // ---------------------------------------------------------------- bulk OUT
        stage = "bulk out";
        app_rx_q.delete();
        q.delete(); for (int i = 0; i < 1024; i++) q.push_back(i * 3 + 1);
        host.bulk_out(q, res);
        if (res != 0) fail($sformatf("bulk out res %0d", res));
        begin int n = 0; while (app_rx_q.size() < 1024 && n < 5000) begin @(posedge clk); n++; end end
        if (app_rx_q.size() != 1024) fail($sformatf("app got %0d bytes", app_rx_q.size()));
        else for (int i = 0; i < 1024; i++) if (app_rx_q[i] != q[i]) begin fail($sformatf("bulk out data at %0d: got %02x %02x %02x %02x exp %02x %02x %02x %02x", i, app_rx_q[i], app_rx_q[i+1], app_rx_q[i+2], app_rx_q[i+3], q[i], q[i+1], q[i+2], q[i+3])); break; end
        // flow control: app not ready -> second packet gets NRDY, then ERDY after draining
        app_rx_q.delete(); app_rx_ready = 0;
        q.delete(); for (int i = 0; i < 100; i++) q.push_back(i);
        host.bulk_out(q, res);
        if (res != 0) fail("bulk out #2");
        q.delete(); for (int i = 0; i < 50; i++) q.push_back(200 + i);
        ready_after = 2000;
        host.bulk_out(q, res);
        if (res != 0) fail($sformatf("bulk out #3 res %0d", res));
        begin int n = 0; while (app_rx_q.size() < 150 && n < 5000) begin @(posedge clk); n++; end end
        if (app_rx_q.size() != 150) fail($sformatf("app got %0d bytes (flow)", app_rx_q.size()));
        else if (app_rx_q[0] != 0 || app_rx_q[99] != 99 || app_rx_q[100] != 200 || app_rx_q[149] != 249) fail("flow data");

        // ---------------------------------------------------------------- bulk IN
        stage = "bulk in";
        // nothing queued: NRDY, then the app sends 37 bytes -> flushed after idle -> ERDY -> DP
        app_q.delete(); for (int i = 0; i < 37; i++) app_q.push_back(8'h40 + i);
        app_delay = 300; app_done = 0; app_go = 1;
        host.bulk_in(d, res);
        if (res != 0) fail($sformatf("bulk in res %0d", res));
        if (d.size() != 37) fail($sformatf("bulk in got %0d", d.size()));
        else for (int i = 0; i < 37; i++) if (d[i] != 8'h40 + i) begin fail("bulk in data"); break; end
        // 2 full packets + 10 bytes streamed while the host reads (two packet buffers)
        q.delete(); for (int i = 0; i < 2058; i++) q.push_back(i * 5 + 7);
        app_q = q; app_delay = 0; app_done = 0; app_go = 1;
        wait_clk(125 * 30);
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 1024) fail($sformatf("full packet 1: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 1024; i++) if (d[i] != q[i]) begin fail("full packet 1 data"); break; end
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 1024) fail($sformatf("full packet 2: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 1024; i++) if (d[i] != q[1024 + i]) begin fail("full packet 2 data"); break; end
        begin int n = 0; while (!app_done && n < 20000) begin @(posedge clk); n++; end end
        wait_clk(125 * 30);
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 10) fail($sformatf("tail packet: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 10; i++) if (d[i] != q[2048 + i]) begin fail("tail data"); break; end
        // exactly one full packet, then idle: a ZLP follows
        q.delete(); for (int i = 0; i < 1024; i++) q.push_back(i);
        app_send(q);
        wait_clk(125 * 30);
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 1024) fail("exact packet");
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 0) fail($sformatf("zlp: res %0d len %0d", res, d.size()));
        // 32-bit entry: two full packets and a 12-byte tail, 4 bytes per clock
        stage = "bulk in words";
        q.delete(); for (int i = 0; i < 2060; i++) q.push_back(8'(i * 11 + 5));
        begin logic [7:0] q2[$]; q2 = q[0:2047]; app_send_words(q2); end   // fills both packet buffers
        wait_clk(125 * 30);
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 1024) fail($sformatf("word packet 1: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 1024; i++) if (d[i] != q[i]) begin fail($sformatf("word packet 1 data at %0d", i)); break; end
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 1024) fail($sformatf("word packet 2: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 1024; i++) if (d[i] != q[1024 + i]) begin fail("word packet 2 data"); break; end
        // the stream went idle after full packets: a ZLP ends that transfer first
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 0) fail($sformatf("word zlp: res %0d len %0d", res, d.size()));
        begin logic [7:0] q3[$]; q3 = q[2048:2059]; app_send_words(q3); end
        wait_clk(125 * 30);
        host.bulk_in(d, res);
        if (res != 0 || d.size() != 12) fail($sformatf("word tail: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 12; i++) if (d[i] != q[2048 + i]) begin fail("word tail data"); break; end
        // bursts: 6 full packets and a 100-byte tail through the 32-bit entry (fits the 8 buffers),
        // read with NumP 4 (several packets per acknowledgement); the 3rd packet is answered with a
        // retry once, so the device resends it and the ones after it
        stage = "bulk in burst";
        q.delete(); for (int i = 0; i < 6244; i++) q.push_back(8'(i * 7 + 13));
        app_send_words(q);
        wait_clk(125 * 30);
        host.bulk_in_burst(4, 16, 2, d, res);
        if (res != 0 || d.size() != 6244) fail($sformatf("burst: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 6244; i++) if (d[i] != q[i]) begin fail($sformatf("burst data at %0d", i)); break; end
        if (host.burst_dropped == 0) fail("burst: no packets were in flight at the retry");
        // flow control within a burst: read with nothing queued (NRDY), the data arrives later (ERDY),
        // then the host's ACK - no data packet may go out before it
        stage = "bulk in burst flow";
        app_q.delete(); for (int i = 0; i < 200; i++) app_q.push_back(8'h80 + 8'(i));
        app_delay = 500; app_done = 0; app_go = 1;
        host.bulk_in_burst(4, 16, -1, d, res);
        if (res != 0 || d.size() != 200) fail($sformatf("burst flow: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 200; i++) if (d[i] != 8'h80 + 8'(i)) begin fail("burst flow data"); break; end
        if (host.proto_err != 0) fail($sformatf("host protocol errors %0d", host.proto_err));
        // a short packet inside the queued data ends the host's transfer: the device must not run
        // ahead into the next packets (the host drops them) - 2 full packets, a 100-byte short one,
        // then 3 more full ones, read with NumP 8 as two transfers
        stage = "bulk in burst short";
        q.delete(); for (int i = 0; i < 2148; i++) q.push_back(8'(i * 3 + 1));
        app_send_words(q);
        wait_clk(125 * 30);         // idle: the 100-byte tail closes as a short packet
        q2_short.delete(); for (int i = 0; i < 3072; i++) q2_short.push_back(8'(i * 5 + 2));
        app_send_words(q2_short);
        wait_clk(125 * 5);
        host.bulk_in_burst(8, 16, -1, d, res);
        if (res != 0 || d.size() != 2148) fail($sformatf("short 1: res %0d len %0d", res, d.size()));
        else for (int i = 0; i < 2148; i++) if (d[i] != q[i]) begin fail("short 1 data"); break; end
        host.bulk_in_burst(8, 3, -1, d, res);
        if (res != 0 || d.size() != 3072) fail($sformatf("short 2: res %0d len %0d (discarded %0d)", res, d.size(), host.burst_discarded));
        else for (int i = 0; i < 3072; i++) if (d[i] != q2_short[i]) begin fail("short 2 data"); break; end
        wait_clk(125 * 30);
        host.bulk_in(d, res);       // the ZLP after the idle full packets
        if (res != 0 || d.size() != 0) fail($sformatf("short zlp: res %0d len %0d", res, d.size()));
        if (host.proto_err != 0) fail($sformatf("host protocol errors %0d", host.proto_err));
        // all 16 buffers (bMaxBurst 15): 15 full packets and a 300-byte tail read with NumP 16, the
        // 10th packet answered with a retry; twice, so the 4-bit buffer indices wrap
        stage = "bulk in burst 16";
        for (int r = 0; r < 2; r++) begin
            q.delete(); for (int i = 0; i < 15660; i++) q.push_back(8'(i * 11 + r * 5 + 3));
            app_send_words(q);
            wait_clk(125 * 30);
            host.bulk_in_burst(16, 16, 9, d, res);
            if (res != 0 || d.size() != 15660) fail($sformatf("burst 16 #%0d: res %0d len %0d", r, res, d.size()));
            else for (int i = 0; i < 15660; i++) if (d[i] != q[i]) begin fail($sformatf("burst 16 #%0d data at %0d", r, i)); break; end
        end
        if (host.proto_err != 0) fail($sformatf("host protocol errors %0d", host.proto_err));
        // SeqNum wraps 31 -> 0: 34 more IN transfers (the device ignored the ACK with SeqNum 0
        // after 31 - a widened "seq + 1" compare - and the host timed out on the 33rd packet)
        stage = "seq wrap";
        for (int r = 0; r < 34; r++) begin
            q.delete(); for (int i = 0; i < 4; i++) q.push_back(8'(r * 4 + i));
            app_send(q);
            wait_clk(125 * 30);
            host.bulk_in(d, res);
            if (res != 0 || d.size() != 4 || d[0] != q[0] || d[3] != q[3]) begin
                fail($sformatf("wrap round %0d: res %0d len %0d", r, res, d.size())); break;
            end
        end
        if (host.proto_err != 0) fail($sformatf("host protocol errors %0d", host.proto_err));
        if (host.lgood_err || host.lcrd_err || host.hsn_err) fail("link ack errors");

        if (errors == 0) begin $display("PASS usb3_device"); $finish; end
        else $fatal(1, "FAIL usb3_device: %0d errors", errors);
        $finish;
    end
endmodule
