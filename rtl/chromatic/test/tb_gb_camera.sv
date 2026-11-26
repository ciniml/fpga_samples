// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// tb_gb_camera: GbCamera against gb_camera_ref.py (make camera)
//   cam_in.hex: per case 14336 frame bytes + 64 register bytes; cam_out.hex: per case RAM 0x100-0xEFF
`timescale 1ns/1ps
module tb_gb_camera;
    localparam int NCASE = 6;
    localparam int FB = 128 * 112;
    localparam int REC = FB + 64;

    logic clk = 0, pclk = 0, rst = 1;
    always #5 clk = ~clk;
    always #4 pclk = ~pclk;

    logic        fb_we = 0, frame = 0;
    logic [13:0] fb_wa = 0;
    logic [7:0]  fb_wd = 0;
    logic        reg_we = 0;
    logic [6:0]  reg_a = 0;
    logic [7:0]  reg_d = 0;
    logic [7:0]  reg0;
    logic        busy, ram_we;
    logic [12:0] ram_wa;
    logic [7:0]  ram_wd;
    logic [15:0] h_ra = 0;
    logic [7:0]  h_q;
    GbCamera #(.TIMEOUT(100000)) dut (
        .i_clk(clk), .i_rst(rst),
        .i_pclk(pclk), .i_fb_we(fb_we), .i_fb_wa(fb_wa), .i_fb_wd(fb_wd), .i_frame(frame),
        .i_reg_we(reg_we), .i_reg_a(reg_a), .i_reg_d(reg_d), .o_reg0(reg0), .o_busy(busy),
        .o_ram_we(ram_we), .o_ram_wa(ram_wa), .o_ram_wd(ram_wd),
        .i_h_ra(h_ra), .o_h_q(h_q));

    logic [7:0] in_mem [0:NCASE*REC-1];
    logic [7:0] ram [0:8191];
    int nwr;
    always @(posedge clk) if (ram_we) begin
        ram[ram_wa] <= ram_wd;
        nwr <= nwr + 1;
    end

    task automatic wreg(input int a, input int d);
        @(posedge clk);
        reg_we <= 1; reg_a <= 7'(a); reg_d <= 8'(d);
        @(posedge clk);
        reg_we <= 0;
    endtask

    int fo, errs = 0;
    int t0;
    initial begin
        $readmemh("cam_in.hex", in_mem);
        fo = $fopen("cam_out.hex", "w");
        repeat (10) @(posedge clk);
        rst <= 0;
        for (int c = 0; c < NCASE; c++) begin
            // the frame (camera clock)
            for (int i = 0; i < FB; i++) begin
                @(posedge pclk);
                fb_we <= 1; fb_wa <= 14'(i); fb_wd <= in_mem[c*REC + i];
            end
            // the tile colours (0x3800-0x3AFF)
            for (int i = 0; i < 768; i++) begin
                @(posedge pclk);
                fb_we <= 1; fb_wa <= 14'(14'h3800 + i); fb_wd <= 8'(i * 7 + c * 31);
            end
            @(posedge pclk);
            fb_we <= 0;
            // host read of the frame
            @(posedge clk); h_ra <= 16'd1234;
            @(posedge clk); @(posedge clk);
            if (h_q !== in_mem[c*REC + 1234]) begin
                $display("case %0d: host frame read %02x, want %02x", c, h_q, in_mem[c*REC + 1234]);
                errs++;
            end
            for (int a = 1; a < 54; a++) wreg(a, in_mem[c*REC + FB + a]);
            wreg(54, c & 1);                    // colour on odd cases
            for (int a = 0; a < 8192; a++) ram[a] = 8'h55;
            nwr = 0;
            // shoot, then the frame completes
            wreg(0, 8'h01);
            @(posedge clk);
            if (!busy || reg0[0] !== 1'b1) begin $display("case %0d: not busy after the shot", c); errs++; end
            repeat (200) @(posedge clk);
            @(posedge pclk); frame <= ~frame;
            t0 = $time;
            while (busy) @(posedge clk);
            $display("case %0d: shot took %0d ns, %0d RAM writes", c, $time - t0, nwr);
            if (nwr != 3584 + ((c & 1) ? 672 : 0)) errs++;
            for (int ch = 0; ch < 3; ch++) for (int t = 0; t < 224; t++)
                if (ram['hF00 + ch * 256 + t] !== ((c & 1) ? 8'(ch * 256 + t) * 8'd7 + 8'(c * 31) : 8'h55)) begin
                    if (errs < 10) $display("case %0d: colour %0d tile %0d: %02x", c, ch, t, ram['hF00 + ch * 256 + t]);
                    errs++;
                end
            for (int a = 'h100; a < 'hF00; a++) $fwrite(fo, "%02x\n", ram[a]);
        end
        // status: shots
        @(posedge clk); h_ra <= 16'h4044;
        @(posedge clk); @(posedge clk);
        if (h_q != NCASE) begin $display("shots %0d", h_q); errs++; end
        $fclose(fo);
        if (errs) $display("TB FAIL (%0d)", errs);
        else $display("TB PASS");
        if (errs) $fatal(1);
        $finish;
    end
endmodule
