// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Test of Usb3PhyCtl + Usb3PhyDrp (test/run_phy.sh): receiver detection (present / absent), P0 entry
// and driver on / off produce the DRP writes seen on Gowin's PHY, and PhyStatus / RxStatus answer.
`timescale 1ns / 1ps
module tb_usb3_phy_ctl;
    logic pclk = 0, dclk = 0, rst = 1;
    always #4 pclk = ~pclk;
    always #8.9 dclk = ~dclk;
    logic [1:0] pd = 2'd2;
    logic ei = 1, det = 0, drive = 0, present = 1;
    wire req, done, res, physt, rx_ei;
    wire [2:0] dst;
    wire wren, rden; wire [23:0] addr; wire [31:0] wdata; wire [7:0] strb;
    logic ready = 0, rdvld = 0, rxdet = 0;
    Usb3PhyCtl u_ctl (.i_clk(pclk), .i_rst(rst), .i_power_down(pd), .i_elecidle(ei), .i_detectrx(det), .i_sig(1'b0), .i_rx_good(1'b0),
        .i_det_done(done), .i_det_res(res), .o_det_req(req), .o_phy_status(physt), .o_det_status(dst), .o_rx_elecidle(rx_ei));
    Usb3PhyDrp #(.WAIT_CLKS(20)) u_drp (.i_clk(dclk), .i_rst(rst), .i_drive(drive), .i_power_down(pd), .i_det_req(req),
        .i_rxdet(rxdet), .o_det_done(done), .o_det_res(res), .o_rd_last(), .o_wren(wren), .o_rden(rden), .o_addr(addr),
        .o_wrdata(wdata), .o_strb(strb), .i_ready(ready), .i_rdvld(rdvld), .i_rddata(32'h02000003));
    // DRP slave: answers after 3 clocks; a receiver detection write pulses rxdet when present
    string log = "";
    int cnt = 0;
    always @(posedge dclk) begin
        ready <= 0; rdvld <= 0;
        if ((wren || rden) && !ready && !rdvld) begin
            cnt <= cnt + 1;
            if (cnt == 3) begin
                cnt <= 0;
                if (wren) begin
                    ready <= 1;
                    log = {log, $sformatf("W%06x=%0x ", addr, wdata)};
                    if (addr == 24'h80033f && wdata == 32'h03000000 && present) fork begin #200 rxdet = 1; #1800 rxdet = 0; end join_none
                end else begin
                    rdvld <= 1;
                    log = {log, $sformatf("R%06x ", addr)};
                end
            end
        end
    end
    task automatic detect(input logic want);
        int t;
        present = want; log = "";
        @(negedge pclk) det = 1;
        t = 0;
        while (!physt) begin @(negedge pclk); t++; if (t > 20000) $fatal(1, "no PhyStatus for detection"); end
        if (dst != (want ? 3'd3 : 3'd0)) $fatal(1, "RxStatus %0d, want %0d", dst, want ? 3 : 0);
        @(negedge pclk) det = 0;
        repeat (100) @(negedge pclk);
        $display("detect %0d: %s", want, log);
        if (log != (want ? "W80033f=3000000 W80033f=0 R808b34 W808238=0 W8082d8=0 W8082d8=110 "
                         : "W80033f=3000000 W80033f=0 R808b34 ")) $fatal(1, "detection sequence");
    endtask
    initial begin
        repeat (10) @(negedge pclk);
        rst = 0;
        repeat (20) @(negedge pclk);
        detect(1);
        detect(0);
        // LFPS: driver on / off
        log = "";
        @(negedge pclk) begin ei = 0; drive = 1; end
        repeat (200) @(negedge pclk);
        @(negedge pclk) begin ei = 1; drive = 0; end
        repeat (200) @(negedge pclk);
        $display("lfps: %s", log);
        if (log != "W8003a4=7 W8003a4=1 ") $fatal(1, "driver sequence");
        // P0 entry: PhyStatus at once, then the writes
        log = "";
        @(negedge pclk) pd = 2'd0;
        @(negedge pclk);
        if (!physt) $fatal(1, "no PhyStatus on P0 entry");
        @(negedge pclk) begin ei = 0; drive = 1; end
        repeat (400) @(negedge pclk);
        $display("p0: %s", log);
        if (log != "W808238=805 W8082d8=0 W8082d8=110 W8003a4=7 ") $fatal(1, "P0 sequence");
        $display("ctl: ok");
        $finish;
    end
endmodule
