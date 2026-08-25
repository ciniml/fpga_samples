// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
//
// Behavioural USB 2.0 host bus-functional model for `veryl test`.
//
// Talks to the PHY's serial side: 8 line samples per 60 MHz clock. In HS
// mode one sample = one bit (480 Mbps); in FS mode only sample 0 of each
// clock is meaningful and a bit lasts 5 clocks (LS: 40). The BFM
// encodes / decodes SYNC, NRZI, bit stuffing and EOP itself so that the
// DUT PHY is exercised end to end, and offers token / data / handshake
// helpers for driving a device core.
//
// All packet payloads travel through the module-level tx_buf/rx_buf
// arrays (Verilator-friendly; avoids dynamic arrays as task arguments).
`timescale 1ns/1ps
module usb_host_bfm (
    input  logic       clk,
    input  logic       hs,       // 1: HS bit rate, 0: FS
    input  logic       ls,       // 1: LS bit rate / polarity (FS timing base x8)
    // to DUT receiver (already merged with bus idle level)
    output logic [7:0] dp_o,
    output logic [7:0] dn_o,
    output logic       drive,
    // from DUT transmitter
    input  logic [7:0] dp_i,
    input  logic [7:0] dn_i,
    input  logic       oe_i
);
    // ------------------------------------------------------------------
    // Buffers / statistics
    // ------------------------------------------------------------------
    byte tx_buf[0:1023];
    int  tx_len;
    byte rx_buf[0:1023];
    int  rx_len;
    bit  rx_ok;          // packet decoded without error
    bit  rx_timeout;
    int  clocks_per_bit;
    int  errors;

    // Encoded line bit stream (levels: 1 = J, and SE0 flags).
    bit  lv[0:16383];
    bit  se[0:16383];
    int  nbits;

    // Raw TX registers
    logic [7:0] tx_dp, tx_dn;
    logic       tx_drive;
    initial begin
        tx_drive = 0; tx_dp = 8'hFF; tx_dn = 8'h00;
        errors = 0; rx_ok = 0; rx_timeout = 0; tx_len = 0; rx_len = 0;
    end
    always_comb clocks_per_bit = ls ? 40 : 5;

    // Bus idle level when nobody drives: FS/HS-capable device pulls D+
    // (J); LS device pulls D-; HS idle is SE0.
    always_comb begin
        drive = tx_drive;
        if (tx_drive) begin
            dp_o = tx_dp; dn_o = tx_dn;
        end else if (oe_i) begin
            dp_o = dp_i; dn_o = dn_i;   // device drives the shared bus
        end else if (hs) begin
            dp_o = 8'h00; dn_o = 8'h00;
        end else if (ls) begin
            dp_o = 8'h00; dn_o = 8'hFF;
        end else begin
            dp_o = 8'hFF; dn_o = 8'h00;
        end
    end

    function automatic logic [4:0] crc5(input logic [10:0] tok);
        logic [4:0] c; logic fb;
        c = 5'h1F;
        for (int i = 0; i < 11; i++) begin
            fb = c[0] ^ tok[i];
            c  = {1'b0, c[4:1]};
            if (fb) c ^= 5'h14;
        end
        return ~c;
    endfunction

    function automatic logic [15:0] crc16(input int n);
        logic [15:0] c; logic fb;
        c = 16'hFFFF;
        for (int k = 0; k < n; k++)
            for (int i = 0; i < 8; i++) begin
                fb = c[0] ^ tx_buf[k][i];
                c  = {1'b0, c[15:1]};
                if (fb) c ^= 16'hA001;
            end
        return ~c;
    endfunction

    // ------------------------------------------------------------------
    // Line-level encoding
    // ------------------------------------------------------------------
    task automatic push_bit(input bit level, input bit is_se0);
        lv[nbits] = level; se[nbits] = is_se0; nbits++;
    endtask

    // Build SYNC + stuffed/NRZI data + EOP from tx_buf[0:tx_len-1].
    task automatic encode_packet();
        bit last; int ones;
        nbits = 0;
        // SYNC: KJKJ...KK
        for (int i = 0; i < (hs ? 15 : 3); i++) begin push_bit(0, 0); push_bit(1, 0); end
        push_bit(0, 0); push_bit(0, 0);
        last = 0; ones = 1;
        for (int k = 0; k < tx_len; k++)
            for (int i = 0; i < 8; i++) begin
                if (!tx_buf[k][i]) last = ~last;
                push_bit(last, 0);
                if (tx_buf[k][i]) begin
                    ones++;
                    if (ones == 6) begin last = ~last; push_bit(last, 0); ones = 0; end
                end else ones = 0;
            end
        if (hs) begin
            last = ~last;
            for (int i = 0; i < 8; i++) push_bit(last, 0);
        end else begin
            push_bit(0, 1); push_bit(0, 1); push_bit(1, 0);
        end
    endtask

    task automatic level_to_pins(input bit level, input bit is_se0, output logic dp, output logic dn);
        if (is_se0) begin dp = 0; dn = 0; end
        else if (ls) begin dp = ~level; dn = level; end
        else begin dp = level; dn = ~level; end
    endtask

    // Drive the encoded bit stream onto the bus.
    task automatic drive_bits();
        logic dp, dn;
        if (hs) begin
            for (int i = 0; i < nbits; i += 8) begin
                for (int j = 0; j < 8; j++) begin
                    if (i + j < nbits) level_to_pins(lv[i+j], se[i+j], dp, dn);
                    else begin dp = 0; dn = 0; end   // pad with SE0 idle
                    tx_dp[j] = dp; tx_dn[j] = dn;
                end
                tx_drive = 1;
                @(posedge clk);
            end
        end else begin
            for (int i = 0; i < nbits; i++) begin
                level_to_pins(lv[i], se[i], dp, dn);
                tx_dp = {8{dp}}; tx_dn = {8{dn}};
                tx_drive = 1;
                repeat (clocks_per_bit) @(posedge clk);
            end
        end
        tx_drive = 0;
        @(posedge clk);
    endtask

    // Send tx_buf[0:tx_len-1] as one packet.
    task automatic send_packet();
        encode_packet();
        drive_bits();
    endtask

    // Raw (no SYNC/NRZI) constant level for `clks` clocks (chirp, reset).
    task automatic drive_raw(input bit level, input bit is_se0, input int clks);
        logic dp, dn;
        level_to_pins(level, is_se0, dp, dn);
        tx_dp = {8{dp}}; tx_dn = {8{dn}};
        tx_drive = 1;
        repeat (clks) @(posedge clk);
        tx_drive = 0;
    endtask

    // ------------------------------------------------------------------
    // Packet helpers
    // ------------------------------------------------------------------
    task automatic send_token(input logic [3:0] pid, input logic [6:0] addr, input logic [3:0] ep);
        logic [10:0] tok; logic [4:0] c;
        tok = {ep, addr}; c = crc5(tok);
        tx_buf[0] = {~pid, pid};
        tx_buf[1] = tok[7:0];
        tx_buf[2] = {c, tok[10:8]};
        tx_len = 3;
        send_packet();
    endtask

    task automatic send_sof(input logic [10:0] frame);
        logic [4:0] c;
        c = crc5(frame);
        tx_buf[0] = 8'hA5;
        tx_buf[1] = frame[7:0];
        tx_buf[2] = {c, frame[10:8]};
        tx_len = 3;
        send_packet();
    endtask

    // Payload must be placed in tx_buf[1 .. n]; this writes PID + CRC.
    task automatic send_data(input logic [3:0] pid, input int n);
        logic [15:0] c; logic [15:0] cc; logic fb;
        tx_buf[0] = {~pid, pid};
        cc = 16'hFFFF;
        for (int k = 1; k <= n; k++)
            for (int i = 0; i < 8; i++) begin
                fb = cc[0] ^ tx_buf[k][i];
                cc = {1'b0, cc[15:1]};
                if (fb) cc ^= 16'hA001;
            end
        c = ~cc;
        tx_buf[n+1] = c[7:0];
        tx_buf[n+2] = c[15:8];
        tx_len = n + 3;
        send_packet();
    endtask

    task automatic send_handshake(input logic [3:0] pid);
        tx_buf[0] = {~pid, pid};
        tx_len = 1;
        send_packet();
    endtask

    // ------------------------------------------------------------------
    // Receive: capture the device's transmission and decode it.
    // ------------------------------------------------------------------
    bit smp_j[0:65535];
    bit smp_se0[0:65535];
    int nsmp;

    task automatic recv_packet(input int timeout_clks);
        int t; int i; bit prev; bit b; int ones; int zeros; int bitcnt; byte sh; bit active; bit done;
        int stride; int phase;
        rx_len = 0; rx_ok = 0; rx_timeout = 0; nsmp = 0;
        t = 0;
        while (!oe_i && t < timeout_clks) begin @(posedge clk); t++; end
        if (!oe_i) begin rx_timeout = 1; return; end
        // Capture samples while the device drives.
        while (oe_i) begin
            if (hs) begin
                for (int j = 0; j < 8; j++) begin
                    smp_j[nsmp]   = ls ? dn_i[j] : dp_i[j];
                    smp_se0[nsmp] = ~dp_i[j] & ~dn_i[j];
                    nsmp++;
                end
            end else begin
                smp_j[nsmp]   = ls ? dn_i[0] : dp_i[0];
                smp_se0[nsmp] = ~dp_i[0] & ~dn_i[0];
                nsmp++;
            end
            @(posedge clk);
        end
        // Decode. FS: the device holds every bit for clocks_per_bit
        // clocks starting at the first driven clock, so sample the centre.
        stride = hs ? 1 : clocks_per_bit;
        phase  = hs ? 0 : clocks_per_bit / 2;
        prev = 1; ones = 0; zeros = 0; bitcnt = 0; sh = 0; active = 0; done = 0;
        i = phase;
        while (i < nsmp && !done) begin
            if (smp_se0[i]) begin
                if (active) begin
                    rx_ok = (bitcnt == 0) && !hs;
                    done = 1;
                end
            end else begin
                b = (smp_j[i] == prev); prev = smp_j[i];
                if (active) begin
                    if (ones == 6) begin
                        ones = 0;
                        if (b) begin
                            rx_ok = hs && (bitcnt == 7);
                            done = 1;
                        end
                    end else begin
                        sh = {b, sh[7:1]};
                        if (b) ones++; else ones = 0;
                        bitcnt++;
                        if (bitcnt == 8) begin rx_buf[rx_len++] = sh; bitcnt = 0; end
                    end
                end else begin
                    if (b) begin
                        if (zeros >= 3) begin active = 1; ones = 1; bitcnt = 0; sh = 0; end
                        zeros = 0;
                    end else zeros++;
                end
            end
            i += stride;
        end
    endtask

    // Wait for a packet and check that it is the expected handshake.
    task automatic expect_handshake(input logic [3:0] pid, input string what);
        recv_packet(2000);
        if (rx_timeout || !rx_ok || rx_len != 1 || rx_buf[0] != {~pid, pid}) begin
            $display("ERROR: %s: expected handshake %h, got timeout=%0d ok=%0d len=%0d pid=%h",
                     what, pid, rx_timeout, rx_ok, rx_len, rx_buf[0]);
            errors++;
        end
    endtask

    // IN transaction: token, then receive DATAx into rx_buf (payload only,
    // CRC stripped after verification). Returns the PID in rx_pid.
    logic [3:0] rx_pid;
    task automatic in_transaction(input logic [6:0] addr, input logic [3:0] ep, input bit ack);
        logic [15:0] c; logic fb; int n;
        send_token(4'b1001, addr, ep);
        recv_packet(2000);
        rx_pid = rx_timeout ? 4'h0 : rx_buf[0][3:0];
        if (rx_timeout || !rx_ok) begin
            $display("ERROR: IN ep%0d: timeout=%0d ok=%0d", ep, rx_timeout, rx_ok);
            errors++; rx_len = 0; return;
        end
        if (rx_buf[0][3:0] == 4'b0011 || rx_buf[0][3:0] == 4'b1011) begin
            // verify CRC16 over payload + CRC (residual 0xB001)
            c = 16'hFFFF;
            for (int k = 1; k < rx_len; k++)
                for (int i = 0; i < 8; i++) begin
                    fb = c[0] ^ rx_buf[k][i];
                    c  = {1'b0, c[15:1]};
                    if (fb) c ^= 16'hA001;
                end
            if (c != 16'hB001) begin
                $display("ERROR: IN ep%0d: CRC16 residual %h", ep, c);
                errors++;
            end
            n = rx_len - 3;
            for (int k = 0; k < n; k++) rx_buf[k] = rx_buf[k+1];
            rx_len = n;
            if (ack) send_handshake(4'b0010);
        end else begin
            rx_len = 0;
        end
    endtask

    // OUT / SETUP transaction: payload in tx_buf[1..n].
    task automatic out_transaction(input logic [3:0] token_pid, input logic [6:0] addr, input logic [3:0] ep,
                                   input logic [3:0] data_pid, input int n);
        byte save1, save2;
        // send_token builds its packet in tx_buf[0:2]; keep the payload
        // bytes that live there.
        save1 = tx_buf[1]; save2 = tx_buf[2];
        send_token(token_pid, addr, ep);
        tx_buf[1] = save1; tx_buf[2] = save2;
        send_data(data_pid, n);
        recv_packet(2000);
        rx_pid = rx_timeout ? 4'h0 : rx_buf[0][3:0];
        if (rx_timeout || !rx_ok || rx_len != 1) begin
            $display("ERROR: OUT/SETUP ep%0d: no handshake (timeout=%0d ok=%0d len=%0d)", ep, rx_timeout, rx_ok, rx_len);
            errors++;
        end
    endtask
endmodule
