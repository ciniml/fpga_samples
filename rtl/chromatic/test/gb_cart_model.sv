// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Game Boy cartridge model for the cartridge reader tests: ROM with a
// generated header, ROM only / MBC1 / MBC2 / MBC3 / MBC5 banking, cartridge
// RAM (MBC2: 512 x 4 bit inside the MBC, its upper nibble reads as noise),
// MBC7 with a 93LC56 / 93LC66 serial EEPROM (any command but READ is a violation),
// a 2 MiB AMD command-set flash behind MBC5 (FLASH; SST39VF1681-like ID, 64 KiB
// erase blocks; chip erase and programming bits that are not erased are violations),
// and monitors for every rule the reader must keep (whitelisted MBC writes
// only, never a write with /CS or to 0xA000-0xBFFF, /CS only for RAM reads,
// RAM disabled before the power goes down, no data contention, every line
// Low while the slot is unpowered on a newer board).
`timescale 1ns/1ps
module gb_cart_model #(
    parameter int MBC       = 5,     // 0 ROM only, 1 MBC1, 2 MBC2, 3 MBC3, 5 MBC5, 7 MBC7
    parameter int ROM_CODE  = 5,     // header 0x148: 32 KiB << ROM_CODE
    parameter bit MBC1M     = 0,     // MBC1 multicart wiring (bank bits 4:0 -> 3:0, reg2 -> bits 5:4)
    parameter bit BAD_HDR   = 0,     // corrupt the header checksum
    parameter int RAM_CODE  = 0,     // header 0x149 (0 none, 1 2 KiB, 2 8 KiB, 3 32 KiB, 4 128 KiB, 5 64 KiB)
    parameter int EEP_WORDS = 128,   // MBC7: 128 (93LC56) or 256 (93LC66)
    parameter bit FLASH     = 0      // MBC5 flash cartridge (2 MiB, ROM_CODE gives the image in it)
) (
    input  logic        clk,         // monitor clock (the design clock)
    input  logic        rst,
    input  logic        legacy,      // board type of the test
    input  logic        pwr_en,      // CART_PWR_EN
    input  logic        ctrl_oe,
    input  logic        drive_low_expected,
    input  logic        ram_mode,    // the reader's RAM mode (a RAM enable is allowed only then)
    input  logic        flash_mode,  // the reader's flash mode (any write below 0x8000 allowed then)
    input  logic [15:0] a,
    input  logic        clk_phi,
    input  logic        rd_n,
    input  logic        wr_n,
    input  logic        cs_n,
    input  logic        rst_low,
    input  logic        dir_e,       // 1: cartridge -> FPGA
    input  logic [7:0]  d_out,       // FPGA data
    input  logic        d_oe,
    output logic [7:0]  d_in,        // data seen by the FPGA
    output int          n_writes,
    output int          n_violations,
    output int          n_ram_reads,  // bus reads that returned cartridge RAM
    output logic        ram_enabled
);
    localparam int ROM_BYTES = 32768 << ROM_CODE;
    localparam int ROM_ALLOC = FLASH ? 2097152 : ROM_BYTES;
    localparam int BANKS     = ROM_ALLOC / 16384;
    localparam int RAM_BYTES = MBC == 7 ? EEP_WORDS * 2 : MBC == 2 ? 512 :
                               RAM_CODE == 1 ? 2048 : RAM_CODE == 2 ? 8192 : RAM_CODE == 3 ? 32768 :
                               RAM_CODE == 4 ? 131072 : RAM_CODE == 5 ? 65536 : 0;
    localparam int RAM_ALLOC = RAM_BYTES == 0 ? 1 : RAM_BYTES;

    logic [7:0] rom [ROM_ALLOC];
    logic [8:0] bank_lo;    // MBC1: 5 bits, MBC2: 4, MBC3: 7, MBC5: 9
    logic [1:0] reg2;
    logic       mode;
    logic       ram_en;
    logic [3:0] ram_bank;   // MBC3 / MBC5 (MBC1 uses reg2 in mode 1)
    logic [7:0] ram [RAM_ALLOC];
    assign ram_enabled = ram_en;

    function automatic logic [7:0] fill(int i);
        logic [31:0] x;
        x = i * 32'h9E3779B1;
        return x[31:24] ^ x[15:8] ^ 8'(i >> 14);
    endfunction

    initial begin
        int unsigned sum;
        logic [7:0] x;
        string title;
        for (int i = 0; i < ROM_ALLOC; i++) rom[i] = i < ROM_BYTES ? fill(i) : 8'hFF;
        // header
        title = $sformatf("TESTCART MBC%0d", MBC);
        for (int i = 0; i < 16; i++) rom[16'h134 + i] = (i < title.len()) ? title[i] : 8'h00;
        rom[16'h143] = 8'h80;
        case (MBC)
            0: rom[16'h147] = 8'h00;
            1: rom[16'h147] = RAM_CODE != 0 ? 8'h03 : 8'h01;
            2: rom[16'h147] = 8'h06;
            3: rom[16'h147] = RAM_CODE != 0 ? 8'h13 : 8'h11;
            5: rom[16'h147] = RAM_CODE != 0 ? 8'h1B : 8'h19;
            7: rom[16'h147] = 8'h22;
            default: rom[16'h147] = 8'h00;
        endcase
        rom[16'h148] = 8'(ROM_CODE);
        rom[16'h149] = (MBC == 2 || MBC == 7) ? 8'h00 : 8'(RAM_CODE);
        for (int i = 0; i < RAM_ALLOC; i++) ram[i] = fill(i * 7 + 12345) ^ 8'h5A;
        x = 0;
        for (int i = 16'h134; i <= 16'h14C; i++) x = x - rom[i] - 8'd1;
        rom[16'h14D] = BAD_HDR ? ~x : x;
        if (MBC1M) begin
            // every 256 KiB game of the multicart carries its own header copy (logo area 0x104..)
            for (int g = 1; g < ROM_BYTES / 262144; g++)
                for (int i = 16'h100; i < 16'h150; i++) rom[g * 262144 + i] = rom[i];
        end
        sum = 0;
        for (int i = 0; i < ROM_BYTES; i++) if (i != 16'h14E && i != 16'h14F) sum += rom[i];
        rom[16'h14E] = sum[15:8];
        rom[16'h14F] = sum[7:0];
        // +romout=<file>: the expected image, for comparing a dump byte by byte
        if ($value$plusargs("romout=%s", title)) begin
            int fd;
            fd = $fopen(title, "wb");
            for (int i = 0; i < ROM_BYTES; i++) $fwrite(fd, "%c", rom[i]);
            $fclose(fd);
        end
        // +ramout=<file>: the expected save image (MBC2: low nibble, upper nibble 1s)
        if ($value$plusargs("ramout=%s", title)) begin
            int fd;
            fd = $fopen(title, "wb");
            for (int i = 0; i < RAM_BYTES; i++) $fwrite(fd, "%c", MBC == 2 ? (ram[i] | 8'hF0) : ram[i]);
            $fclose(fd);
        end
    end

    function automatic int ram_addr(logic [15:0] addr);
        int b;
        if (MBC == 2) return int'(addr[8:0]);  // 512 nibbles, mirrored over 0xA000-0xBFFF
        case (MBC)
            1: b = mode ? int'(reg2) : 0;
            3, 5: b = int'(ram_bank);
            default: b = 0;
        endcase
        return (b * 8192 + int'(addr[12:0])) % RAM_ALLOC;
    endfunction
    // ---- MBC7: RAM enable 2 and the 93LCxx (bit-banged through Ax8x) ----
    logic       access2;
    logic       e_cs, e_clk, e_di, e_do;
    logic [2:0] e_state;              // 0 idle, 1 command, 2 data out
    logic [15:0] e_sr;
    logic [4:0] e_bits;
    logic [7:0] e_addr;
    int         n_eep_reads;
    wire  mbc7_on  = MBC == 7 && ram_en && access2;
    wire  eep_reg  = a[15:12] == 4'hA && a[7:4] == 4'h8;
    wire [7:0] mbc7_q = !mbc7_on ? 8'hFF : eep_reg ? {e_cs, e_clk, 4'b0000, e_di, e_do} :
                        a[7:4] == 4'h6 ? 8'h00 : 8'hFF;

    wire ram_sel = !cs_n && a[15:13] == 3'b101;
    wire ram_hit = ram_sel && !rd_n && ram_en && RAM_BYTES != 0 && MBC != 7;
    logic [3:0] noise;

    // ---- banking ----
    function automatic int unsigned map(logic [15:0] addr);
        int unsigned b;
        if (!addr[14]) begin
            b = 0;
            if (MBC == 1 && mode) b = MBC1M ? (int'(reg2) << 4) : (int'(reg2) << 5);
        end else begin
            case (MBC)
                0: b = 1;
                1: begin
                    int unsigned b5;
                    b5 = bank_lo[4:0] == 0 ? 1 : int'(bank_lo[4:0]);
                    b = MBC1M ? ((int'(reg2) << 4) | (b5 & 15)) : ((int'(reg2) << 5) | b5);
                end
                2: b = bank_lo[3:0] == 0 ? 1 : bank_lo[3:0];
                3: b = bank_lo[6:0] == 0 ? 1 : bank_lo[6:0];
                7: b = bank_lo[6:0];
                5: b = bank_lo;
                default: b = 1;
            endcase
        end
        b = b % BANKS;
        return b * 16384 + addr[13:0];
    endfunction

    wire cart_drives = !rd_n && !a[15];
    // ---- flash: AMD command state ----
    logic [2:0] f_st;       // 0 read, 1 AA seen, 2 55 seen, 3 80 seen, 4 80 AA, 5 80 AA 55, 6 program
    logic       f_id;
    int         f_busy;     // clocks left
    logic [7:0] f_busy_q;   // status read while busy
    int         f_busy_addr;
    int         n_flash_prog, n_flash_erase;
    function automatic int faddr(logic [15:0] ad);
        return ad[14] ? (int'(bank_lo) % BANKS) * 16384 + int'(ad[13:0]) : int'(ad[13:0]);
    endfunction
    wire [7:0] flash_q = f_id ? (a[7:0] == 8'h00 ? 8'hBF : a[7:0] == 8'h01 ? 8'hC8 : 8'hFF) :
                         f_busy > 0 ? f_busy_q : rom[map(a)];
    wire [7:0] ram_q = ram[ram_addr(a)];
    assign d_in = !dir_e ? 8'hFF :
                  cart_drives ? (FLASH ? flash_q : rom[map(a)]) :
                  ram_hit ? (MBC == 2 ? {noise, ram_q[3:0]} : ram_q) :
                  (MBC == 7 && ram_sel && !rd_n) ? mbc7_q : 8'hFF;

    // ---- monitors ----
    logic wr_n_q;
    int   cyc;
    logic [1:0] dl_q;
    logic on_q, rd_n_q, cs_n_q;
    wire  on = ctrl_oe || legacy;
    // the reader's whitelist (0x0A only in RAM mode, which the model does not see: the
    // test checks the mode separately)
    function automatic bit allowed(logic [15:0] ad, logic [7:0] dt);
        return (ad == 16'h0000 && (dt == 8'h00 || dt == 8'h0A)) || ad == 16'h2000 || ad == 16'h2100 ||
               ad == 16'h3000 || (ad == 16'h4000 && dt < 8'h10) || ad == 16'h6000 ||
               (MBC == 7 && ((ad == 16'h4000 && dt == 8'h40) || (ad == 16'hA080 && (dt & 8'h3D) == 0))) ||
               (FLASH && ad == 16'h0000 && dt == 8'hF0);  // the reader's own flash reset
    endfunction
    // the one write cycle that may carry /CS: the MBC7 EEPROM register, in RAM mode
    wire cs_write_ok = MBC == 7 && a == 16'hA080 && ram_mode;
    final begin
        string fn;
        if (FLASH && $value$plusargs("flashout=%s", fn)) begin
            int fd;
            fd = $fopen(fn, "wb");
            for (int i = 0; i < ROM_ALLOC; i++) $fwrite(fd, "%c", rom[i]);
            $fclose(fd);
        end
    end
    task automatic violation(string s);
        n_violations++;
        $display("[cart] VIOLATION at %0t: %s", $time, s);
    endtask

    initial begin
        n_writes = 0;
        n_violations = 0;
        n_ram_reads = 0;
        n_eep_reads = 0;
        n_flash_prog = 0;
        n_flash_erase = 0;
    end

    always @(posedge clk) begin    // not always_ff: the counters are also cleared by the initial block
        if (rst) begin
            bank_lo <= 9'd1;
            reg2    <= 0;
            mode    <= 0;
            ram_en  <= 0;
            ram_bank <= 0;
            noise   <= 0;
            access2 <= 0;
            f_st <= 0; f_id <= 0; f_busy <= 0; f_busy_q <= 0;
            e_cs <= 0; e_clk <= 0; e_di <= 0; e_do <= 1;
            e_state <= 0; e_sr <= 0; e_bits <= 0; e_addr <= 0;
            on_q    <= 0;
            rd_n_q  <= 1;
            cs_n_q  <= 1;
            wr_n_q  <= 1;
            dl_q    <= 0;
            cyc     <= 0;
        end else begin
            cyc    <= cyc + 1;
            wr_n_q <= wr_n;
            rd_n_q <= rd_n;
            cs_n_q <= cs_n;
            on_q   <= on;
            noise  <= noise + 4'd5;
            if (f_busy > 0) f_busy <= f_busy - 1;
            dl_q   <= {dl_q[0], drive_low_expected};
            if (d_oe && dir_e) violation("FPGA drives D while the shifter drives the FPGA side");
            if (on && !cs_n && !wr_n && !cs_write_ok) violation("/CS and /WR Low together");
            if (on && !cs_n && a[15:13] != 3'b101) violation($sformatf("/CS Low outside 0xA000-0xBFFF (a=%h)", a));
            if (on && !cs_n && rd_n && !cs_write_ok) violation("/CS Low without /RD");
            if (on_q && !on && ram_en) violation("slot powered down with the cartridge RAM enabled");
            // count a RAM read once per /RD pulse, at its end
            if (on && !rd_n_q && rd_n && !cs_n_q && a[15:13] == 3'b101 && ram_en) n_ram_reads <= n_ram_reads + 1;
            if (!legacy && !pwr_en && drive_low_expected && dl_q == 2'b11 && cyc > 64 &&
                (a != 0 || clk_phi || rd_n || wr_n || cs_n || !rst_low || !d_oe || d_out != 0 || dir_e))
                violation($sformatf("slot unpowered but a line is not Low (a=%h phi=%b rd=%b wr=%b cs=%b rst_low=%b oe=%b d=%h dir=%b)",
                                    a, clk_phi, rd_n, wr_n, cs_n, rst_low, d_oe, d_out, dir_e));
            if (!wr_n && !rd_n && on) violation("/WR and /RD Low together");
            if (!wr_n && (dir_e || !d_oe) && on) violation("/WR Low without the FPGA driving D");
            // latch on the /WR rising edge (as MBCs do)
            if (!wr_n_q && wr_n && on) begin
                n_writes <= n_writes + 1;
                if (!allowed(a, d_out) && !(FLASH && flash_mode && !a[15])) violation($sformatf("write %h <- %h is not whitelisted", a, d_out));
                if (!a[15] && !(FLASH && flash_mode) && f_st != 0) violation("flash command state changed outside flash mode");
                if (FLASH && !a[15]) begin
                    // AMD command decode (the flash sees every write below 0x8000)
                    if (f_busy > 0) ;
                    else if (d_out == 8'hF0 && f_st != 6) begin f_st <= 0; f_id <= 0; end  // in a program cycle F0 is data
                    else case (f_st)
                        0: if (faddr(a) == 'hAAA && d_out == 8'hAA) f_st <= 1;
                        1: f_st <= (faddr(a) == 'h555 && d_out == 8'h55) ? 2 : 0;
                        2: begin
                            f_st <= 0;
                            if (faddr(a) == 'hAAA && d_out == 8'h90) f_id <= 1;
                            else if (faddr(a) == 'hAAA && d_out == 8'hA0) f_st <= 6;
                            else if (faddr(a) == 'hAAA && d_out == 8'h80) f_st <= 3;
                        end
                        3: f_st <= (faddr(a) == 'hAAA && d_out == 8'hAA) ? 4 : 0;
                        4: f_st <= (faddr(a) == 'h555 && d_out == 8'h55) ? 5 : 0;
                        5: begin
                            f_st <= 0;
                            if (d_out == 8'h10) violation("flash CHIP ERASE");
                            else if (d_out == 8'h30 || d_out == 8'h50) begin
                                int b0;
                                b0 = (faddr(a) / 65536) * 65536;
                                for (int i = 0; i < 65536; i++) rom[b0 + i] = 8'hFF;
                                f_busy <= 3000; f_busy_q <= 8'h00; n_flash_erase <= n_flash_erase + 1;
                            end
                        end
                        6: begin
                            int fa;
                            fa = faddr(a);
                            f_st <= 0;
                            if ((rom[fa] & d_out) != d_out)
                                violation($sformatf("flash program %06h <- %02h over %02h (not erased)", fa, d_out, rom[fa]));
                            rom[fa] = rom[fa] & d_out;
                            f_busy <= 200; f_busy_q <= {~d_out[7], 7'h00}; n_flash_prog <= n_flash_prog + 1;
                        end
                        default: f_st <= 0;
                    endcase
                end
                if (a == 16'h0000 && d_out == 8'h0A && !ram_mode && !(FLASH && flash_mode)) violation("RAM enable outside RAM mode");
                if (a[15] && !cs_write_ok) violation($sformatf("write to %h (not an MBC register)", a));
                if (a[15] && cs_write_ok && cs_n) violation("EEPROM register write without /CS");
                if (MBC == 7 && a == 16'hA080 && !cs_n && mbc7_on) begin
                    // 93LCxx: CS rising resets, DI sampled on CLK rising, DO changes on CLK rising
                    logic ncs, nclk, ndi;
                    ncs = d_out[7]; nclk = d_out[6]; ndi = d_out[1];
                    if (!e_cs && ncs) e_state <= 0;
                    if (!ncs) e_state <= 0;
                    if (ncs && !e_clk && nclk) begin
                        case (e_state)
                            0: if (ndi) begin e_state <= 1; e_bits <= 0; e_sr <= 0; end
                            1: begin
                                e_sr   <= {e_sr[14:0], ndi};
                                e_bits <= e_bits + 1;
                                if (e_bits == 9) begin
                                    // 10 bits after the start bit: opcode (2) + address (8)
                                    if (e_sr[8:7] != 2'b10)
                                        violation($sformatf("EEPROM command %b (only READ = 10 is allowed)", {e_sr[8:0], ndi}));
                                    e_addr  <= {e_sr[6:0], ndi};
                                    e_state <= 2;
                                    e_bits  <= 16;
                                    e_do    <= 1'b0;   // dummy 0
                                    begin
                                        int w;
                                        w = int'({e_sr[6:0], ndi}) % EEP_WORDS;
                                        e_sr <= {ram[w * 2], ram[w * 2 + 1]};
                                    end
                                    n_eep_reads <= n_eep_reads + 1;
                                end
                            end
                            2: begin
                                e_do   <= e_sr[15];
                                e_sr   <= {e_sr[14:0], 1'b0};
                                e_bits <= e_bits - 1;
                                if (e_bits == 1) e_state <= 0;
                            end
                            default: e_state <= 0;
                        endcase
                    end
                    e_cs <= ncs; e_clk <= nclk; e_di <= ndi;
                end
                if (!a[15]) begin
                    case (MBC)
                        1: begin
                            case (a[14:13])
                                2'd0: ram_en <= d_out[3:0] == 4'hA;
                                2'd1: bank_lo <= {4'd0, d_out[4:0]};
                                2'd2: reg2 <= d_out[1:0];
                                2'd3: mode <= d_out[0];
                            endcase
                        end
                        2: if (!a[14]) begin
                            if (a[8]) bank_lo <= {5'd0, d_out[3:0]};
                            else ram_en <= d_out[3:0] == 4'hA;
                        end
                        7: begin
                            case (a[14:13])
                                2'd0: ram_en <= d_out == 8'h0A;
                                2'd1: bank_lo <= {2'd0, d_out[6:0]};
                                2'd2: access2 <= d_out == 8'h40;
                                default: ;
                            endcase
                        end
                        3: begin
                            case (a[14:13])
                                2'd0: ram_en <= d_out[3:0] == 4'hA;
                                2'd1: bank_lo <= {2'd0, d_out[6:0]};
                                2'd2: ram_bank <= d_out[3:0];
                                default: ;
                            endcase
                        end
                        5: begin
                            case (a[14:12])
                                3'd0, 3'd1: ram_en <= d_out[3:0] == 4'hA;
                                3'd2: bank_lo[7:0] <= d_out;
                                3'd3: bank_lo[8] <= d_out[0];
                                3'd4, 3'd5: ram_bank <= d_out[3:0];
                                default: ;
                            endcase
                        end
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule
