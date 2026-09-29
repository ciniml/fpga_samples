// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Shared device-level test body (see tb_usb_device.veryl).
//   HS   = 0: FS enumeration through UsbPhy;  1: reset + chirp handshake, HS enumeration.
//   ULPI = 1: UsbDevice -> UlpiLink -> UlpiPhy instead of UsbPhy.
`timescale 1ns/1ps
//   STREAM = 1: EP1_STREAM device (byte-stream ports) - the loopback stages are replaced by stream stages.
module usb_device_test_body #(parameter HS = 0, parameter ULPI = 0, parameter RUN = 0, parameter STALL = 0, parameter STREAM = 0);  // STALL > 0: RxValid dropped 1 clock in STALL (HS CDR word stalls)
    logic clk = 0;
    logic rst = 1;
    always #8.333 clk = ~clk;

    logic [7:0] utmi_data_out, utmi_data_in;
    logic utmi_txvalid, utmi_txready, utmi_rxactive, utmi_rxvalid, utmi_rxerror;
    logic [1:0] utmi_linestate, utmi_opmode, utmi_xcvr;
    logic utmi_termsel;
    logic [7:0] rx_dp, rx_dn, tx_dp, tx_dn;
    logic tx_oe;
    logic pu_dp, pu_dn, term_dp, term_dn;

    logic high_speed, configured, suspended, dev_reset, sof;
    logic [6:0] address;
    logic [10:0] frame;
    logic [15:0] vendor_reg;

    // EP1 stream side (STREAM = 1): the test feeds i_tx and collects o_rx
    logic s_tx_v = 0; logic [7:0] s_tx_d = 0; logic s_tx_rdy; logic s_rx_v; logic [7:0] s_rx_d; logic s_rx_rdy = 1;
    byte s_rx_q[$];
    always @(posedge clk) if (s_rx_v && s_rx_rdy) s_rx_q.push_back(s_rx_d);
    // (the idle time must exceed one bulk transaction: 512 B at HS ~ 9 us, 64 B at FS ~ 50 us)
    localparam int FLUSH_US = HS ? 20 : 200;
    UsbDevice #(.HS_CAPABLE(1), .EP1_STREAM(STREAM), .STREAM_FLUSH_US(FLUSH_US)) dev (
        .i_clk(clk), .i_rst(rst),
        .o_utmi_data_out(utmi_data_out), .o_utmi_txvalid(utmi_txvalid), .i_utmi_txready(utmi_txready),
        .i_utmi_data_in(utmi_data_in), .i_utmi_rxactive(utmi_rxactive), .i_utmi_rxvalid(utmi_rxvalid),
        .i_utmi_rxerror(utmi_rxerror), .i_utmi_linestate(utmi_linestate),
        .o_utmi_opmode(utmi_opmode), .o_utmi_xcvrselect(utmi_xcvr), .o_utmi_termselect(utmi_termsel),
        .o_high_speed(high_speed), .o_configured(configured), .o_suspended(suspended), .o_reset(dev_reset),
        .o_address(address), .o_frame(frame), .o_sof(sof),
        .o_vendor_reg(vendor_reg), .i_vendor_status(32'hCAFE1234),
        .o_rx_valid(s_rx_v), .o_rx_data(s_rx_d), .i_rx_ready(s_rx_rdy),
        .i_tx_valid(s_tx_v), .i_tx_data(s_tx_d), .o_tx_ready(s_tx_rdy)
    );

    generate if (ULPI == 0) begin : g_utmi
        // STALL > 0: the receive words pass through an elastic queue that
        // withholds a word 1 clock in STALL (as the HS CDR / gearbox does);
        // nothing is lost, the stream is just delivered later
        logic dd_valid = 1; logic [7:0] q_dp, q_dn, q_dd; logic [23:0] q[$];
        always @(posedge clk) begin
            if (STALL == 0) begin q_dp <= rx_dp; q_dn <= rx_dn; q_dd <= rx_dp; dd_valid <= 1'b1; end
            else begin
                q.push_back({rx_dp, rx_dn, rx_dp});
                if ($urandom_range(STALL - 1) != 0 && q.size() > 0) begin
                    logic [23:0] w; w = q.pop_front();
                    q_dp <= w[23:16]; q_dn <= w[15:8]; q_dd <= w[7:0]; dd_valid <= 1'b1;
                end else dd_valid <= 1'b0;
            end
        end
        UsbPhy phy (
            .i_clk(clk), .i_rst(rst),
            .i_utmi_data_out(utmi_data_out), .i_utmi_txvalid(utmi_txvalid), .o_utmi_txready(utmi_txready),
            .o_utmi_data_in(utmi_data_in), .o_utmi_rxactive(utmi_rxactive), .o_utmi_rxvalid(utmi_rxvalid),
            .o_utmi_rxerror(utmi_rxerror), .o_utmi_linestate(utmi_linestate),
            .i_utmi_opmode(utmi_opmode), .i_utmi_xcvrselect(utmi_xcvr), .i_utmi_termselect(utmi_termsel),
            .i_rx_dp(q_dp), .i_rx_dn(q_dn), .i_rx_dd(q_dd), .i_rx_dd_valid(dd_valid), .o_tx_dp(tx_dp), .o_tx_dn(tx_dn), .o_tx_oe(tx_oe),
            .o_pullup_dp_en(pu_dp), .o_pullup_dn_en(pu_dn), .o_term_dp_en(term_dp), .o_term_dn_en(term_dn)
        );
    end else begin : g_ulpi
        logic [7:0] ulpi_l2p, ulpi_p2l, ulpi_bus;
        logic ulpi_dir, ulpi_nxt, ulpi_stp, ulpi_l_oe;
        assign ulpi_bus = ulpi_dir ? ulpi_p2l : (ulpi_l_oe ? ulpi_l2p : 8'hzz);
        UlpiLink link (
            .i_clk(clk), .i_rst(rst),
            .i_utmi_data_out(utmi_data_out), .i_utmi_txvalid(utmi_txvalid), .o_utmi_txready(utmi_txready),
            .o_utmi_data_in(utmi_data_in), .o_utmi_rxactive(utmi_rxactive), .o_utmi_rxvalid(utmi_rxvalid),
            .o_utmi_rxerror(utmi_rxerror), .o_utmi_linestate(utmi_linestate),
            .i_utmi_opmode(utmi_opmode), .i_utmi_xcvrselect(utmi_xcvr), .i_utmi_termselect(utmi_termsel),
            .i_ulpi_data(ulpi_bus), .o_ulpi_data(ulpi_l2p), .o_ulpi_data_oe(ulpi_l_oe),
            .i_ulpi_dir(ulpi_dir), .i_ulpi_nxt(ulpi_nxt), .o_ulpi_stp(ulpi_stp)
        );
        UlpiPhy phy (
            .i_clk(clk), .i_rst(rst),
            .i_ulpi_data(ulpi_bus), .o_ulpi_data(ulpi_p2l), .o_ulpi_dir(ulpi_dir), .o_ulpi_nxt(ulpi_nxt), .i_ulpi_stp(ulpi_stp),
            .i_vbus_valid(1'b1),
            .i_rx_dp(rx_dp), .i_rx_dn(rx_dn), .i_rx_dd(rx_dp), .o_tx_dp(tx_dp), .o_tx_dn(tx_dn), .o_tx_oe(tx_oe),
            .o_pullup_dp_en(pu_dp), .o_pullup_dn_en(pu_dn), .o_term_dp_en(term_dp), .o_term_dn_en(term_dn),
            .o_dp_pulldown(), .o_dm_pulldown()
        );
    end endgenerate

    logic host_hs = 0;
    logic host_drive;
    usb_host_bfm host (
        .clk(clk), .hs(host_hs), .ls(1'b0),
        .dp_o(rx_dp), .dn_o(rx_dn), .drive(host_drive),
        .dp_i(tx_dp), .dn_i(tx_dn), .oe_i(tx_oe)
    );

    int errors = 0;
    string stage = "init";
    initial if (RUN) begin repeat (6_000_000) @(posedge clk); $fatal(1, "TIMEOUT at stage %s", stage); end

    localparam int US = 60;

    task automatic fail(input string msg);
        $display("ERROR: [%s] %s", stage, msg); errors++;
    endtask

    // ------------------------------------------------------------------
    // Control transfer helpers (address `addr`)
    // ------------------------------------------------------------------
    logic [6:0] addr = 0;
    byte ctrl_buf[0:1023];
    int  ctrl_len;

    task automatic setup_stage(input logic [7:0] bmrt, input logic [7:0] breq, input logic [15:0] wval,
                               input logic [15:0] widx, input logic [15:0] wlen);
        host.tx_buf[1] = bmrt; host.tx_buf[2] = breq;
        host.tx_buf[3] = wval[7:0]; host.tx_buf[4] = wval[15:8];
        host.tx_buf[5] = widx[7:0]; host.tx_buf[6] = widx[15:8];
        host.tx_buf[7] = wlen[7:0]; host.tx_buf[8] = wlen[15:8];
        host.out_transaction(4'b1101, addr, 0, 4'b0011, 8);
        if (host.rx_pid != 4'b0010) fail($sformatf("SETUP %02x/%02x not ACKed (pid %h)", bmrt, breq, host.rx_pid));
    endtask

    // IN data stage until short packet / wlen reached; then OUT status ZLP.
    // Returns 1 when the device STALLed.
    task automatic control_in(input logic [7:0] bmrt, input logic [7:0] breq, input logic [15:0] wval,
                              input logic [15:0] widx, input logic [15:0] wlen, output bit stalled);
        bit toggle; bit done; int guard;
        stalled = 0; ctrl_len = 0; toggle = 1; done = 0; guard = 0;
        setup_stage(bmrt, breq, wval, widx, wlen);
        while (!done && guard < 200) begin
            guard++;
            host.in_transaction(addr, 0, 1);
            if (host.rx_pid == 4'b1110) begin stalled = 1; done = 1; end
            else if (host.rx_pid == 4'b1010) begin repeat (50) @(posedge clk); end // NAK: retry
            else if (host.rx_pid == 4'b0011 || host.rx_pid == 4'b1011) begin
                if (host.rx_pid[3] != toggle) fail("EP0 IN data toggle mismatch");
                toggle = ~toggle;
                for (int i = 0; i < host.rx_len; i++) ctrl_buf[ctrl_len + i] = host.rx_buf[i];
                ctrl_len += host.rx_len;
                if (host.rx_len < 64 || ctrl_len >= wlen) done = 1;
            end else begin fail($sformatf("EP0 IN: unexpected pid %h", host.rx_pid)); done = 1; end
        end
        if (!stalled) begin
            // status stage: OUT ZLP DATA1
            host.out_transaction(4'b0001, addr, 0, 4'b1011, 0);
            if (host.rx_pid != 4'b0010) fail($sformatf("status OUT not ACKed (pid %h)", host.rx_pid));
        end
    endtask

    // No-data control request: SETUP then IN status ZLP.
    task automatic control_nodata(input logic [7:0] bmrt, input logic [7:0] breq, input logic [15:0] wval,
                                  input logic [15:0] widx, output bit stalled);
        int guard; bit done;
        stalled = 0; guard = 0; done = 0;
        setup_stage(bmrt, breq, wval, widx, 0);
        while (!done && guard < 100) begin
            guard++;
            host.in_transaction(addr, 0, 1);
            if (host.rx_pid == 4'b1110) begin stalled = 1; done = 1; end
            else if (host.rx_pid == 4'b1010) begin repeat (50) @(posedge clk); end
            else if (host.rx_pid == 4'b1011) begin
                if (host.rx_len != 0) fail("status IN not a ZLP");
                done = 1;
            end else begin fail($sformatf("status IN: unexpected pid %h", host.rx_pid)); done = 1; end
        end
    endtask

    task automatic expect_bytes(input string what, input int n, input byte exp[0:255]);
        if (ctrl_len != n) fail($sformatf("%s: length %0d, expected %0d", what, ctrl_len, n));
        else for (int i = 0; i < n; i++)
            if (ctrl_buf[i] != exp[i]) fail($sformatf("%s: byte %0d = %02x, expected %02x", what, i, ctrl_buf[i], exp[i]));
    endtask

    // ------------------------------------------------------------------
    // Bulk helpers
    // ------------------------------------------------------------------
    bit bulk_toggle_out = 0;
    bit bulk_toggle_in  = 0;
    int mps;

    task automatic bulk_out(input int n, input int seed, output logic [3:0] resp);
        for (int i = 0; i < n; i++) host.tx_buf[1 + i] = byte'(seed + i * 3);
        host.out_transaction(4'b0001, addr, 1, bulk_toggle_out ? 4'b1011 : 4'b0011, n);
        resp = host.rx_pid;
        if (resp == 4'b0010) bulk_toggle_out = ~bulk_toggle_out;
    endtask

    task automatic bulk_in(output logic [3:0] resp);
        host.in_transaction(addr, 1, 1);
        resp = host.rx_pid;
        if (resp == 4'b0011 || resp == 4'b1011) begin
            if (resp[3] != bulk_toggle_in) fail("EP1 IN data toggle mismatch");
            bulk_toggle_in = ~bulk_toggle_in;
        end
    endtask

    // stream feed: one byte per clock while the device is ready (values seed + i)
    task automatic feed(input int n, input int seed);
        for (int i = 0; i < n; i++) begin
            s_tx_d = byte'(seed + i); s_tx_v = 1;
            while (!s_tx_rdy) @(posedge clk);
            @(posedge clk);
        end
        s_tx_v = 0;
    endtask
    localparam int FLUSH_CLKS = FLUSH_US * 60 + 100;   // STREAM_FLUSH_US + margin

    // ------------------------------------------------------------------
    // Reset / chirp
    // ------------------------------------------------------------------
    task automatic bus_reset();
        int t;
        stage = "reset";
        host_hs = 0;
        bulk_toggle_out = 0; bulk_toggle_in = 0; addr = 0;
        if (!HS) begin
            // FS host: plain SE0 for 10 ms; the device chirps into it
            // (ignored) and must come back as FS.
            host.drive_raw(0, 1, 10000 * US);
            repeat (100) @(posedge clk);
            if (high_speed) fail("device went HS on an FS host");
            if (!pu_dp) fail("FS pull-up not enabled after reset");
        end else begin
            fork
                host.drive_raw(0, 1, 4000 * US); // SE0 background (Chirp K rides on it)
                begin
                    // wait for the device chirp K (D- high)
                    t = 0;
                    while (!(tx_oe && tx_dn[0] && !tx_dp[0]) && t < 1000 * US) begin @(posedge clk); t++; end
                    if (t >= 1000 * US) fail("no device Chirp K");
                    t = 0;
                    while (tx_oe && t < 8000 * US) begin @(posedge clk); t++; end
                    if (t >= 8000 * US) fail("Chirp K never ended");
                    if (t < 1000 * US) fail($sformatf("Chirp K too short: %0d us", t / US));
                    // hub chirp: K J K J K J (50 us each), then SE0 (HS idle)
                    repeat (20 * US) @(posedge clk);
                    for (int i = 0; i < 6; i++) begin
                        host.tx_drive = 1;
                        host.tx_dp = (i % 2 == 0) ? 8'h00 : 8'hFF;
                        host.tx_dn = (i % 2 == 0) ? 8'hFF : 8'h00;
                        repeat (50 * US) @(posedge clk);
                    end
                    host.tx_dp = 0; host.tx_dn = 0; // SE0
                    repeat (300 * US) @(posedge clk);
                end
            join
            host_hs = 1;
            repeat (100) @(posedge clk);
            if (!high_speed) fail("device did not enter HS");
            if (pu_dp || !term_dp) fail("HS terminations not enabled");
        end
        stage = "post-reset";
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    byte exp[0:255];
    bit stalled;
    logic [3:0] resp;
    // RUN = 0 keeps an uninstantiated copy (a Verilator implicit top) inert.
    initial if (RUN) begin
        repeat (5) @(posedge clk);
        rst = 0;
        repeat (100) @(posedge clk);
        mps = HS ? 512 : 64;

        bus_reset();

        // ---- GET_DESCRIPTOR(device) with wLength 64 (first 8 bytes usually, here full)
        stage = "get device descriptor";
        control_in(8'h80, 8'h06, 16'h0100, 0, 64, stalled);
        if (stalled) fail("device descriptor STALLed");
        exp[0]=8'h12; exp[1]=8'h01; exp[2]=8'h10; exp[3]=8'h02; exp[4]=8'hFF; exp[5]=8'h00; exp[6]=8'h00; exp[7]=8'h40;
        exp[8]=8'h09; exp[9]=8'h12; exp[10]=8'h01; exp[11]=8'h00; exp[12]=8'h00; exp[13]=8'h01; exp[14]=8'h01; exp[15]=8'h02; exp[16]=8'h03; exp[17]=8'h01;
        expect_bytes("device descriptor", 18, exp);

        // ---- SET_ADDRESS 5
        stage = "set address";
        control_nodata(8'h00, 8'h05, 16'd5, 0, stalled);
        if (stalled) fail("SET_ADDRESS STALLed");
        repeat (20) @(posedge clk);
        if (address != 5) fail($sformatf("address = %0d", address));
        addr = 5;

        // ---- device descriptor again at the new address, wLength = 18
        stage = "device descriptor @5";
        control_in(8'h80, 8'h06, 16'h0100, 0, 18, stalled);
        expect_bytes("device descriptor @5", 18, exp);

        // ---- configuration descriptor: 9 bytes then full
        stage = "config descriptor";
        control_in(8'h80, 8'h06, 16'h0200, 0, 9, stalled);
        exp[0]=8'h09; exp[1]=8'h02; exp[2]=8'h20; exp[3]=8'h00; exp[4]=8'h01; exp[5]=8'h01; exp[6]=8'h00; exp[7]=8'h80; exp[8]=8'h32;
        expect_bytes("config header", 9, exp);
        control_in(8'h80, 8'h06, 16'h0200, 0, 255, stalled);
        if (ctrl_len != 32) fail($sformatf("full config length %0d", ctrl_len));
        // config(9) + interface(9) = 18: EP OUT @18, EP IN @25
        if (ctrl_buf[20] != 8'h01 || ctrl_buf[21] != 8'h02) fail("EP1 OUT descriptor");
        if ({ctrl_buf[23], ctrl_buf[22]} != mps) fail($sformatf("EP1 OUT wMaxPacketSize %0d", {ctrl_buf[23], ctrl_buf[22]}));
        if (ctrl_buf[27] != 8'h81) fail("EP1 IN descriptor");
        if ({ctrl_buf[30], ctrl_buf[29]} != mps) fail("EP1 IN wMaxPacketSize");

        // ---- other-speed configuration: type 7 and the other packet size
        stage = "other speed config";
        control_in(8'h80, 8'h06, 16'h0700, 0, 255, stalled);
        if (stalled) fail("other_speed_configuration STALLed");
        if (ctrl_len != 32 || ctrl_buf[1] != 8'h07) fail("other_speed type patch");
        if ({ctrl_buf[23], ctrl_buf[22]} != (HS ? 64 : 512)) fail("other_speed packet size");

        // ---- device qualifier
        stage = "device qualifier";
        control_in(8'h80, 8'h06, 16'h0600, 0, 10, stalled);
        if (stalled || ctrl_len != 10 || ctrl_buf[1] != 8'h06) fail("device qualifier");

        // ---- strings: langid and product ("USB PHY Sample")
        stage = "strings";
        control_in(8'h80, 8'h06, 16'h0300, 0, 255, stalled);
        exp[0]=8'h04; exp[1]=8'h03; exp[2]=8'h09; exp[3]=8'h04;
        expect_bytes("string 0", 4, exp);
        control_in(8'h80, 8'h06, 16'h0302, 16'h0409, 255, stalled);
        if (ctrl_len != 30 || ctrl_buf[2] != "U" || ctrl_buf[4] != "S" || ctrl_buf[6] != "B") fail("product string");
        // unknown string index -> STALL
        control_in(8'h80, 8'h06, 16'h0309, 16'h0409, 255, stalled);
        if (!stalled) fail("string 9 should STALL");

        // ---- BOS + Microsoft OS 2.0 descriptor set (WinUSB binding on Windows)
        stage = "bos";
        control_in(8'h80, 8'h06, 16'h0F00, 0, 255, stalled);
        if (stalled || ctrl_len != 33 || ctrl_buf[0] != 5 || ctrl_buf[1] != 8'h0F || ctrl_buf[2] != 33 || ctrl_buf[4] != 1) fail("BOS descriptor");
        if (ctrl_buf[5] != 8'h1C || ctrl_buf[6] != 8'h10 || ctrl_buf[7] != 8'h05 || ctrl_buf[9] != 8'hDF || ctrl_buf[31] != 8'h20) fail("MS OS 2.0 platform capability");
        control_in(8'hC0, 8'h20, 0, 16'd7, ctrl_buf[29] | (ctrl_buf[30] << 8), stalled);
        if (stalled || ctrl_len != 30 || ctrl_buf[0] != 10 || ctrl_buf[8] != 30 || ctrl_buf[10] != 20 || ctrl_buf[12] != 3) fail("MS OS 2.0 descriptor set");
        if (ctrl_buf[14] != "W" || ctrl_buf[15] != "I" || ctrl_buf[19] != "B") fail("Compatible ID WINUSB");
        control_in(8'hC0, 8'h20, 0, 16'd8, 30, stalled);   // other wIndex -> STALL
        if (!stalled) fail("MS vendor code with wIndex 8 should STALL");
        control_in(8'h80, 8'h06, 16'h0100, 0, 18, stalled);
        if (stalled || ctrl_buf[2] != 8'h10 || ctrl_buf[3] != 8'h02) fail("bcdUSB 2.10");

        // ---- GET_CONFIGURATION before configure = 0
        stage = "get configuration";
        control_in(8'h80, 8'h08, 0, 0, 1, stalled);
        if (stalled || ctrl_len != 1 || ctrl_buf[0] != 0) fail("GET_CONFIGURATION (unconfigured)");

        // ---- bulk before configuration -> STALL
        stage = "bulk unconfigured";
        bulk_in(resp);
        if (resp != 4'b1110) fail($sformatf("EP1 IN unconfigured: pid %h", resp));

        // ---- SET_CONFIGURATION 1
        stage = "set configuration";
        control_nodata(8'h00, 8'h09, 16'd1, 0, stalled);
        if (stalled) fail("SET_CONFIGURATION STALLed");
        repeat (10) @(posedge clk);
        if (!configured) fail("not configured");
        control_in(8'h80, 8'h08, 0, 0, 1, stalled);
        if (stalled || ctrl_len != 1 || ctrl_buf[0] != 1) fail("GET_CONFIGURATION (configured)");

        // ---- GET_STATUS device / endpoint
        stage = "get status";
        control_in(8'h80, 8'h00, 0, 0, 2, stalled);
        if (stalled || ctrl_len != 2 || ctrl_buf[0] != 0 || ctrl_buf[1] != 0) fail("GET_STATUS device");
        control_in(8'h82, 8'h00, 0, 16'h0081, 2, stalled);
        if (stalled || ctrl_len != 2 || ctrl_buf[0] != 0) fail("GET_STATUS EP1 IN");

        // ---- vendor requests
        stage = "vendor";
        control_in(8'hC0, 8'h01, 0, 0, 4, stalled);
        exp[0]=8'h34; exp[1]=8'h12; exp[2]=8'hFE; exp[3]=8'hCA;
        expect_bytes("vendor status", 4, exp);
        control_nodata(8'h40, 8'h02, 16'hBEEF, 0, stalled);
        if (stalled || vendor_reg != 16'hBEEF) fail($sformatf("vendor reg = %04x", vendor_reg));
        // unsupported standard request -> STALL
        control_in(8'h80, 8'h07, 0, 0, 2, stalled);
        if (!stalled) fail("SET_DESCRIPTOR should STALL");

        if (STREAM) begin
        // ---- stream OUT: bytes appear on o_rx
        stage = "stream out";
        bulk_out(20, 8'h10, resp);
        if (resp != 4'b0010) fail($sformatf("EP1 OUT: pid %h", resp));
        repeat (60) @(posedge clk);
        if (s_rx_q.size() != 20) fail($sformatf("o_rx got %0d bytes, expected 20", s_rx_q.size()));
        else for (int i = 0; i < 20; i++) if (s_rx_q[i] != byte'(8'h10 + i * 3)) begin fail("o_rx data"); break; end
        s_rx_q.delete();
        // OUT while the consumer stalls: the FIFO holds it, delivered when ready
        s_rx_rdy = 0;
        bulk_out(mps, 8'h30, resp);
        bulk_out(5, 8'h70, resp);
        repeat (20) @(posedge clk);
        if (s_rx_q.size() != 0) fail("o_rx delivered while not ready");
        s_rx_rdy = 1;
        repeat (mps + 40) @(posedge clk);
        if (s_rx_q.size() != mps + 5) fail($sformatf("o_rx got %0d bytes, expected %0d", s_rx_q.size(), mps + 5));
        else begin
            for (int i = 0; i < mps; i++) if (s_rx_q[i] != byte'(8'h30 + i * 3)) begin fail("o_rx data (stalled, 1st)"); break; end
            for (int i = 0; i < 5; i++) if (s_rx_q[mps + i] != byte'(8'h70 + i * 3)) begin fail("o_rx data (stalled, 2nd)"); break; end
        end
        s_rx_q.delete();

        // ---- stream IN: empty -> NAK; full packets right away, the remainder only after the idle time
        stage = "stream in";
        bulk_in(resp);
        if (resp != 4'b1010) fail($sformatf("EP1 IN empty: pid %h", resp));
        feed(mps + 10, 8'h20);
        bulk_in(resp);
        if (host.rx_len != mps) fail($sformatf("IN full packet len %0d", host.rx_len));
        else for (int i = 0; i < mps; i++) if (host.rx_buf[i] != byte'(8'h20 + i)) begin fail("IN full packet data"); break; end
        bulk_in(resp);
        if (resp != 4'b1010) fail("remainder sent before the idle time");
        repeat (FLUSH_CLKS) @(posedge clk);
        bulk_in(resp);
        if (host.rx_len != 10) fail($sformatf("IN remainder len %0d", host.rx_len));
        else for (int i = 0; i < 10; i++) if (host.rx_buf[i] != byte'(8'h20 + mps + i)) begin fail("IN remainder data"); break; end
        bulk_in(resp);
        if (resp != 4'b1010) fail("NAK expected after a short packet (no ZLP)");

        // ---- message of exactly one full packet: ZLP after the idle time
        stage = "stream zlp";
        feed(mps, 8'h40);
        bulk_in(resp);
        if (host.rx_len != mps) fail("IN full packet (zlp stage)");
        bulk_in(resp);
        if (resp != 4'b1010) fail("ZLP sent before the idle time");
        repeat (FLUSH_CLKS) @(posedge clk);
        bulk_in(resp);
        if (!(resp == 4'b0011 || resp == 4'b1011) || host.rx_len != 0) fail($sformatf("ZLP expected: pid %h len %0d", resp, host.rx_len));
        bulk_in(resp);
        if (resp != 4'b1010) fail("NAK expected after the ZLP");

        // ---- IN without ACK: same packet again
        stage = "stream retransmit";
        feed(5, 8'h50);
        repeat (FLUSH_CLKS) @(posedge clk);
        host.in_transaction(addr, 1, 0);
        if (host.rx_pid[3] != bulk_toggle_in) fail("retransmit toggle");
        bulk_in(resp);
        if (host.rx_len != 5 || host.rx_buf[0] != 8'h50) fail("retransmitted packet");

        // ---- back-pressure: o_tx_ready drops one packet short of the FIFO, everything drains in order
        stage = "stream backpressure";
        begin
            int room = 4096 - mps;       // BULK_FIFO_DEPTH - guard band
            int got = 0; int k = 0;
            feed(room, 8'h60);
            @(posedge clk);
            if (s_tx_rdy) fail("o_tx_ready still high with the FIFO full");
            while (got < room) begin
                if (got + mps > room) repeat (FLUSH_CLKS) @(posedge clk);
                bulk_in(resp);
                if (resp == 4'b1010) begin fail($sformatf("NAK while draining at %0d", got)); break; end
                for (int i = 0; i < host.rx_len; i++) if (host.rx_buf[i] != byte'(8'h60 + got + i)) begin fail($sformatf("drain data at %0d", got + i)); break; end
                got += host.rx_len; k++;
                if (k > 100) begin fail("drain did not finish"); break; end
            end
            if (!s_tx_rdy) fail("o_tx_ready low after draining");
            if (room % mps == 0) begin          // ended on a full packet: a ZLP closes the message
                repeat (FLUSH_CLKS) @(posedge clk);
                bulk_in(resp);
                if (!(resp == 4'b0011 || resp == 4'b1011) || host.rx_len != 0) fail("ZLP expected after the drain");
            end
            bulk_in(resp);
            if (resp != 4'b1010) fail("FIFO not empty after drain");
        end
        end else begin
        // ---- bulk loopback: empty -> NAK, then data
        stage = "bulk loopback";
        bulk_in(resp);
        if (resp != 4'b1010) fail($sformatf("EP1 IN empty: pid %h", resp));
        if (HS) begin
            host.send_token(4'b0100, addr, 1);  // PING
            host.expect_handshake(4'b0010, "PING with space");
        end
        bulk_out(mps, 8'h10, resp);
        if (resp != 4'b0010) fail($sformatf("EP1 OUT #1: pid %h", resp));
        bulk_out(7, 8'h80, resp);
        if (resp != 4'b0010) fail($sformatf("EP1 OUT #2: pid %h", resp));
        // retransmission with the old toggle must be ACKed but dropped
        bulk_toggle_out = ~bulk_toggle_out;   // resend #2 with its original (stale) toggle
        bulk_out(7, 8'h80, resp);              // ACK flips it back to the live state
        if (resp != 4'b0010) fail("EP1 OUT retransmission not ACKed");
        bulk_in(resp);
        if (host.rx_len != mps) fail($sformatf("EP1 IN #1 len %0d", host.rx_len));
        for (int i = 0; i < mps; i++) if (host.rx_buf[i] != byte'(8'h10 + i * 3)) begin fail("EP1 IN #1 data"); break; end
        bulk_in(resp);
        if (host.rx_len != 7) fail($sformatf("EP1 IN #2 len %0d", host.rx_len));
        for (int i = 0; i < 7; i++) if (host.rx_buf[i] != byte'(8'h80 + i * 3)) begin fail("EP1 IN #2 data"); break; end
        bulk_in(resp);
        if (resp != 4'b1010) fail("EP1 IN should be empty (NAK)");

        // ---- IN without ACK must be retransmitted with the same toggle
        stage = "bulk retransmit";
        bulk_out(5, 8'h40, resp);
        host.in_transaction(addr, 1, 0);      // no ACK
        if (host.rx_pid[3] != bulk_toggle_in) fail("retransmit toggle (1st)");
        bulk_in(resp);                          // same packet again
        if (host.rx_len != 5 || host.rx_buf[0] != 8'h40) fail("retransmitted packet");

        // ---- fill the FIFO: NAK when a full packet no longer fits
        stage = "bulk fifo full";
        begin
            int acked = 0; int k = 0;
            while (k < 64) begin
                bulk_out(mps, k, resp);
                if (resp == 4'b1010) break;
                if (resp != 4'b0010) begin fail("EP1 OUT while filling"); break; end
                acked++; k++;
            end
            if (resp != 4'b1010) fail("FIFO never reported full (NAK)");
            if (HS) begin
                host.send_token(4'b0100, addr, 1);
                host.expect_handshake(4'b1010, "PING when full");
            end
            for (int i = 0; i < acked; i++) begin
                bulk_in(resp);
                if (host.rx_len != mps) begin fail($sformatf("drain #%0d len %0d", i, host.rx_len)); break; end
                if (host.rx_buf[1] != byte'(i + 3)) begin fail($sformatf("drain #%0d data", i)); break; end
            end
            bulk_in(resp);
            if (resp != 4'b1010) fail("FIFO not empty after drain");
        end

        // ---- endpoint halt
        stage = "endpoint halt";
        control_nodata(8'h02, 8'h03, 0, 16'h0081, stalled); // SET_FEATURE(ENDPOINT_HALT, EP1 IN)
        if (stalled) fail("SET_FEATURE STALLed");
        bulk_in(resp);
        if (resp != 4'b1110) fail("halted EP1 IN did not STALL");
        control_in(8'h82, 8'h00, 0, 16'h0081, 2, stalled);
        if (ctrl_buf[0] != 1) fail("GET_STATUS halted EP");
        control_nodata(8'h02, 8'h01, 0, 16'h0081, stalled); // CLEAR_FEATURE
        bulk_toggle_in = 0;
        bulk_out(3, 8'h55, resp);
        bulk_in(resp);
        if (host.rx_len != 3 || resp != 4'b0011) fail("EP1 IN after CLEAR_FEATURE (DATA0 expected)");
        end

        // ---- SOF
        stage = "sof";
        host.send_sof(11'h123);
        // (with STALL the elastic queue's backlog grows over the run, so allow the delivery delay)
        for (int w = 0; w < 4000 && frame != 11'h123; w++) @(posedge clk);
        if (frame != 11'h123) fail($sformatf("frame %h", frame));

        // ---- wrong address is ignored
        stage = "wrong address";
        host.send_token(4'b1001, 7'd9, 0);
        host.recv_packet(500);
        if (!host.rx_timeout) fail("device answered a foreign address");

        errors += host.errors;
        if (errors == 0) $display("PASS: usb_device HS=%0d ULPI=%0d STREAM=%0d", HS, ULPI, STREAM);
        else $fatal(1, "FAIL: usb_device HS=%0d ULPI=%0d errors=%0d", HS, ULPI, errors);
        $finish;
    end
endmodule
