// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file tb_isp.sv
 * @brief Camera pipeline: RAW10 packets (as Csi2Rx delivers them) in the
 *        camera clock domain -> IspRaw10Unpack -> IspLineRing -> IspDisplay
 *        in the display domain, locked by IspGenlock.
 *
 * Small frames (W x H, display HT x VT) at the real clocks (125 / 74.25 MHz).
 * The camera model sends FS, then rows with headers every display line
 * period (+ a small rate error PPM), VTS lines a frame; a new VTS from
 * the genlock applies from the next frame. It starts at an arbitrary
 * phase. Checks: the genlock locks, and once locked every output frame
 * equals the reference (test/isp_ref.py) of the raw image, which is
 * different every frame. Writes out/raw.txt, out/frames.txt.
 */
`timescale 1ns/1ps
`default_nettype none
module tb_isp #(
    parameter int W = 64, parameter int H = 32,
    parameter int HFP = 20, parameter int HSW = 4, parameter int HBP = 12,
    parameter int VFP = 2, parameter int VSW = 2, parameter int VBP = 4,
    parameter real PPM = 150.0,
    parameter int START_PHASE = 13,     // camera row 0 offset at start (lines)
    parameter int NFRAMES = 40
);
    localparam int HT = W + HFP + HSW + HBP;
    localparam int VT = H + VFP + VSW + VBP;
    localparam real TP = 1000.0 / 74.25;        // display pixel clock period (ns)
    localparam real LINE_NS = HT * TP;

    logic cclk = 0, pclk = 0;
    always #4 cclk = ~cclk;
    always #(TP / 2) pclk = ~pclk;
    logic crst = 1, prst = 1;

    // ---------------- camera model -> Csi2Rx-like outputs ----------------
    logic        hdr = 0, short_ = 0, vld = 0;
    logic [5:0]  dt = 0;
    logic [15:0] data = 0;
    logic [1:0]  be = 0;
    int vts_cam = VT;
    logic [15:0] vts_cmd;
    logic        vts_req, vts_req_d = 0;
    int frame_no = 0;

    function automatic logic [9:0] rawpix(int f, int x, int y);
        int h = (x * 7919 + y * 104729 + f * 1299709) ^ (x * y * 31 + f * 17);
        h = h ^ (h >> 7) ^ (h << 3);
        return h[9:0];
    endfunction

    integer fraw;
    task automatic send_hdr(input logic s, input logic [5:0] t);
        @(posedge cclk); hdr <= 1; short_ <= s; dt <= t;
        @(posedge cclk); hdr <= 0;
    endtask
    task automatic send_row(input int f, input int y);
        logic [7:0] b [$];
        for (int g = 0; g < W / 4; g++) begin
            logic [9:0] p [4];
            for (int k = 0; k < 4; k++) p[k] = rawpix(f, 4 * g + k, y);
            for (int k = 0; k < 4; k++) b.push_back(p[k][9:2]);
            b.push_back({p[3][1:0], p[2][1:0], p[1][1:0], p[0][1:0]});
        end
        send_hdr(0, 6'h2B);
        repeat (6) @(posedge cclk);
        while (b.size() != 0) begin
            @(posedge cclk);
            vld <= 1;
            if (b.size() >= 2) begin data <= {b[1], b[0]}; be <= 2'b11; void'(b.pop_front()); void'(b.pop_front()); end
            else begin data <= {8'h00, b[0]}; be <= 2'b01; void'(b.pop_front()); end
            @(posedge cclk); vld <= 0;
        end
    endtask

    real cam_line;
    initial begin
        real t0;
        cam_line = LINE_NS * (1.0 + PPM * 1e-6);
        fraw = $fopen("out/raw.txt", "w");
        #(START_PHASE * LINE_NS + 1000.0);
        forever begin
            t0 = $realtime;
            if (vts_req != vts_req_d) begin vts_req_d = vts_req; vts_cam = vts_cmd; end
            send_hdr(1, 6'h00);                                  // FS
            for (int y = 0; y < H; y++) begin
                wait ($realtime >= t0 + (y + 1) * cam_line);      // row y: one line after FS + y
                send_row(frame_no, y);
            end
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++) $fwrite(fraw, "%0d\n", rawpix(frame_no, x, y));
            wait ($realtime >= t0 + vts_cam * cam_line);
            frame_no++;
        end
    end

    // ---------------- DUT ----------------
    logic        we;
    logic [8:0]  waddr;
    logic [39:0] wdata;
    logic [11:0] row;
    logic        r0, fs;
    IspRaw10Unpack u_unpack (
        .i_clk(cclk), .i_rst(crst),
        .i_hdr(hdr), .i_short(short_), .i_dt(dt), .i_data(data), .i_be(be), .i_vld(vld),
        .o_we(we), .o_waddr(waddr), .o_wdata(wdata), .o_row(row), .o_r0(r0), .o_fs(fs));

    // r0 -> display domain (toggle + 2 FF)
    logic r0_t = 0;
    always @(posedge cclk) if (r0) r0_t <= ~r0_t;
    logic [2:0] r0_s = 0;
    always @(posedge pclk) r0_s <= {r0_s[1:0], r0_t};
    wire r0_p = r0_s[2] ^ r0_s[1];

    logic [11:0] x, y;
    logic de, hs, vs;
    IspVideoTiming #(.HACT(W), .HFP(HFP), .HSW(HSW), .HBP(HBP), .VACT(H), .VFP(VFP), .VSW(VSW), .VBP(VBP)) u_tim (
        .i_clk(pclk), .i_rst(prst), .o_x(x), .o_y(y), .o_de(de), .o_hs(hs), .o_vs(vs));

    logic [8:0]  raddr;
    logic [2:0]  rb0, rb1, rb2;
    logic [39:0] q0, q1, q2;
    IspLineRing u_ring (
        .i_wclk(cclk), .i_we(we), .i_wbank(row[2:0]), .i_waddr(waddr), .i_wdata(wdata),
        .i_rclk(pclk), .i_raddr(raddr), .i_rbank0(rb0), .i_rbank1(rb1), .i_rbank2(rb2),
        .o_q0(q0), .o_q1(q1), .o_q2(q2));

    localparam logic [9:0]  BLACK = 10'd40;
    localparam logic [15:0] GR = 16'h01A0, GG = 16'h0100, GB = 16'h0180;   // 1.625, 1.0, 1.5
    logic [23:0] rgb;
    logic ode, ohs, ovs;
    IspDisplay #(.W(W), .H(H)) u_disp (
        .i_clk(pclk), .i_rst(prst), .i_x(x), .i_y(y), .i_de(de), .i_hs(hs), .i_vs(vs),
        .i_black(BLACK), .i_gain_r(GR), .i_gain_g(GG), .i_gain_b(GB), .i_cfa(2'd3), .i_mode(2'd0),
        .o_raddr(raddr), .o_rbank0(rb0), .o_rbank1(rb1), .o_rbank2(rb2), .i_q0(q0), .i_q1(q1), .i_q2(q2),
        .o_rgb(rgb), .o_de(ode), .o_hs(ohs), .o_vs(ovs));

    logic [15:0] err;
    logic [11:0] vr0;
    logic        locked;
    IspGenlock #(.VT(VT)) u_lock (
        .i_clk(pclk), .i_rst(prst), .i_y(y), .i_x(x), .i_r0(r0_p),
        .i_en(1'b1), .i_target(8'd4), .i_vts0(16'(VT)), .i_maxstep(8'd8),
        .o_vts(vts_cmd), .o_req(vts_req), .o_err(err), .o_vr0(vr0), .o_locked(locked));

    // ---------------- output capture ----------------
    // Display frame n shows the camera frame whose row 0 came just before
    // its active area; the frame number is that of the last row 0.
    int last_r0_frame = -1;
    always @(posedge cclk) if (r0) last_r0_frame <= frame_no;
    integer fout;
    int ox = 0, oy = 0, nshown = 0, shown_frame = -1;
    logic ovs_d = 0, cap = 0;   // cap: locked at the start of this frame
    initial fout = $fopen("out/frames.txt", "w");
    always @(posedge pclk) if (!prst) begin
        ovs_d <= ovs;
        if (ode) begin
            if (ox == 0 && oy == 0) begin
                shown_frame = last_r0_frame;
                cap = locked;
                if (cap) $fwrite(fout, "F %0d\n", shown_frame);
            end
            if (cap) $fwrite(fout, "%06h\n", rgb);
            ox++;
            if (ox == W) begin ox = 0; oy++; end
        end
        if (ovs && !ovs_d) begin
            if (oy != 0 && oy != H) $display("frame with %0d lines", oy);
            oy = 0; ox = 0;
        end
    end
    int nf = 0;
    always @(posedge pclk) if (!prst && x == 0 && y == VT - 1) begin
        nf++;
        $display("[%0t] display frame %0d: vr0 %0d err %0d vts %0d locked %0d", $time, nf, vr0, $signed(err), vts_cmd, locked);
    end

    initial begin
        repeat (10) @(posedge cclk);
        crst = 0;
        repeat (4) @(posedge pclk);
        prst = 0;
        wait (nf == NFRAMES);
        $fclose(fout);
        $fclose(fraw);
        if (!locked) $fatal(1, "tb_isp: genlock did not lock");
        $display("tb_isp: done (locked)");
        $finish;
    end
endmodule
`default_nettype wire
