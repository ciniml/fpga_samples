// Behavioural line model for the transformerless 100BASE-TX PHY tests.
//   TX: the two LVCMOS pins (tx_p, tx_n) -> differential level
//       ATT * (tx_p - tx_n) [V], first-order low-pass TAU [ns]
//       (one pole for the TX edge shaping + cable), + OFFSET (baseline)
//       + uniform noise +-NOISE
//   RX: comparator A = v > TH_A, B = v > -TH_B, SAMPLES samples per
//       rx_clk spaced SP ns, LAT ns behind the clock edge (so every
//       transition that affects a sample is already known), [0] earliest
`timescale 1ns/1ps
module eth100_chan #(
    parameter real TAU     = 1.6,
    parameter real ATT     = 1.0,
    parameter real NOISE   = 0.0,
    parameter real OFFSET  = 0.0,
    parameter real TH_A    = 0.5,
    parameter real TH_B    = 0.5,
    parameter real LAT     = 40.0,
    parameter real SP      = 2.0,
    parameter int  SAMPLES = 4
) (
    input  logic               tx_p,
    input  logic               tx_n,
    input  logic               rx_clk,
    output logic [SAMPLES-1:0] a,
    output logic [SAMPLES-1:0] b
);
    real tq[$];
    real lq[$];
    real cur_t = 0.0, cur_v = 0.0, cur_l = 0.0;
    real level;

    always @(tx_p or tx_n) begin
        level = ATT * ((tx_p ? 1.0 : 0.0) - (tx_n ? 1.0 : 0.0));
        tq.push_back($realtime);
        lq.push_back(level);
    end

    function automatic real v_at(input real t);
        while (tq.size() > 0 && tq[0] <= t) begin
            cur_v = cur_l + (cur_v - cur_l) * $exp(-(tq[0] - cur_t) / TAU);
            cur_t = tq[0];
            cur_l = lq[0];
            void'(tq.pop_front());
            void'(lq.pop_front());
        end
        return cur_l + (cur_v - cur_l) * $exp(-(t - cur_t) / TAU) + OFFSET
               + NOISE * (2.0 * ($urandom() / 4294967296.0) - 1.0);
    endfunction

    always @(posedge rx_clk) begin
        real t0, v;
        t0 = $realtime - LAT;
        for (int k = 0; k < SAMPLES; k++) begin
            v = v_at(t0 + SP * k);
            a[k] <= v > TH_A;
            b[k] <= v > -TH_B;
        end
    end
endmodule
