// Testbench of the DK_LED-RXCARD (GW3A) top of ethernet_hub75, for all
// HUB75_IMPL (make rxcard IMPL=soft|gmt|ddr). IMPL=ddr runs the DDR2
// frame buffer against the slot-level DDR2 model (ddr2_phy_sim.sv, power-up
// wait shortened, a 4096-burst start-up memory test) and waits for the
// memory test and clear before the video tests.
//
// An RTL8211E stand-in: MDIO registers (the DUT must find the PHY and set
// the RGMII delays) and the host side of the RGMII link at 1000 Mb/s
// (RXC 125 MHz) and 100 Mb/s (25 MHz), plus a HUB75 panel model:
//   1. ARP request for the DUT       -> ARP reply checked field by field
//   2. ICMP echo request (64 B)      -> echo reply (checksums, payload)
//   3. a frame with a bad FCS        -> dropped, no reply
//   4. a video frame (util/udpvideosend format: W * H * 2 / 1024 packets
//      of 2 + 1024 B)
//                                    -> 0xdeadbeef ack, then the panel
//      model must show every pixel (identity colour table)
//   5. a colour table (LUT port) + a second frame -> panel shows the table
//      values
//   6. ARP again (the service still answers after the video traffic)
//   7. 100 Mb/s: RXC to 25 MHz, ARP and ICMP in nibble mode
//
// The panel model (one 64x64 panel per connector, J4 J5 / J6 J7 / J8 J9
// row major, PROWS rows) shifts the lanes on HUB75 CLK rising edges,
// takes a bit plane on every LAT (MSB plane first after a row change) and
// checks the OE pulse length of each plane; unused connectors must stay 0.
`timescale 1ns/1ps
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off BLKSEQ */
/* verilator lint_off INITIALDLY */
module tb;
    parameter int PROWS = 3;   // panel rows (DUT PANEL_ROWS)
    localparam int W = 128, H = 64 * PROWS, CHAIN = 64, LANES = 4 * PROWS, SCAN = 32;
    parameter int BITS = 6;          // DUT COMPONENT_BITS
    localparam int BASE_OE = 16 >> (BITS - 6), NPK = W * H * 2 / 1024;
    localparam logic [47:0] DUT_MAC  = 48'h11_22_33_44_55_66;
    localparam logic [31:0] DUT_IP   = 32'hC0A8_0A02;
    localparam logic [47:0] HOST_MAC = 48'h02_00_00_00_00_01;
    localparam logic [31:0] HOST_IP  = 32'hC0A8_0A01;
    localparam int VIDEO_PORT = 10004, LUT_PORT = 10005;

    parameter int IMPL = 0;
    // 1: the top's TXC_SHIFTED build (TXD 2 ns before TXC); the PHY model
    // then samples at the TXC edges instead of 2 ns after (its TX delay)
    parameter bit TXS = 0;
    localparam realtime TX_SAMPLE = TXS ? 0.5 : 2.0;

    logic clk50 = 0;
    always #10 clk50 = ~clk50;
    // RXC from the PHY: 125 MHz (1000 Mb/s) or 25 MHz (100 Mb/s)
    bit   gbe = 1;
    logic rxc = 0;
    always #(gbe ? 4 : 20) rxc = ~rxc;

    logic [3:0] rxd = 4'h0;
    logic       rx_ctl = 1'b0;
    wire  [3:0] txd;
    wire        tx_ctl, txc;
    wire  [1:0] led;
    wire        rstn, mdc;
    tri1        mdio;
    wire        hclk, lat, oe, oe_b;
    wire  [4:0] row_pins;
    wire  [5:0] j [6];   // J4..J9
    tri   [15:0] ddr_dq;
    tri   [1:0]  ddr_dqs;

    DkLedRxcardTop #(.HUB75_IMPL(IMPL), .PANEL_ROWS(PROWS), .COMPONENT_BITS(BITS), .BASE_OE_CYCLES(BASE_OE), .TXC_SHIFTED(TXS), .PHY_RST_LOG2(8), .PHY_WAIT_LOG2(8),
                     .DDR_T_INIT_PS(20_000_000), .BIST_BURSTS(4096)) dut (
        .clk50(clk50), .key_n(1'b1), .led(led),
        .phy_rst_n(rstn), .phy_mdc(mdc), .phy_mdio(mdio),
        .rgmii_txc(txc), .rgmii_tx_ctl(tx_ctl), .rgmii_txd(txd),
        .rgmii_rxc(rxc), .rgmii_rx_ctl(rx_ctl), .rgmii_rxd(rxd),
        .hub75_j4(j[0]), .hub75_j5(j[1]), .hub75_j6(j[2]), .hub75_j7(j[3]), .hub75_j8(j[4]),
        .hub75_j9(j[5]), .hub75_j10(), .hub75_j11(), .hub75a_row(row_pins), .hub75a_clk(hclk),
        .hub75a_lat(lat), .hub75a_oe(oe), .hub75b_oe(oe_b),
        .ddr_ck(), .ddr_cke(), .ddr_odt(), .ddr_cs_n(), .ddr_ras_n(), .ddr_cas_n(), .ddr_we_n(),
        .ddr_ba(), .ddr_a(), .ddr_dq(ddr_dq), .ddr_dqs(ddr_dqs)
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
    // one byte: 1000 Mb/s both RXC edges (low nibble at the rising edge),
    // 100 Mb/s two RXC periods; data centred between the edges (the PHY's
    // RXC delay)
    task automatic send_byte(input logic [7:0] b);
        if (gbe) begin
            @(negedge rxc); #2; rxd = b[3:0]; rx_ctl = 1'b1;
            @(posedge rxc); #2; rxd = b[7:4]; rx_ctl = 1'b1;
        end else begin
            @(negedge rxc); #10; rxd = b[3:0]; rx_ctl = 1'b1;
            @(negedge rxc); #10; rxd = b[7:4]; rx_ctl = 1'b1;
        end
    endtask

    task automatic send_frame(input bit bad_fcs = 0);
        logic [31:0] crc = 32'hFFFF_FFFF;
        for (int i = 0; i < 7; i++) send_byte(8'h55);
        send_byte(8'hD5);
        for (int i = 0; i < txf_len; i++) begin
            crc = crc32_byte(crc, txf[i]);
            send_byte(txf[i]);
        end
        crc = ~crc;
        if (bad_fcs) crc ^= 32'h0000_0100;
        for (int i = 0; i < 4; i++) send_byte(crc[8*i +: 8]);
        @(negedge rxc); #2;
        rx_ctl = 1'b0;
        rxd    = 4'h0;
        repeat (gbe ? 12 : 24) @(negedge rxc);   // inter-frame gap
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
    logic [7:0]   txb [$];
    logic [3:0]   tx_lo;
    bit           tx_half = 0, tx_bad_ctl = 0;

    // TXC leaves edge-aligned with the data; the PHY delays it by 2 ns
    task automatic tx_frame_done();
        automatic int nbytes = txb.size();
        automatic logic [31:0] crc = 32'hFFFF_FFFF;
        automatic byte unsigned bytes [0:2047];
        for (int i = 0; i < nbytes; i++) bytes[i] = txb[i];
        if (tx_half || tx_bad_ctl) begin
            $display("[%0t] ERROR: tx frame with a half byte / bad TX_CTL", $time); errors++;
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
        txb.delete();
        tx_half = 0;
        tx_bad_ctl = 0;
    endtask

    logic [3:0] tx_rise_d;
    logic       tx_rise_ctl = 0, tx_active = 0;
    always @(posedge txc) begin
        #(TX_SAMPLE);
        tx_rise_d   = txd;
        tx_rise_ctl = tx_ctl;
        if (!gbe) begin
            if (tx_ctl) begin
                tx_active = 1;
                if (!tx_half) tx_lo = txd;
                else txb.push_back({txd, tx_lo});
                tx_half = !tx_half;
            end else if (tx_active) begin
                tx_active = 0;
                tx_frame_done();
            end
        end
    end
    always @(negedge txc) begin
        #(TX_SAMPLE);
        if (gbe) begin
            if (tx_rise_ctl) begin
                tx_active = 1;
                if (!tx_ctl) tx_bad_ctl = 1;   // TX_EN xor TX_ER must stay 1
                txb.push_back({txd, tx_rise_d});
            end else if (tx_active) begin
                tx_active = 0;
                tx_frame_done();
            end
        end
    end

    // ------------------------------------------------------------------
    // RTL8211E MDIO stand-in (PHY address 1)
    // ------------------------------------------------------------------
    localparam logic [4:0] PHY_ADDR = 5'd1;
    logic [15:0] phy_reg [32];
    logic [15:0] ext_a4_1c = 16'h8a01;   // arbitrary reserved bits to keep
    logic [15:0] phy_page = 0, phy_ext = 0;
    int          bmcr_writes = 0;
    logic        md_drive = 0, md_bit = 1;
    assign mdio = md_drive ? md_bit : 1'bz;

    initial begin
        for (int i = 0; i < 32; i++) phy_reg[i] = 16'h0000;
        phy_reg[2] = 16'h001C;
        phy_reg[3] = 16'hC915;
    end

    function automatic logic [15:0] phy_read(input logic [4:0] r);
        if (r == 5'h1c && phy_page == 7 && phy_ext == 16'h00a4) return ext_a4_1c;
        if (r == 5'h1f) return phy_page;
        return phy_reg[r];
    endfunction

    task automatic phy_write(input logic [4:0] r, input logic [15:0] v);
        if (r == 5'h1f) phy_page = v;
        else if (r == 5'h1e && phy_page == 7) phy_ext = v;
        else if (r == 5'h1c && phy_page == 7 && phy_ext == 16'h00a4) ext_a4_1c = v;
        else begin
            phy_reg[r] = v;
            if (r == 5'h00) bmcr_writes++;
        end
    endtask

    initial begin : mdio_slave
        int ones;
        logic [13:0] hdr;
        logic [15:0] v;
        forever begin
            // preamble (>= 32 ones), then ST = 01
            ones = 0;
            forever begin
                @(posedge mdc);
                if (mdio === 1'b1) ones++;
                else if (ones >= 32) break;
                else ones = 0;
            end
            // got the 0 of ST: 13 more header bits (1, OP, PHYAD, REGAD)
            hdr = 0;
            for (int i = 0; i < 13; i++) begin
                @(posedge mdc);
                hdr = {hdr[12:0], mdio};
            end
            // hdr[12] = ST 1, [11:10] OP, [9:5] PHY, [4:0] REG
            if (hdr[11:10] == 2'b10 && hdr[9:5] == PHY_ADDR) begin
                v = phy_read(hdr[4:0]);
                @(posedge mdc);            // TA bit 1 (Z)
                #20 md_drive = 1; md_bit = 0;
                @(posedge mdc);            // TA bit 2 (0)
                for (int i = 15; i >= 0; i--) begin
                    #20 md_bit = v[i];
                    @(posedge mdc);
                end
                #20 md_drive = 0;
            end else if (hdr[11:10] == 2'b01) begin
                v = 0;
                @(posedge mdc); @(posedge mdc);   // TA
                for (int i = 0; i < 16; i++) begin
                    @(posedge mdc);
                    v = {v[14:0], mdio};
                end
                if (hdr[9:5] == PHY_ADDR) phy_write(hdr[4:0], v);
            end else begin
                repeat (18) @(posedge mdc);
            end
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
    logic [LANES-1:0] sr_r [CHAIN], sr_g [CHAIN], sr_b [CHAIN];
    logic [BITS-1:0]  img_r [H][W], img_g [H][W], img_b [H][W];
    int   shift_idx = 0, plane_cnt = 0, last_row = -1, oe_len = 0, oe_plane = -1;
    int   panel_frames = 0;
    realtime frame_t0 = 0, frame_period = 0;
    logic hclk_d = 0, lat_d = 0;
    // lane l (64 wide, row major): panel row l / 4, column l % 2, R2 half
    // when (l / 2) % 2; connector J(4 + 2 * row + column)
    logic [LANES-1:0] lanes_r, lanes_g, lanes_b;
    always_comb
        for (int l = 0; l < LANES; l++) begin
            automatic int k = 2 * (l / 4) + l % 2, o = ((l / 2) % 2) * 3;
            lanes_r[l] = j[k][o];
            lanes_g[l] = j[k][o + 1];
            lanes_b[l] = j[k][o + 2];
        end
    bit   panel_check_oe = 0;

    always @(posedge dut.disp_clk) begin
        hclk_d <= hclk;
        lat_d  <= lat;
        if (!oe) oe_len++;
        if (hclk && !hclk_d) begin
            for (int k = 2 * PROWS; k < 6; k++)
                if (j[k] !== 6'd0) begin
                    $display("[%0t] ERROR: unused connector J%0d = %b", $time, 4 + k, j[k]);
                    errors++;
                end
            if (shift_idx < CHAIN) begin
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
            if (shift_idx == CHAIN && plane >= 0) begin
                for (int x = 0; x < CHAIN; x++)
                    for (int l = 0; l < LANES; l++) begin
                        automatic int y0 = (l / 2) * SCAN, x0 = (l % 2) * CHAIN;
                        img_r[y0 + row][x0 + x][plane] = sr_r[x][l];
                        img_g[y0 + row][x0 + x][plane] = sr_g[x][l];
                        img_b[y0 + row][x0 + x][plane] = sr_b[x][l];
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
        while (panel_frames < start + n) @(posedge dut.disp_clk);
    endtask

    // ------------------------------------------------------------------
    // tests
    // ------------------------------------------------------------------
    logic [15:0] frame_px [H * W];
    logic [7:0]  lut_r8 [32], lut_g8 [64], lut_b8 [32];
    bit          lut_identity = 1;

    // the top BITS bits of the 8-bit table value (identity: bit replication)
    function automatic logic [7:0] expect_c(input int ch, input logic [5:0] v);
        logic [7:0] e8;
        if (lut_identity) e8 = (ch == 1) ? {v[5:0], v[5:4]} : {v[4:0], v[4:2]};
        else if (ch == 0) e8 = lut_r8[v[4:0]];
        else if (ch == 1) e8 = lut_g8[v];
        else e8 = lut_b8[v[4:0]];
        return e8 >> (8 - BITS);
    endfunction

    task automatic send_video_frame();
        for (int p = 0; p < NPK; p++) begin
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
                automatic logic [7:0] er = expect_c(0, {1'b0, px[15:11]});
                automatic logic [7:0] eg = expect_c(1, px[10:5]);
                automatic logic [7:0] eb = expect_c(2, {1'b0, px[4:0]});
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

    // status port: any datagram -> 48 bytes of status from port 10006
    byte unsigned st [48];
    task automatic test_status(input int flips, input int runs = 1);
        int q;
        txf[42] = 8'h00;
        build_udp(40000, 10006, 1);
        send_frame();
        wait_rx(200, q);
        if (q < 0) begin
            $display("[%0t] ERROR: no status reply", $time); errors++;
            return;
        end
        expect_eq("status dst mac", rx48(q, 0), HOST_MAC);
        expect_eq("status ip csum", rx_csum(q, 14, 20), 16'hFFFF);
        expect_eq("status ip len", rx16(q, 16), 16'd76);
        expect_eq("status dst ip", rx32(q, 30), HOST_IP);
        expect_eq("status sport", rx16(q, 34), 16'd10006);
        expect_eq("status dport", rx16(q, 36), 16'd40000);
        expect_eq("status udp len", rx16(q, 38), 16'd56);
        expect_eq("status magic", rxq[q][42], 8'hD2);
        expect_eq("status flags", rxq[q][43] & 8'hBF, IMPL >= 2 ? 8'h37 : 8'h01);
        expect_eq("status memory test errors", rx16(q, 46), 16'd0);
        expect_eq("status speed", rxq[q][51], 8'd2);
        expect_eq("status overflow", rx16(q, 52), 16'd0);
        expect_eq("status flips", rx32(q, 54), flips);
        expect_eq("status pass errors", {rx16(q, 58), rx16(q, 60), rx16(q, 62)}, 0);
        expect_eq("status runs", rx32(q, 82), IMPL >= 2 ? runs + ($test$plusargs("ddr_marginal") ? 2 : 0) : 0);
        for (int i = 0; i < 48; i++) st[i] = rxq[q][42 + i];
        if (IMPL >= 2) expect_eq("read tuning done", rxq[q][42 + 44] >> 7, 1);
        $display("[%0t] status reply ok (RD_LAT %0d, RD_SEL %0d / %0d)", $time, rxq[q][44], rxq[q][45] & 15, rxq[q][45] >> 4);
    endtask

    initial begin
        int q;
        if ($test$plusargs("vcd")) begin
            $dumpfile("tb.vcd");
            $dumpvars(0, tb);
        end
        wait (rstn === 1'b1);
        wait (dut.phy_done === 1'b1);
        expect_eq("phys configured", dut.phy_cnt2, 1);
        expect_eq("ext a4 reg 1c", ext_a4_1c, 16'hba01);
        expect_eq("page restored", phy_page, 0);
        expect_eq("autoneg restarts", bmcr_writes, 1);
        $display("[%0t] MDIO: RGMII delays set", $time);
        #40us;
        expect_eq("speed 1000", dut.speed, 2);

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

        if (IMPL >= 2) begin
            wait (dut.t_done === 1'b1 && dut.fb_ready === 1'b1);
            expect_eq("ddr2 calibrated", dut.cal_ok, 1);
            expect_eq("ddr2 memory test errors", dut.bist_err, 0);
            if ($test$plusargs("ddr_marginal")) begin
                // the read tuning must have moved to the second slots
                expect_eq("tuning moved", dut.t_en, 1);
                if (dut.t_first == 0) begin
                    $display("[%0t] ERROR: no errors in the first memory test with +ddr_marginal", $time); errors++;
                end
                $display("[%0t] read tuning: first test %0d wrong words, slots %0d / %0d", $time, dut.t_first, dut.t_sel, dut.t_sel_o);
            end
            $display("[%0t] DDR2: initialised, memory test passed, frame buffer cleared", $time);
            wait_panel_frames(1);
            begin
                int lit = 0;
                for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) if (img_r[y][x] || img_g[y][x] || img_b[y][x]) lit++;
                expect_eq("black before the first frame (lit pixels)", lit, 0);
            end
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

        test_status(2);
        if (IMPL >= 2) begin
            // control: override with the calibrated values and run the
            // memory test again, then back to the calibration
            txf[42] = 8'h01;
            // the values in use: tuned if the tuning moved a slot
            txf[43] = (st[44] >> 6 & 1) ? st[45] & 15 : st[3] & 15;
            txf[44] = (st[44] >> 6 & 1) ? st[45] >> 4 : st[3] >> 4;
            txf[45] = st[2];
            build_udp(40000, 10007, 4);
            send_frame();
            #100us;
            wait (dut.fb_ready === 1'b1);
            #10us;
            test_status(2, 2);
            expect_eq("override flag", st[1] >> 6 & 1, 1);
            expect_eq("override sel", st[22], (st[44] >> 6 & 1) ? st[45] : st[3]);
            if (!$test$plusargs("ddr_marginal")) begin
                // (with +ddr_marginal the calibrated slots are the bad ones)
                txf[42] = 8'h02;
                build_udp(40000, 10007, 1);
                send_frame();
                #100us;
                wait (dut.fb_ready === 1'b1);
                #10us;
                test_status(2, 3);
                expect_eq("override off", st[1] >> 6 & 1, 0);
            end
        end
        test_arp();

        // 100 Mb/s
        gbe = 0;
        #80us;
        expect_eq("speed 100", dut.speed, 1);
        test_arp();
        test_icmp(64);

        $display("panel refresh: %0.1f Hz (%0.3f ms per frame)", 1.0e9 / frame_period, frame_period / 1.0e6);
        if (errors == 0) $display("PASS");
        else $display("FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #300ms;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
