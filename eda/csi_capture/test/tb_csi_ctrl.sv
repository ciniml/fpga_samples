// csi_ctrl + i2c_reg16 + imx219_init_rom against a CCI (16-bit address)
// I2C slave model: the power-up init must write every ROM entry, and the
// UART commands 'P', 'W', 'R', 'S' must answer as documented.
// Run: ./run_ctrl.sh (Verilator --binary --timing)
`timescale 1ns/1ps
module tb_csi_ctrl;
    logic clk = 0, rst = 1;
    always #10 clk = ~clk;                  // 50 MHz
    localparam int BAUD_DIV = 8;            // fast UART for simulation

    // ---- I2C bus (wired-AND) ----
    wire scl_oe, sda_oe;
    logic slv_sda_oe = 0;
    wire scl = !scl_oe;
    wire sda = !(sda_oe || slv_sda_oe);

    // ---- CCI slave model (7-bit address 0x10) ----
    logic [7:0] regs [0:65535];
    int nwrites = 0;
    initial begin
        for (int i = 0; i < 65536; i++) regs[i] = 8'h00;
        regs[16'h0000] = 8'h02; regs[16'h0001] = 8'h19;
    end
    typedef enum {SI, SRX, SACK, STX, STXACK} sst_t;
    sst_t st = SI;
    int bitc = 0, n = 0; logic rd = 0; logic [7:0] sh; logic [15:0] a;
    always @(negedge sda) if (scl) begin st = SRX; bitc = 0; n = 0; slv_sda_oe = 0; end      // (repeated) START
    always @(posedge sda) if (scl) begin st = SI; slv_sda_oe = 0; end                        // STOP
    always @(posedge scl) if (st == SRX) begin sh = {sh[6:0], sda}; bitc++; end
    always @(negedge scl) begin
        case (st)
            SRX: if (bitc == 8) begin
                if (n == 0) begin
                    if (sh[7:1] == 7'h10) begin rd = sh[0]; #50 slv_sda_oe = 1; st = SACK; end
                    else st = SI;
                end else begin
                    if (n == 1) a[15:8] = sh;
                    else if (n == 2) a[7:0] = sh;
                    else begin regs[a] = sh; nwrites++; a++; end
                    #50 slv_sda_oe = 1; st = SACK;
                end
            end
            SACK: begin
                #50 slv_sda_oe = 0;
                n++;
                if (n == 1 && rd) begin
                    sh = regs[a]; bitc = 0; slv_sda_oe = !sh[7]; st = STX;
                end else begin
                    bitc = 0; st = SRX;
                end
            end
            STX: begin
                bitc++;
                #50 if (bitc < 8) slv_sda_oe = !sh[7 - bitc]; else begin slv_sda_oe = 0; st = STXACK; end
            end
            default: ;
        endcase
    end

    // ---- UART host model ----
    logic rxd = 1; wire txd;
    task automatic send(input logic [7:0] b);
        rxd = 0; repeat (BAUD_DIV) @(posedge clk);
        for (int i = 0; i < 8; i++) begin rxd = b[i]; repeat (BAUD_DIV) @(posedge clk); end
        rxd = 1; repeat (BAUD_DIV) @(posedge clk);
    endtask
    // background receiver: the reply may start while send() is still in its stop bit
    logic [7:0] rxq [$];
    initial forever begin
        logic [7:0] b;
        @(negedge txd);
        repeat (BAUD_DIV / 2) @(posedge clk);
        for (int i = 0; i < 8; i++) begin repeat (BAUD_DIV) @(posedge clk); b[i] = txd; end
        repeat (BAUD_DIV) @(posedge clk);
        rxq.push_back(b);
    end
    task automatic recv(output logic [7:0] b);
        wait (rxq.size() != 0);
        b = rxq.pop_front();
    endtask

    logic [31:0] snap [0:24];
    logic snap_tgl, snap_ack = 0; logic [4:0] snap_idx; logic [31:0] snap_data;
    always @(posedge clk) begin snap_ack <= snap_tgl; snap_data <= 32'hA0000000 | snap_idx; end
    logic init_busy;
    csi_ctrl #(.CLOCK_HZ(50_000_000), .BAUD_DIVIDER(BAUD_DIV), .BOOT_CYCLES(2000), .MS_CYCLES(500)) dut (
        .clk(clk), .rst(rst), .uart_rxd(rxd), .uart_txd(txd),
        .o_scl_oe(scl_oe), .o_sda_oe(sda_oe), .i_scl(scl), .i_sda(sda),
        .o_ofs0(), .o_ofs1(), .o_inv(), .o_init_busy(init_busy),
        .o_snap_tgl(snap_tgl), .i_snap_ack(snap_ack), .o_snap_idx(snap_idx), .i_snap_data(snap_data),
        .o_cap_tgl(), .o_cap_mode(), .o_cap_raddr(), .i_cap_rdata('0),
        .o_log_tgl(), .o_log_at_fs(), .o_log_raddr(), .i_log_rdata('0));

    initial begin #200ms; $fatal(1, "timeout: nwrites %0d state %0d", nwrites, dut.st); end
    always @(nwrites) if (nwrites % 10 == 0) $display("[%0t] %0d register writes", $time, nwrites);
    initial begin
        logic [7:0] r0, r1, r2;
        int nrom = 0;
        repeat (4) @(posedge clk); rst = 0;
        for (int i = 0; i < 128; i++) begin
            logic [23:0] e;
            ridx = i; #1;
            e = rent;
            if (e[23:8] == 16'hFFFE) break;
            if (e[23:8] != 16'hFFFF) nrom++;
        end
        // the auto init runs ~20 ms after reset
        @(negedge init_busy);   // busy from reset (boot wait) through the init
        if (nwrites != nrom) $fatal(1, "init wrote %0d registers, ROM has %0d", nwrites, nrom);
        if (regs[16'h030D] != 8'h39 || regs[16'h0100] != 8'h01 || regs[16'h016C] != 8'h02 || regs[16'h016D] != 8'h80)
            $fatal(1, "init register values wrong");
        $display("auto init: %0d writes OK", nwrites);
        send("P"); recv(r0); recv(r1);
        if (r0 != "p") $fatal(1, "P -> %02h", r0);
        send("W"); send(8'h01); send(8'h72); send(8'h5A); recv(r0); recv(r1);
        if (r0 != "w" || r1 != 0 || regs[16'h0172] != 8'h5A) $fatal(1, "W -> %02h %02h reg %02h", r0, r1, regs[16'h0172]);
        send("R"); send(8'h00); send(8'h00); recv(r0); recv(r1); recv(r2);
        if (r0 != "r" || r1 != 8'h02 || r2 != 0) $fatal(1, "R -> %02h %02h %02h", r0, r1, r2);
        send("R"); send(8'h00); send(8'h01); recv(r0); recv(r1); recv(r2);
        if (r1 != 8'h19) $fatal(1, "R 0001 -> %02h", r1);
        send("D"); send(8'h11); recv(r0);                       // wrong address: NACK
        send("R"); send(8'h00); send(8'h00); recv(r0); recv(r1); recv(r2);
        if (r2 != 1) $fatal(1, "no NACK from a wrong address");
        send("D"); send(8'h10); recv(r0);
        send("S"); recv(r0);
        if (r0 != "S") $fatal(1, "S -> %02h", r0);
        for (int i = 0; i < 25; i++) begin
            logic [31:0] v;
            recv(v[7:0]); recv(v[15:8]); recv(v[23:16]); recv(v[31:24]);
            if (v != (32'hA0000000 | i)) $fatal(1, "S word %0d = %08h", i, v);
        end
        $display("tb_csi_ctrl: PASS");
        $finish;
    end
    logic [6:0] ridx; logic [23:0] rent;
    imx219_init_rom trom (.i_idx(ridx), .o_entry(rent));
endmodule
