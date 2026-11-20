// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Behavioural 10BASE-T1S mixing segment for the T1sPhy tests.
//   Each node drives +-STEP (tx_en and tx_p != tx_n) or nothing; the bus
//   differential voltage is the sum of the driven levels (overlapping
//   drivers = a physical collision, counted in `collisions`), through a
//   first-order low-pass TAU [ns] (edge shaping of the board + cable),
//   scaled by ATT for the receivers, plus uniform noise +-NOISE.
//   The voltage is stepped every DT ns into a ring buffer; receivers read
//   it: comparator H = v > TH, L = v > -TH, SPC samples per rx clock spaced
//   SP ns, LAT ns behind the clock edge ([0] earliest).
`timescale 1ns/1ps
module t1s_bus #(
    parameter int  N     = 2,
    parameter real STEP  = 0.5,
    parameter real TAU   = 7.0,
    parameter real ATT   = 1.0,
    parameter real NOISE = 0.0,
    parameter real TH    = 0.1,
    parameter real LAT   = 30.0,
    parameter real SP    = 2.5,
    parameter int  SPC   = 4
) (
    input  logic [N-1:0]       tx_p,
    input  logic [N-1:0]       tx_n,
    input  logic [N-1:0]       tx_en,
    input  logic [N-1:0]       rx_clk,
    output logic [SPC-1:0]     h [N],
    output logic [SPC-1:0]     l [N],
    output int                 collisions
);
    localparam real DT = 0.25;
    localparam int  NB = 1024;          // 256 ns of history
    real    vbuf [NB];
    real    v     = 0.0;
    longint step  = 0;
    int     ndrv  = 0;
    real    alpha;

    initial begin
        collisions = 0;
        alpha = 1.0 - $exp(-DT / TAU);
        for (int i = 0; i < NB; i++) vbuf[i] = 0.0;
        forever begin
            real level;
            int  n;
            #(DT);
            level = 0.0;
            n     = 0;
            for (int i = 0; i < N; i++) begin
                if (tx_en[i] && tx_p[i] != tx_n[i]) begin
                    level += tx_p[i] ? STEP : -STEP;
                    n++;
                end
            end
            if (n > 1 && ndrv <= 1) collisions++;
            ndrv = n;
            v += (level - v) * alpha;
            step++;
            vbuf[step % NB] = v;
        end
    end

    function automatic real v_at(input real t);
        longint s;
        s = longint'(t / DT);
        if (s < 0) s = 0;
        return ATT * vbuf[s % NB] + NOISE * (2.0 * ($urandom() / 4294967296.0) - 1.0);
    endfunction

    for (genvar i = 0; i < N; i++) begin : g_rx
        always @(posedge rx_clk[i]) begin
            real t0, vv;
            t0 = $realtime - LAT;
            for (int k = 0; k < SPC; k++) begin
                vv = v_at(t0 + SP * k);
                h[i][k] <= vv > TH;
                l[i][k] <= vv > -TH;
            end
        end
    end
endmodule
