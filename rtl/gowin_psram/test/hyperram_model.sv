// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
// Behavioral HyperRAM (HyperBus) die model, W955D8MBYA-like, for the
// GowinPsram tests. Implements: CA capture on CK edges, linear bursts,
// register space (ID0/ID1/CR0/CR1), fixed/variable initial latency with
// the RWDS additional-latency indication, RWDS data mask on writes,
// RWDS-strobed read data with tCKD output delay, wrapping at the CR0 burst
// length (which the real die does even for linear CAs). Not modeled: deep
// power down, refresh collisions beyond a random "additional latency"
// flag in variable-latency mode.
`timescale 1ns/1ps
module hyperram_model #(
    parameter WORDS  = 1 << 21,   // 4MiB die
    parameter T_CKD  = 5.0,       // CK edge -> DQ/RWDS output (ns)
    parameter T_DSV  = 3.0        // CS# low -> RWDS valid (ns)
) (
    input  wire       ck,
    input  wire       cs_n,
    input  wire       reset_n,
    inout  wire [7:0] dq,
    inout  wire       rwds
);
    reg [15:0] mem [0:WORDS-1];
    reg [15:0] cr0, cr1;
    localparam [15:0] ID0 = 16'h0C81;   // arbitrary, checked by the test
    localparam [15:0] ID1 = 16'h0001;

    reg [7:0] dq_drv;
    reg       dq_oe;
    reg       rwds_drv;
    reg       rwds_oe;
    assign dq   = (dq_oe && !cs_n) ? dq_drv : 8'bz;
    assign rwds = (rwds_oe && !cs_n) ? rwds_drv : 1'bz;

    integer n_ca_writes = 0, n_reads = 0, n_writes = 0, n_masked = 0;
    integer errors = 0;

    function integer lat_clocks(input [3:0] code);
        case (code)
            4'b1110: lat_clocks = 3;
            4'b1111: lat_clocks = 4;
            4'b0000: lat_clocks = 5;
            4'b0001: lat_clocks = 6;
            default: lat_clocks = 6;
        endcase
    endfunction

    task automatic reset_regs;
        cr0 = 16'h8F1F;   // default: 6 clocks, fixed latency
        cr1 = 16'hFFC1;
    endtask

    initial begin
        reset_regs();
        dq_oe = 0; rwds_oe = 0; dq_drv = 0; rwds_drv = 0;
    end
    always @(negedge reset_n) reset_regs();

    // CS# low time limit (tCSM = 4us)
    realtime cs_fall;
    always @(negedge cs_n) cs_fall = $realtime;
    always @(posedge cs_n) begin
        if ($realtime - cs_fall > 4000.0) begin
            $display("ERROR: hyperram_model: CS# low for %0.1f ns (> tCSM 4us)", $realtime - cs_fall);
            errors++;
        end
    end

    reg [47:0] ca;
    reg        rw, reg_space, linear;
    reg [31:0] waddr;
    integer    lat, lat_total, k;
    reg        extra;
    reg [15:0] w;
    reg        m_hi, m_lo;
    integer    wrap_words;

    // The die wraps every burst (linear CA included, as observed on the
    // Tang Nano 9K W955D8MBYA) at the CR0 burst length.
    function integer wrap_len(input [1:0] code);
        case (code)
            2'b00: wrap_len = 64;
            2'b01: wrap_len = 32;
            2'b10: wrap_len = 8;
            default: wrap_len = 16;
        endcase
    endfunction
    function [31:0] next_addr(input [31:0] a, input integer ww);
        next_addr = (a & ~(ww - 1)) | ((a + 1) & (ww - 1));
    endfunction

    always @(negedge cs_n) begin
        // additional latency flag: always in fixed mode, random otherwise
        extra = cr0[3] ? 1'b1 : ($urandom_range(0, 19) == 0);
        rwds_drv = extra;
        dq_oe = 0;
        // ---- CA: 6 bytes on 6 consecutive CK edges ----
        ca = 48'h0;
        for (k = 0; k < 6; k++) begin
            if (k[0] == 0) @(posedge ck); else @(negedge ck);
            if (cs_n) begin
                $display("ERROR: hyperram_model: CS# rose during CA");
                errors++;
            end
            ca = {ca[39:0], dq};
        end
        rw        = ca[47];
        reg_space = ca[46];
        linear    = ca[45];
        waddr     = {ca[44:16], ca[2:0]};
        if (!linear) begin
            $display("ERROR: hyperram_model: wrapped burst not supported (CA=%h)", ca);
            errors++;
        end
        if (ca[15:3] != 13'h0 || {ca[44:16], ca[2:0]} >= WORDS) begin
            $display("ERROR: hyperram_model: reserved CA bits set (CA=%h)", ca);
            errors++;
        end
`ifdef HYPERRAM_TRACE
        $display("model: CA=%h rw=%b reg=%b linear=%b waddr=%h at %0t", ca, rw, reg_space, linear, waddr, $realtime);
`endif
        wrap_words = wrap_len(cr0[1:0]);
        lat       = lat_clocks(cr0[7:4]);
        // data phase begins at CK rising edge (2 + latency count): the
        // count runs from the third CA clock (measured on the W955D8MBYA
        // with fixed latency; the variable-latency case is assumed alike)
        lat_total = 2 + (extra ? 2 * lat : lat);

        if (!rw && reg_space) begin
            // register write: data word right after the CA, no latency
            rwds_oe = 0;
            @(posedge ck or posedge cs_n); w[15:8] = dq;
            @(negedge ck or posedge cs_n); w[7:0]  = dq;
            $display("model: reg write CA=%h waddr=%h data=%h at %0t", ca, waddr, w, $realtime);
            case (waddr)
                32'h800: cr0 = w;
                32'h801: cr1 = w;
                default: begin
                    $display("ERROR: hyperram_model: write to unknown register %h", waddr);
                    errors++;
                end
            endcase
            n_ca_writes++;
        end else if (rw) begin
            // read: RWDS low after the CA until data, then strobes with data
            rwds_drv = 0;
            for (k = 3; k < lat_total; k++) begin
                @(posedge ck or posedge cs_n);
                if (cs_n) break;
            end
            while (!cs_n) begin
                if (reg_space) begin
                    case (waddr[11:0])
                        12'h000: w = ID0;
                        12'h001: w = ID1;
                        12'h800: w = cr0;
                        12'h801: w = cr1;
                        default: w = 16'hDEAD;
                    endcase
                end else begin
                    w = mem[waddr % WORDS];
                end
                @(posedge ck or posedge cs_n);
                if (cs_n) break;
                #(T_CKD) dq_drv = w[15:8]; rwds_drv = 1; dq_oe = 1;
                @(negedge ck or posedge cs_n);
                if (cs_n) break;
                #(T_CKD) dq_drv = w[7:0]; rwds_drv = 0;
                waddr = reg_space ? waddr + 1 : next_addr(waddr, wrap_words);
                n_reads++;
            end
            dq_oe = 0;
            rwds_oe = 0;
        end else begin
            // memory write: master drives RWDS as byte mask with the data
            rwds_oe = 0;
            for (k = 3; k < lat_total; k++) begin
                @(posedge ck or posedge cs_n);
                if (cs_n) break;
            end
            while (!cs_n) begin
                @(posedge ck or posedge cs_n);
                if (cs_n) break;
                w[15:8] = dq; m_hi = rwds;
                @(negedge ck or posedge cs_n);
                if (cs_n) break;
                w[7:0]  = dq; m_lo = rwds;
                if (!m_hi) mem[waddr % WORDS][15:8] = w[15:8];
                if (!m_lo) mem[waddr % WORDS][7:0]  = w[7:0];
                if (m_hi || m_lo) n_masked++;
                waddr = next_addr(waddr, wrap_words);
                n_writes++;
            end
        end
    end

    // RWDS (additional latency indication) tDSV after CS# falls
    always @(negedge cs_n) begin
        #(T_DSV);
        if (!cs_n) rwds_oe = 1;
    end

    always @(posedge cs_n) begin
        dq_oe   = 0;
        rwds_oe = 0;
    end
endmodule
