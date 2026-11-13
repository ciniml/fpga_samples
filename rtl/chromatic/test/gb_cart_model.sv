// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Game Boy cartridge model for the cartridge reader tests: ROM with a
// generated header, ROM only / MBC1 / MBC2 / MBC3 / MBC5 banking, and
// monitors for every rule the reader must keep (no /CS, whitelisted MBC
// writes only, no RAM enable, no data contention, every line Low while
// the slot is unpowered on a newer board).
`timescale 1ns/1ps
module gb_cart_model #(
    parameter int MBC       = 5,     // 0 ROM only, 1 MBC1, 2 MBC2, 3 MBC3, 5 MBC5
    parameter int ROM_CODE  = 5,     // header 0x148: 32 KiB << ROM_CODE
    parameter bit MBC1M     = 0,     // MBC1 multicart wiring (bank bits 4:0 -> 3:0, reg2 -> bits 5:4)
    parameter bit BAD_HDR   = 0      // corrupt the header checksum
) (
    input  logic        clk,         // monitor clock (the design clock)
    input  logic        rst,
    input  logic        legacy,      // board type of the test
    input  logic        pwr_en,      // CART_PWR_EN
    input  logic        ctrl_oe,
    input  logic        drive_low_expected,
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
    output int          n_violations
);
    localparam int ROM_BYTES = 32768 << ROM_CODE;
    localparam int BANKS     = ROM_BYTES / 16384;

    logic [7:0] rom [ROM_BYTES];
    logic [8:0] bank_lo;    // MBC1: 5 bits, MBC2: 4, MBC3: 7, MBC5: 9
    logic [1:0] reg2;
    logic       mode;
    logic       ram_en;

    function automatic logic [7:0] fill(int i);
        logic [31:0] x;
        x = i * 32'h9E3779B1;
        return x[31:24] ^ x[15:8] ^ 8'(i >> 14);
    endfunction

    initial begin
        int unsigned sum;
        logic [7:0] x;
        string title;
        for (int i = 0; i < ROM_BYTES; i++) rom[i] = fill(i);
        // header
        title = $sformatf("TESTCART MBC%0d", MBC);
        for (int i = 0; i < 16; i++) rom[16'h134 + i] = (i < title.len()) ? title[i] : 8'h00;
        rom[16'h143] = 8'h80;
        case (MBC)
            0: rom[16'h147] = 8'h00;
            1: rom[16'h147] = 8'h01;
            2: rom[16'h147] = 8'h05;
            3: rom[16'h147] = 8'h11;
            5: rom[16'h147] = 8'h19;
            default: rom[16'h147] = 8'h00;
        endcase
        rom[16'h148] = 8'(ROM_CODE);
        rom[16'h149] = 8'h00;
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
    end

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
                5: b = bank_lo;
                default: b = 1;
            endcase
        end
        b = b % BANKS;
        return b * 16384 + addr[13:0];
    endfunction

    wire cart_drives = !rd_n && !a[15];
    assign d_in = dir_e ? (cart_drives ? rom[map(a)] : 8'hFF) : 8'hFF;

    // ---- monitors ----
    logic wr_n_q;
    int   cyc;
    logic [1:0] dl_q;
    wire  on = ctrl_oe || legacy;
    function automatic bit allowed(logic [15:0] ad, logic [7:0] dt);
        return (ad == 16'h0000 && dt == 8'h00) || ad == 16'h2000 || ad == 16'h2100 ||
               ad == 16'h3000 || ad == 16'h4000 || ad == 16'h6000;
    endfunction
    task automatic violation(string s);
        n_violations++;
        $display("[cart] VIOLATION at %0t: %s", $time, s);
    endtask

    initial begin
        n_writes = 0;
        n_violations = 0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            bank_lo <= 9'd1;
            reg2    <= 0;
            mode    <= 0;
            ram_en  <= 0;
            wr_n_q  <= 1;
            dl_q    <= 0;
            cyc     <= 0;
        end else begin
            cyc    <= cyc + 1;
            wr_n_q <= wr_n;
            dl_q   <= {dl_q[0], drive_low_expected};
            if (d_oe && dir_e) violation("FPGA drives D while the shifter drives the FPGA side");
            if (on && !cs_n) violation("/CS asserted with the slot powered");
            if (!legacy && !pwr_en && drive_low_expected && dl_q == 2'b11 && cyc > 64 &&
                (a != 0 || clk_phi || rd_n || wr_n || cs_n || !rst_low || !d_oe || d_out != 0 || dir_e))
                violation($sformatf("slot unpowered but a line is not Low (a=%h phi=%b rd=%b wr=%b cs=%b rst_low=%b oe=%b d=%h dir=%b)",
                                    a, clk_phi, rd_n, wr_n, cs_n, rst_low, d_oe, d_out, dir_e));
            if (!wr_n && !rd_n && on) violation("/WR and /RD Low together");
            if (!wr_n && (dir_e || !d_oe) && on) violation("/WR Low without the FPGA driving D");
            // latch on the /WR rising edge (as MBCs do)
            if (!wr_n_q && wr_n && on) begin
                n_writes <= n_writes + 1;
                if (!allowed(a, d_out)) violation($sformatf("write %h <- %h is not whitelisted", a, d_out));
                if (a[15]) violation($sformatf("write to %h (not an MBC register)", a));
                if (a < 16'h2000 && d_out[3:0] == 4'hA) violation("RAM enable written");
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
                        3: begin
                            case (a[14:13])
                                2'd0: ram_en <= d_out[3:0] == 4'hA;
                                2'd1: bank_lo <= {2'd0, d_out[6:0]};
                                default: ;
                            endcase
                        end
                        5: begin
                            case (a[14:12])
                                3'd0, 3'd1: ram_en <= d_out[3:0] == 4'hA;
                                3'd2: bank_lo[7:0] <= d_out;
                                3'd3: bank_lo[8] <= d_out[0];
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
