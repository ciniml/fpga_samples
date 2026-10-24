// Testbench of the Tang Primer 20K top of ethernet_hub75.
//
// Host side of the RMII link + a HUB75 panel model:
//   1. ARP request for the DUT       -> ARP reply checked field by field
//   2. ICMP echo request (64 B)      -> echo reply (checksums, payload)
//   3. a frame with a bad FCS        -> dropped, no reply
//   4. a video frame (util/udpvideosend format: 32 packets of 2 + 1024 B)
//                                    -> 0xdeadbeef ack, then the panel
//      model must show every pixel (identity colour table)
//   5. a colour table (LUT port) + a second frame -> panel shows the table
//      values
//   6. ARP again (the service still answers after the video traffic)
//
// The panel model shifts the lanes on HUB75 CLK rising edges, takes a
// bit plane on every LAT (MSB plane first after a row change) and checks
// the OE pulse length of each plane.
`timescale 1ns/1ps
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */
module tb;
    localparam int W = 128, H = 128, BITS = 6, LANES = 4, SCAN = 32, BASE_OE = 16;
    localparam logic [47:0] DUT_MAC  = 48'h11_22_33_44_55_66;
    localparam logic [31:0] DUT_IP   = 32'hC0A8_0A02;
    localparam logic [47:0] HOST_MAC = 48'h02_00_00_00_00_01;
    localparam logic [31:0] HOST_IP  = 32'hC0A8_0A01;
    localparam int VIDEO_PORT = 10004, LUT_PORT = 10005;

    logic clk27 = 0;
    always #18.518 clk27 = ~clk27;
    logic rmii_clk = 0;
    always #10 rmii_clk = ~rmii_clk;

    logic [1:0] rxd = 2'b00;
    logic       crs_dv = 1'b0;
    wire  [1:0] txd;
    wire        txen;
    wire  [5:0] led;
    wire        rstn, mdc;
    wire        hclk, lat, oe, ra, rb, rc, rd, re;
    wire  [1:0] r1, g1, b1, r2, g2, b2;
    wire        hclk2, lat2, oe2, ra2, rb2, rc2, rd2, re2;

    TangPrimer20kTop #(.PHY_RST_LOG2(8)) dut (
        .clk27(clk27), .led(led),
        .rmii_txclk(rmii_clk), .rmii_rxd(rxd), .rmii_crs_dv(crs_dv),
        .rmii_txd(txd), .rmii_txen(txen), .rmii_mdio(1'b1), .rmii_mdc(mdc), .rmii_rstn(rstn),
        .hub75io_clk(hclk), .hub75io_r(r1), .hub75io_g(g1), .hub75io_b(b1),
        .hub75io_row_a(ra), .hub75io_row_b(rb), .hub75io_row_c(rc), .hub75io_row_d(rd), .hub75io_row_e(re),
        .hub75io_lat(lat), .hub75io_oe(oe),
        .hub75io_clk_2(hclk2), .hub75io_r_2(r2), .hub75io_g_2(g2), .hub75io_b_2(b2),
        .hub75io_row_a_2(ra2), .hub75io_row_b_2(rb2), .hub75io_row_c_2(rc2), .hub75io_row_d_2(rd2), .hub75io_row_e_2(re2),
        .hub75io_lat_2(lat2), .hub75io_oe_2(oe2)
    );

    int errors = 0;

    // ------------------------------------------------------------------
    // CRC / checksums
    // ------------------------------------------------------------------
    function automatic logic [31:0] crc32_byte(input logic [31:0] crc, input logic [7:0] b);
        logic [31:0] c;
        c = crc ^ {24'b0, b};
        for (int i = 0; i < 8; i++) c = c[0] ? ((c >> 1) ^ 32'hEDB88320) : (c >> 1);
        return c;
    endfunction

    byte unsigned txf [0:2047];   // frame being built (host -> DUT)
    int           txf_len;

    function automatic logic [15:0] csum(input int start, input int len);
        int unsigned s = 0;
        for (int i = 0; i < len; i += 2) begin
            s += {txf[start + i], 8'h00};
            if (i + 1 < len) s += txf[start + i + 1];
        end
        while (s >> 16) s = (s & 16'hFFFF) + (s >> 16);
        return ~s[15:0];
    endfunction

    // ------------------------------------------------------------------
    // host -> DUT (RMII receive side of the DUT)
    // ------------------------------------------------------------------
    task automatic send_dibits(input logic [7:0] b);
        for (int d = 0; d < 4; d++) begin
            @(negedge rmii_clk);
            crs_dv = 1'b1;
            rxd    = b[2*d +: 2];
        end
    endtask

    task automatic send_frame(input bit bad_fcs = 0);
        logic [31:0] crc = 32'hFFFF_FFFF;
        for (int i = 0; i < 7; i++) send_dibits(8'h55);
        send_dibits(8'hD5);
        for (int i = 0; i < txf_len; i++) begin
            crc = crc32_byte(crc, txf[i]);
            send_dibits(txf[i]);
        end
        crc = ~crc;
        if (bad_fcs) crc ^= 32'h0000_0100;
        for (int i = 0; i < 4; i++) send_dibits(crc[8*i +: 8]);
        @(negedge rmii_clk);
        crs_dv = 1'b0;
        rxd    = 2'b00;
        repeat (48) @(negedge rmii_clk);   // inter-frame gap
    endtask

    task automatic put_mac(input int off, input logic [47:0] m);
        for (int i = 0; i < 6; i++) txf[off + i] = m[8*(5-i) +: 8];
    endtask
    task automatic put_ip(input int off, input logic [31:0] a);
        for (int i = 0; i < 4; i++) txf[off + i] = a[8*(3-i) +: 8];
    endtask
    task automatic put16(input int off, input logic [15:0] v);
        txf[off] = v[15:8];
        txf[off + 1] = v[7:0];
    endtask

    // Ethernet + IPv4 header (no options), proto, payload length after the IP header
    task automatic build_ip(input logic [7:0] proto, input int ip_payload, input logic [15:0] id);
        put_mac(0, DUT_MAC);
        put_mac(6, HOST_MAC);
        put16(12, 16'h0800);
        txf[14] = 8'h45; txf[15] = 8'h00;
        put16(16, 20 + ip_payload);
        put16(18, id);
        put16(20, 16'h4000);
        txf[22] = 8'd64; txf[23] = proto;
        put16(24, 16'h0000);
        put_ip(26, HOST_IP);
        put_ip(30, DUT_IP);
        put16(24, csum(14, 20));
        txf_len = 14 + 20 + ip_payload;
        if (txf_len < 60) begin
            for (int i = txf_len; i < 60; i++) txf[i] = 8'h00;
            txf_len = 60;
        end
    endtask

    task automatic build_udp(input int sport, input int dport, input int len);  // payload already at txf[42..]
        build_ip(8'd17, 8 + len, 16'h1234);
        put16(34, sport);
        put16(36, dport);
        put16(38, 8 + len);
        put16(40, 16'h0000);
    endtask

    // ------------------------------------------------------------------
    // DUT -> host (RMII transmit side of the DUT)
    // ------------------------------------------------------------------
    byte unsigned rxq   [0:15][0:2047];
    int           rxq_len [0:15];
    int           rxq_wr = 0, rxq_rd = 0;
    logic [1:0]   dib [$];

    always @(posedge rmii_clk) begin
        if (txen) begin
            dib.push_back(txd);
        end else if (dib.size() != 0) begin
            automatic int nbytes = dib.size() / 4;
            automatic logic [31:0] crc = 32'hFFFF_FFFF;
            automatic byte unsigned bytes [0:2047];
            for (int i = 0; i < nbytes; i++)
                bytes[i] = {dib[4*i+3], dib[4*i+2], dib[4*i+1], dib[4*i]};
            if (dib.size() % 4 != 0) begin
                $display("[%0t] ERROR: tx frame of %0d dibits", $time, dib.size()); errors++;
            end
            for (int i = 0; i < 7; i++) if (bytes[i] != 8'h55) begin
                $display("[%0t] ERROR: bad preamble byte %0d = %02x", $time, i, bytes[i]); errors++;
            end
            if (bytes[7] != 8'hD5) begin
                $display("[%0t] ERROR: bad SFD %02x", $time, bytes[7]); errors++;
            end
            for (int i = 8; i < nbytes; i++) crc = crc32_byte(crc, bytes[i]);
            if (crc != 32'hDEBB20E3) begin
                $display("[%0t] ERROR: tx FCS bad (residue %08x)", $time, crc); errors++;
            end
            rxq_len[rxq_wr % 16] = nbytes - 12;
            for (int i = 0; i < nbytes - 12; i++) rxq[rxq_wr % 16][i] = bytes[8 + i];
            rxq_wr++;
            dib.delete();
        end
    end

    // wait for the next DUT frame (timeout in us); returns its index or -1
    task automatic wait_rx(input int timeout_us, output int idx);
        int t = 0;
        while (rxq_rd == rxq_wr && t < timeout_us * 10) begin
            #100;
            t++;
        end
        if (rxq_rd == rxq_wr) idx = -1;
        else begin
            idx = rxq_rd % 16;
            rxq_rd++;
        end
    endtask

    function automatic logic [15:0] rx16(input int q, input int off);
        return {rxq[q][off], rxq[q][off + 1]};
    endfunction
    function automatic logic [47:0] rx48(input int q, input int off);
        logic [47:0] v;
        for (int i = 0; i < 6; i++) v[8*(5-i) +: 8] = rxq[q][off + i];
        return v;
    endfunction
    function automatic logic [31:0] rx32(input int q, input int off);
        return {rxq[q][off], rxq[q][off + 1], rxq[q][off + 2], rxq[q][off + 3]};
    endfunction
    function automatic logic [15:0] rx_csum(input int q, input int start, input int len);
        int unsigned s = 0;
        for (int i = 0; i < len; i += 2) begin
            s += {rxq[q][start + i], 8'h00};
            if (i + 1 < len) s += rxq[q][start + i + 1];
        end
        while (s >> 16) s = (s & 16'hFFFF) + (s >> 16);
        return s[15:0];
    endfunction

    task automatic expect_eq(input string what, input logic [63:0] got, input logic [63:0] exp);
        if (got !== exp) begin
            $display("[%0t] ERROR: %s = %0h, expected %0h", $time, what, got, exp);
            errors++;
        end
    endtask

    // ------------------------------------------------------------------
    // HUB75 panel model (sampled on the DUT system clock)
    // ------------------------------------------------------------------
    logic [LANES-1:0] sr_r [W], sr_g [W], sr_b [W];
    logic [BITS-1:0]  img_r [H][W], img_g [H][W], img_b [H][W];
    int   shift_idx = 0, plane_cnt = 0, last_row = -1, oe_len = 0, oe_plane = -1;
    int   panel_frames = 0;
    realtime frame_t0 = 0, frame_period = 0;
    logic hclk_d = 0, lat_d = 0;
    wire  [4:0] row_pins = {re, rd, rc, rb, ra};
    wire  [LANES-1:0] lanes_r = {r2, r1};
    wire  [LANES-1:0] lanes_g = {g2, g1};
    wire  [LANES-1:0] lanes_b = {b2, b1};
    bit   panel_check_oe = 0;

    always @(posedge dut.sys_clk) begin
        hclk_d <= hclk;
        lat_d  <= lat;
        if (!oe) oe_len++;
        if (hclk && !hclk_d) begin
            if (shift_idx < W) begin
                sr_r[shift_idx] = lanes_r;
                sr_g[shift_idx] = lanes_g;
                sr_b[shift_idx] = lanes_b;
            end
            shift_idx++;
        end
        if (lat && !lat_d) begin
            automatic int row = row_pins;
            automatic int plane;
            // the OE pulse of the previous plane
            if (panel_check_oe && oe_plane >= 0 && oe_len != (2 * BASE_OE) << oe_plane) begin
                $display("[%0t] ERROR: OE of plane %0d = %0d clocks, expected %0d", $time, oe_plane, oe_len, (2 * BASE_OE) << oe_plane);
                errors++;
            end
            if (row != last_row) plane_cnt = 0;
            plane = BITS - 1 - plane_cnt;
            if (shift_idx == W && plane >= 0) begin
                for (int x = 0; x < W; x++)
                    for (int l = 0; l < LANES; l++) begin
                        img_r[l * SCAN + row][x][plane] = sr_r[x][l];
                        img_g[l * SCAN + row][x][plane] = sr_g[x][l];
                        img_b[l * SCAN + row][x][plane] = sr_b[x][l];
                    end
                if (row == SCAN - 1 && plane == 0) begin
                    if (frame_t0 != 0) frame_period = $realtime - frame_t0;
                    frame_t0 = $realtime;
                    panel_frames++;
                    panel_check_oe = 1;
                end
            end
            oe_plane  = plane;
            oe_len    = 0;
            plane_cnt++;
            last_row  = row;
            shift_idx = 0;
        end
    end

    task automatic wait_panel_frames(input int n);
        int start = panel_frames;
        while (panel_frames < start + n) @(posedge dut.sys_clk);
    endtask

    // ------------------------------------------------------------------
    // tests
    // ------------------------------------------------------------------
    logic [15:0] frame_px [H * W];
    logic [7:0]  lut_r8 [32], lut_g8 [64], lut_b8 [32];
    bit          lut_identity = 1;

    function automatic logic [5:0] expect_c(input int ch, input logic [5:0] v);
        if (lut_identity) begin
            if (ch == 1) return v;                        // G6
            return {v[4:0], v[4]};                        // R5 / B5
        end
        if (ch == 0) return lut_r8[v[4:0]][7:2];
        if (ch == 1) return lut_g8[v][7:2];
        return lut_b8[v[4:0]][7:2];
    endfunction

    task automatic send_video_frame();
        for (int p = 0; p < 32; p++) begin
            put16(42, p * 1024);
            for (int i = 0; i < 1024; i++) begin
                automatic int byte_off = p * 1024 + i;
                automatic logic [15:0] px = frame_px[byte_off / 2];
                txf[44 + i] = (byte_off % 2 == 0) ? px[7:0] : px[15:8];
            end
            build_udp(VIDEO_PORT, VIDEO_PORT, 2 + 1024);
            send_frame();
        end
    endtask

    task automatic check_ack();
        int q;
        wait_rx(20000, q);
        if (q < 0) begin
            $display("[%0t] ERROR: no ack after the video frame", $time); errors++;
            return;
        end
        expect_eq("ack dst mac", rx48(q, 0), HOST_MAC);
        expect_eq("ack src mac", rx48(q, 6), DUT_MAC);
        expect_eq("ack ethertype", rx16(q, 12), 16'h0800);
        expect_eq("ack ip header csum", rx_csum(q, 14, 20), 16'hFFFF);
        expect_eq("ack proto", rxq[q][23], 8'd17);
        expect_eq("ack src ip", rx32(q, 26), DUT_IP);
        expect_eq("ack dst ip", rx32(q, 30), HOST_IP);
        expect_eq("ack sport", rx16(q, 34), VIDEO_PORT);
        expect_eq("ack dport", rx16(q, 36), VIDEO_PORT);
        expect_eq("ack udp len", rx16(q, 38), 16'd12);
        expect_eq("ack payload", rx32(q, 42), 32'hDEADBEEF);
        $display("[%0t] ack received", $time);
    endtask

    task automatic check_panel(input string what);
        int bad = 0;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++) begin
                automatic logic [15:0] px = frame_px[y * W + x];
                automatic logic [5:0] er = expect_c(0, {1'b0, px[15:11]});
                automatic logic [5:0] eg = expect_c(1, px[10:5]);
                automatic logic [5:0] eb = expect_c(2, {1'b0, px[4:0]});
                if (img_r[y][x] !== er || img_g[y][x] !== eg || img_b[y][x] !== eb) begin
                    if (bad < 8)
                        $display("[%0t] ERROR: %s pixel (%0d,%0d) = %02x %02x %02x, expected %02x %02x %02x", $time, what,
                                 x, y, img_r[y][x], img_g[y][x], img_b[y][x], er, eg, eb);
                    bad++;
                end
            end
        if (bad != 0) begin
            $display("[%0t] ERROR: %s: %0d of %0d pixels wrong", $time, what, bad, H * W);
            errors++;
        end else
            $display("[%0t] %s: all %0d pixels ok", $time, what, H * W);
    endtask

    task automatic test_arp();
        int q;
        put_mac(0, 48'hFFFF_FFFF_FFFF);
        put_mac(6, HOST_MAC);
        put16(12, 16'h0806);
        put16(14, 16'h0001); put16(16, 16'h0800); txf[18] = 6; txf[19] = 4;
        put16(20, 16'h0001);
        put_mac(22, HOST_MAC);
        put_ip(28, HOST_IP);
        put_mac(32, 48'h0);
        put_ip(38, DUT_IP);
        for (int i = 42; i < 60; i++) txf[i] = 8'h00;
        txf_len = 60;
        send_frame();
        wait_rx(200, q);
        if (q < 0) begin
            $display("[%0t] ERROR: no ARP reply", $time); errors++;
            return;
        end
        expect_eq("arp len", rxq_len[q], 60);
        expect_eq("arp dst mac", rx48(q, 0), HOST_MAC);
        expect_eq("arp src mac", rx48(q, 6), DUT_MAC);
        expect_eq("arp ethertype", rx16(q, 12), 16'h0806);
        expect_eq("arp oper", rx16(q, 20), 16'h0002);
        expect_eq("arp sha", rx48(q, 22), DUT_MAC);
        expect_eq("arp spa", rx32(q, 28), DUT_IP);
        expect_eq("arp tha", rx48(q, 32), HOST_MAC);
        expect_eq("arp tpa", rx32(q, 38), HOST_IP);
        $display("[%0t] ARP reply ok", $time);
    endtask

    task automatic test_icmp(input int plen);
        int q;
        txf[34] = 8'd8; txf[35] = 8'd0;
        put16(36, 16'h0000);
        put16(38, 16'hBEEF); put16(40, 16'h0001);
        for (int i = 0; i < plen; i++) txf[42 + i] = 8'(i * 7 + 3);
        put16(36, csum(34, 8 + plen));
        build_ip(8'd1, 8 + plen, 16'h4321);
        send_frame();
        wait_rx(200, q);
        if (q < 0) begin
            $display("[%0t] ERROR: no ICMP reply", $time); errors++;
            return;
        end
        expect_eq("icmp len", rxq_len[q], (42 + plen < 60) ? 60 : 42 + plen);
        expect_eq("icmp dst mac", rx48(q, 0), HOST_MAC);
        expect_eq("icmp src mac", rx48(q, 6), DUT_MAC);
        expect_eq("icmp ip csum", rx_csum(q, 14, 20), 16'hFFFF);
        expect_eq("icmp src ip", rx32(q, 26), DUT_IP);
        expect_eq("icmp dst ip", rx32(q, 30), HOST_IP);
        expect_eq("icmp type", rxq[q][34], 8'd0);
        expect_eq("icmp csum", rx_csum(q, 34, 8 + plen), 16'hFFFF);
        expect_eq("icmp id", rx16(q, 38), 16'hBEEF);
        for (int i = 0; i < plen; i++)
            if (rxq[q][42 + i] != 8'(i * 7 + 3)) begin
                $display("[%0t] ERROR: icmp payload byte %0d", $time, i); errors++;
                break;
            end
        $display("[%0t] ICMP echo reply (%0d B) ok", $time, plen);
    endtask

    initial begin
        int q;
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb.vcd");
            $dumpvars(0, tb);
        end
        wait (rstn === 1'b1);
        #20us;

        test_arp();
        test_icmp(64);
        test_icmp(1000);

        // bad FCS: must be dropped silently
        test_arp_bad: begin
            put_mac(0, 48'hFFFF_FFFF_FFFF);
            txf_len = 60;
            send_frame(1);
            wait_rx(50, q);
            if (q >= 0) begin
                $display("[%0t] ERROR: reply to a frame with a bad FCS", $time); errors++;
            end else
                $display("[%0t] bad FCS frame dropped", $time);
        end

        // frame 1: pseudo-random pixels, identity colour table
        for (int i = 0; i < H * W; i++) frame_px[i] = 16'($urandom);
        send_video_frame();
        check_ack();
        wait_panel_frames(2);
        check_panel("frame 1");

        // colour table: arbitrary values per channel, then frame 2
        txf[42] = 8'h07;   // R, G, B
        for (int i = 0; i < 64; i++) begin
            lut_g8[i] = 8'($urandom);
            if (i < 32) begin
                lut_r8[i] = 8'($urandom);
                lut_b8[i] = lut_r8[i];  // one stream feeds all selected channels
            end
            txf[43 + i] = lut_g8[i];
        end
        // R and B take the first 32 values of the same stream as G
        for (int i = 0; i < 32; i++) begin
            lut_r8[i] = lut_g8[i];
            lut_b8[i] = lut_g8[i];
        end
        build_udp(LUT_PORT, LUT_PORT, 1 + 64);
        send_frame();
        lut_identity = 0;
        for (int i = 0; i < H * W; i++) frame_px[i] = 16'(i * 37 + (i >> 7));
        send_video_frame();
        check_ack();
        wait_panel_frames(2);
        check_panel("frame 2 (colour table)");

        test_arp();

        $display("panel refresh: %0.1f Hz (%0.3f ms per frame)", 1.0e9 / frame_period, frame_period / 1.0e6);
        if (errors == 0) $display("PASS");
        else $display("FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #200ms;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
