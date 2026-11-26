// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// GameCart AUTO_BOOT with QspiRom and a behavioural SPI flash (XT25F64B-like: 9Fh, 03h, 50h,
// 31h, EBh in SPI-Quad with the continuous read mode). Checks the boot result, the capture tick,
// bank 0, a switchable-bank read from the console side, a second boot after a reset of the
// logic while the flash is in the continuous read mode, and silence with an empty flash.
// With CAMERA defined: the image is a camera cartridge (FCh) and GbCamera is attached; a shot is
// taken from the console side (registers, busy, RAM blocked during the shot, the tiles in RAM).
//   make boot / make boot_cam
`timescale 1ns/1ps

module flash_model #(
    parameter real TCO = 7.0  // SCLK fall to data
) (
    input  wire       sclk,
    input  wire       cs_n,
    inout  wire [3:0] io
);
    localparam P_CMD = 0, P_SADDR = 1, P_SDATA = 2, P_ID = 3, P_QADDR = 4, P_QM = 5, P_QDUM = 6, P_QDATA = 7, P_IGN = 8;
    logic [7:0] mem [0:65535];  // 0x400000 ..
    logic       blank = 0;
    int         phase, n;
    logic [7:0] cmd, m, sbyte;
    logic [23:0] addr;
    logic       cont = 0, qnib;
    int         idx;
    logic [3:0] dout = 4'hF, oe = 4'h0;
    int         n_cont_exit = 0;
    for (genvar i = 0; i < 4; i++) begin : g_io
        assign io[i] = oe[i] ? dout[i] : 1'bz;
    end
    pullup (io[0]); pullup (io[1]); pullup (io[2]); pullup (io[3]);

    function automatic logic [7:0] rd(input logic [23:0] a);
        if (blank || a[23:16] != 8'h40) return 8'hFF;
        return mem[a[15:0]];
    endfunction

    always @(negedge cs_n) begin
        n = 0; cmd = 0; addr = 0; m = 0;
        phase = cont ? P_QADDR : P_CMD;
    end
    always @(posedge cs_n) oe <= #(TCO) 4'h0;

    always @(posedge sclk) if (!cs_n) begin
        case (phase)
            P_CMD: begin
                cmd = {cmd[6:0], io[0]}; n++;
                if (n == 8) begin
                    n = 0;
                    case (cmd)
                        8'h9F: begin phase = P_ID; idx = 0; sbyte = 8'h0B; end
                        8'h03: phase = P_SADDR;
                        8'hEB: phase = P_QADDR;
                        default: phase = P_IGN;
                    endcase
                end
            end
            P_SADDR: begin
                addr = {addr[22:0], io[0]}; n++;
                if (n == 24) begin n = 0; phase = P_SDATA; sbyte = rd(addr); end
            end
            P_QADDR: begin
                addr = {addr[19:0], io}; n++;
                if (n == 6) begin n = 0; phase = P_QM; end
            end
            P_QM: begin
                m = {m[3:0], io}; n++;
                if (n == 2) begin
                    n = 0; phase = P_QDUM;
                    if (cont && m[5:4] != 2'b10) n_cont_exit++;
                    cont = m[5:4] == 2'b10;
                end
            end
            P_QDUM: begin
                n++;
                if (n == 4) begin n = 0; phase = P_QDATA; sbyte = rd(addr); qnib = 0; end
            end
            default: ;
        endcase
    end

    always @(negedge sclk) if (!cs_n) begin
        case (phase)
            P_SDATA, P_ID: begin
                dout[1] <= #(TCO) sbyte[7]; oe[1] <= #(TCO) 1'b1;
                sbyte = {sbyte[6:0], 1'b0}; n++;
                if (n == 8) begin
                    n = 0;
                    if (phase == P_ID) begin idx++; sbyte = idx == 1 ? 8'h40 : idx == 2 ? 8'h17 : 8'hFF; end
                    else begin addr++; sbyte = rd(addr); end
                end
            end
            P_QDATA: begin
                dout <= #(TCO) (qnib ? sbyte[3:0] : sbyte[7:4]); oe <= #(TCO) 4'hF;
                if (qnib) begin addr++; sbyte = rd(addr); end
                qnib = !qnib;
            end
            default: ;
        endcase
    end
endmodule

module tb_game_boot;
    logic clk = 0, clk2 = 0, rst = 1;
    always #5 clk = !clk;
    always #2.5 clk2 = !clk2;

    wire        sclk, cs_n;
    wire [3:0]  io, io_o, io_oe;
    for (genvar i = 0; i < 4; i++) begin : g_io
        assign io[i] = io_oe[i] ? io_o[i] : 1'bz;
    end

    logic fl_quad, fl_ready, fl_spiq, fl_cont, fl_want, fl_dval, raw_cs, raw_go, raw_done;
    logic [1:0] fl_cap;
    logic [23:0] fl_addr, fl_daddr;
    logic [7:0] fl_data, raw_tx, raw_rx;
    logic [15:0] a = 16'h0000;
    logic rd_n = 1, wr_n = 1, cs_n_cart = 1;
    logic [7:0] d_in = 8'h00;
    logic [7:0] d_out;
    logic d_oe, d_dir, d_oe_n, rst_drv, rx_ready, tx_valid;
    logic [7:0] tx_data;
    logic rx_valid = 0;
    logic [7:0] rx_data = 0;
    logic [7:0] txq[$];
    always @(posedge clk) if (tx_valid) txq.push_back(tx_data);

`ifdef CAMERA
    logic pclk = 0, cam_frame = 0;
    always #4 pclk = !pclk;
    logic       cam_we, cam_busy, cam_ram_we;
    logic [6:0] cam_wa;
    logic [7:0] cam_wd, cam_reg0, cam_ram_wd, cam_hq;
    logic [11:0] cam_ram_wa;
    logic [15:0] cam_hra;
    GbCamera #(.TIMEOUT(1000000)) u_cam (
        .i_clk(clk), .i_rst(rst),
        .i_pclk(pclk), .i_fb_we(1'b0), .i_fb_wa(14'd0), .i_fb_wd(8'd0), .i_frame(cam_frame),
        .i_reg_we(cam_we), .i_reg_a(cam_wa), .i_reg_d(cam_wd), .o_reg0(cam_reg0), .o_busy(cam_busy),
        .o_ram_we(cam_ram_we), .o_ram_wa(cam_ram_wa), .o_ram_wd(cam_ram_wd), .i_h_ra(cam_hra), .o_h_q(cam_hq));
    localparam bit CAM = 1;
`else
    logic       cam_we, cam_busy = 0, cam_ram_we = 0;
    logic [6:0] cam_wa;
    logic [7:0] cam_wd, cam_reg0 = 0, cam_ram_wd = 0, cam_hq = 0;
    logic [11:0] cam_ram_wa = 0;
    logic [15:0] cam_hra;
    localparam bit CAM = 0;
`endif
    GameCart #(.CLK_HZ(100000000), .CAMERA(CAM)) u_cart (
        .i_clk(clk), .i_rst(rst),
        .i_rx_valid(rx_valid), .i_rx_data(rx_data), .o_rx_ready(rx_ready), .o_tx_valid(tx_valid), .o_tx_data(tx_data), .i_tx_ready(1'b1),
        .i_a(a), .i_rd_n(rd_n), .i_wr_n(wr_n), .i_cs_n(cs_n_cart), .i_phi(1'b0), .i_rst_n(1'b1), .i_d(d_in),
        .o_d(d_out), .o_d_oe(d_oe), .o_d_dir(d_dir), .o_d_oe_n(d_oe_n), .o_rst_drv(rst_drv),
        .o_fl_quad(fl_quad), .i_fl_ready(fl_ready), .o_fl_cap(fl_cap), .o_fl_spiq(fl_spiq), .o_fl_cont(fl_cont),
        .o_fl_want(fl_want), .o_fl_addr(fl_addr), .i_fl_data(fl_data), .i_fl_daddr(fl_daddr), .i_fl_dval(fl_dval),
        .o_raw_cs(raw_cs), .o_raw_go(raw_go), .o_raw_tx(raw_tx), .i_raw_rx(raw_rx), .i_raw_done(raw_done),
        .o_cam_we(cam_we), .o_cam_wa(cam_wa), .o_cam_wd(cam_wd), .i_cam_reg0(cam_reg0), .i_cam_busy(cam_busy),
        .i_cam_ram_we(cam_ram_we), .i_cam_ram_wa(cam_ram_wa), .i_cam_ram_wd(cam_ram_wd), .o_cam_hra(cam_hra), .i_cam_hq(cam_hq));
    QspiRom u_fl (
        .i_clk(clk2), .i_rst(rst),
        .i_quad(fl_quad), .o_ready(fl_ready), .i_cap(fl_cap), .i_spiq(fl_spiq), .i_cont(fl_cont), .i_want(fl_want), .i_addr(fl_addr),
        .o_data(fl_data), .o_daddr(fl_daddr), .o_dval(fl_dval),
        .i_raw_cs(raw_cs), .i_raw_go(raw_go), .i_raw_tx(raw_tx), .o_raw_rx(raw_rx), .o_raw_done(raw_done),
        .o_sclk(sclk), .o_cs_n(cs_n), .o_io(io_o), .o_io_oe(io_oe), .i_io(io));
    flash_model u_flash (.sclk(sclk), .cs_n(cs_n), .io(io));

    int errors = 0;
    task automatic check(input bit ok, input string what);
        if (!ok) begin errors++; $display("FAIL: %s", what); end
        else $display("ok: %s", what);
    endtask

    task automatic boot_and_wait(output time t);
        time t0;
        rst = 1; repeat (20) @(posedge clk); rst = 0; t0 = $time;
        while (u_cart.bt != u_cart.Boot_Done) @(posedge clk);
        t = $time - t0;
    endtask

    task automatic console_read(input logic [15:0] addr, output logic [7:0] d, input bit quiet = 0);
        a = addr; rd_n = 0; cs_n_cart = addr[15:13] != 3'b101;
        repeat (40) @(posedge clk);   // 400 ns: more than the console gives, enough to see the data
        d = d_out;
        if (!quiet || !d_oe) check(d_oe, $sformatf("drives the bus at %04x", addr));
        rd_n = 1; cs_n_cart = 1; repeat (10) @(posedge clk);
    endtask
    task automatic console_write(input logic [15:0] addr, input logic [7:0] v);
        a = addr; d_in = v; cs_n_cart = addr[15:13] != 3'b101;
        repeat (5) @(posedge clk);
        wr_n = 0; repeat (30) @(posedge clk); wr_n = 1;
        repeat (5) @(posedge clk);
        cs_n_cart = 1; repeat (10) @(posedge clk);
    endtask

    task automatic host_send(input logic [7:0] b[]);
        foreach (b[i]) begin
            rx_valid <= 1; rx_data <= b[i];
            do @(posedge clk); while (!rx_ready);
        end
        rx_valid <= 0;
    endtask
    task automatic host_recv(input int n, output logic [7:0] r[]);
        int w = 0;
        while (txq.size() < n && w < 100000) begin @(posedge clk); w++; end
        r = new[n];
        foreach (r[i]) r[i] = txq.size() ? txq.pop_front() : 8'hxx;
    endtask

    initial begin
        time t;
        logic [7:0] r[];
        logic [7:0] sum, d;
        bit bank0_ok;
        for (int i = 0; i < 65536; i++) u_flash.mem[i] = $urandom;
        for (int i = 'h134; i < 'h143; i++) u_flash.mem[i] = "A" + (i % 26);
        u_flash.mem['h147] = CAM ? 8'hFC : 8'h1B;  // camera / MBC5 + RAM + battery
        u_flash.mem['h148] = 8'h07;  // 4 MiB
        u_flash.mem['h149] = 8'h03;  // 32 KiB
        sum = 0;
        for (int i = 'h134; i <= 'h14C; i++) sum = sum - u_flash.mem[i] - 8'd1;
        u_flash.mem['h14D] = sum;

        // 1: a valid image
        boot_and_wait(t);
        $display("boot 1: %0.2f ms, result %0d, good ticks %b, cap %0d", t / 1.0e6, u_cart.bt_res, u_cart.bt_good, fl_cap);
        check(u_cart.bt_res == 2'd1 && u_cart.en, "answering after boot");
        check(u_cart.mapper == (CAM ? 3'd6 : 3'd5) && u_cart.rmask == 9'h0FF && u_cart.xmask == 2'd3 && u_cart.ram_has, "mapper MBC5 (camera), 256 banks, 32 KiB RAM");
        check(u_cart.bt_good != 4'b1111 && u_cart.bt_good != 4'b0000, "some capture ticks fail, some pass");
        bank0_ok = 1;
        for (int i = 0; i < 16384; i++) if (u_cart.rom0[i] != u_flash.mem[i]) bank0_ok = 0;
        check(bank0_ok, "bank 0 in block RAM");
        check(u_cart.ram[123] == 8'hFF && u_cart.ram[32767] == 8'hFF, "RAM filled with FF");
        check(fl_ready && fl_cont && fl_spiq, "flash in SPI-Quad continuous mode");
        check(rx_ready, "host commands taken after boot");
        console_read(16'h0150, d); check(d == u_flash.mem['h0150], $sformatf("bank 0 read %02x", d));
        console_read(16'h4321, d); check(d == u_flash.mem['h4321], $sformatf("bank 1 read %02x", d));
        console_read(16'h7FFE, d); check(d == u_flash.mem['h7FFE], $sformatf("bank 1 read %02x", d));
        check(u_flash.cont, "flash left in the continuous read mode");
        // 2: logic reset with the flash in the continuous read mode
        boot_and_wait(t);
        $display("boot 2: %0.2f ms, result %0d, cont exits %0d", t / 1.0e6, u_cart.bt_res, u_flash.n_cont_exit);
        check(u_cart.bt_res == 2'd1 && u_flash.n_cont_exit == 1, "boots again after a reset in the continuous read mode");
        console_read(16'h5555, d); check(d == u_flash.mem['h5555], $sformatf("bank 1 read %02x", d));

`ifdef CAMERA
        // 4: a shot from the console side: a horizontal ramp v = 2x, gain 1, exposure 1, thresholds 64 / 128 / 192
        for (int y = 0; y < 112; y++) for (int x = 0; x < 128; x++) u_cam.fb[y * 128 + x] = 8'(x * 2);
        console_write(16'h0000, 8'h0A);
        console_write(16'h4000, 8'h10);
        console_write(16'hA001, 8'h04);
        console_write(16'hA002, 8'h10);
        console_write(16'hA003, 8'h00);
        console_write(16'hA004, 8'h00);
        for (int i = 0; i < 16; i++) begin
            console_write(16'hA006 + 16'(i * 3), 8'd64);
            console_write(16'hA007 + 16'(i * 3), 8'd128);
            console_write(16'hA008 + 16'(i * 3), 8'd192);
        end
        console_read(16'hA000, d); check(d[0] == 1'b0, "A000 idle");
        console_read(16'hA001, d); check(d == 8'h00, "other camera registers read 0");
        console_write(16'hA000, 8'h01);
        console_read(16'hA000, d); check(d[0] == 1'b1, "A000 busy after the shot");
        console_write(16'h4000, 8'h00);
        console_read(16'hA100, d); check(d == 8'h00, "RAM reads 0 during the shot");
        console_write(16'h4000, 8'h10);
        cam_frame = !cam_frame;
        do console_read(16'hA000, d, 1); while (d[0]);
        check(1, "shot done");
        console_write(16'h4000, 8'h00);
        console_read(16'hA100, d); check(d == 8'hFF, $sformatf("tile 0: colour 3 (%02x)", d));
        console_read(16'hA101, d); check(d == 8'hFF, $sformatf("tile 0 hi (%02x)", d));
        console_read(16'hA140, d); check(d == 8'h00, $sformatf("tile 4: colour 2 lo (%02x)", d));
        console_read(16'hA141, d); check(d == 8'hFF, $sformatf("tile 4: colour 2 hi (%02x)", d));
        console_read(16'hA18E, d); check(d == 8'hFF, $sformatf("tile 8 row 7: colour 1 lo (%02x)", d));
        console_read(16'hA18F, d); check(d == 8'h00, $sformatf("tile 8 row 7: colour 1 hi (%02x)", d));
        console_read(16'hAEF0, d); check(d == 8'h00, $sformatf("tile 223: colour 0 (%02x)", d));
        console_write(16'hA200, 8'h5A);
        console_read(16'hA200, d); check(d == 8'h5A, "RAM write and read back after the shot");
        txq.delete();
        host_send('{8'h51, 8'h04, 8'h44, 8'h40, 8'h00, 8'h01, 8'h00}); host_recv(1, r);
        check(r[0] == 8'd1, $sformatf("host 'Q' 4: shots %0d", r[0]));
`endif
        txq.delete();
        host_send('{8'h53}); host_recv(64, r);
        check(r[0] == 8'h47 && r[1] == 8'h43 && r[3][0] && r[61][1:0] == 2'd1 && !r[61][3], "host 'S': answering, boot result 1");
        host_send('{8'h45, 8'h00}); host_recv(1, r); check(r[0] == 8'h45, "host 'E' 0");
        host_send('{8'h4B, 8'h00}); host_recv(1, r); check(r[0] == 8'h4B, "host 'K' 0 (quad off)");
        while (fl_ready) @(posedge clk);
        host_send('{8'h46, 8'h01, 8'h00, 8'h03, 8'h00, 8'h9F}); host_recv(4, r);
        check(r[3] == 8'h46 && r[0] == 8'h0B && r[1] == 8'h40 && r[2] == 8'h17, $sformatf("host 'F' 9Fh: %02x %02x %02x %02x", r[0], r[1], r[2], r[3]));
        host_send('{8'h46, 8'h04, 8'h00, 8'h04, 8'h00, 8'h03, 8'h40, 8'h01, 8'h47}); host_recv(5, r);
        check(r[4] == 8'h46 && r[0] == u_flash.mem['h147] && r[1] == u_flash.mem['h148] && r[3] == u_flash.mem['h14A], "host 'F' 03h read");
        host_send('{8'h46, 8'h01, 8'h00, 8'h00, 8'h00, 8'hC7}); host_recv(1, r); check(r[0] == 8'h66, "host 'F' chip erase refused");


        // 3: empty flash (power cycle: the flash leaves the continuous mode)
        u_flash.blank = 1; u_flash.cont = 0;
        boot_and_wait(t);
        $display("boot 3: %0.2f ms, result %0d", t / 1.0e6, u_cart.bt_res);
        check(u_cart.bt_res == 2'd2 && !u_cart.en && !fl_quad, "empty flash: silent");

        if (errors == 0) $display("PASS"); else $display("FAIL (%0d)", errors);
        $finish;
    end
    initial begin #200ms; $display("FAIL: timeout"); $finish; end
endmodule
