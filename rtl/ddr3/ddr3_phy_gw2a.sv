// Copied from ~/repos/riscv-veryl/src/ddr3_phy_gw2a.veryl (commit 78e2537, 2026-09-10) for the NVMe DDR3 namespace.
// Keep in sync with the RISC-V project; local changes should be upstreamed there.
// DDR3 PHY for Gowin GW2A (Tang Primer 20K) built from the public
// IOLOGIC primitives — no Gowin DDR3 IP. Turns the slot vectors of
// `Ddr3Ctrl` into pins:
//
//   fclk = 2 x CK (DDR: one slot per fclk edge), pclk = fclk / 4 = CK / 2.
//   pclk must come from a CLKDIV (DIV_MODE = "4") fed by fclk so the two
//   are phase aligned, as Gowin requires for OSER8 / IDES8.
//
//   OSER8  serialises D0..D7 (D0 first) at DDR on fclk; TX0..TX3 are the
//          tristate controls, one per two slots, appearing on Q1.
//   IDES8  samples the pin at every fclk edge; Q0 is the oldest of the
//          eight samples per pclk.
//   CK and DQS are differential pairs, but on Gowin that is a property of
//   the pin (IO_TYPE=SSTL15D on the P pin in the .cst, the N pin follows),
//   so they use the ordinary OBUF / IOBUF like DQ. CKE / ODT / RESET# are
//   slow and leave through ordinary registers.
//
// Slot s of every controller vector maps to D[s] / Q[s]. CK is the
// constant pattern {0,0,1,1,0,0,1,1} (rising edges at slots 2 and 6).
// Commands are held for one CK (slots 0..3) and DESELECT for the second
// CK of the pclk cycle (slots 4..7), see Ddr3Ctrl.
//
// Read capture: DQ and DQS are simply sampled by IDES8; the controller
// picks the beats out of its sample history (RD_SEL / RD_LAT registers).
// IODELAY is not used in this first version — the quarter-CK slot grid
// plus the on-board sweep (doc/ddr3_controller.md) is the calibration.
//
// This module only makes sense on the Gowin tool chain; Verilator never
// elaborates it (it is not instantiated by any simulation top).
module Ddr3PhyGw2a (
    input var logic i_pclk,
    input var logic i_fclk,
    input var logic i_rst , // active high, pclk domain

    // from / to Ddr3Ctrl (pclk domain)
    input  var logic           i_reset_n,
    input  var logic           i_cke    ,
    input  var logic           i_odt    ,
    input  var logic           i_cs_n   ,
    input  var logic           i_ras_n  ,
    input  var logic           i_cas_n  ,
    input  var logic           i_we_n   ,
    input  var logic [3-1:0]   i_ba     ,
    input  var logic [14-1:0]  i_a      ,
    input  var logic [128-1:0] i_dq_out ,
    input  var logic [4-1:0]   i_dq_oe  ,
    input  var logic [16-1:0]  i_dm_out ,
    input  var logic [16-1:0]  i_dqs_out,
    input  var logic [4-1:0]   i_dqs_oe ,
    output var logic [128-1:0] o_dq_in  ,
    output var logic [16-1:0]  o_dqs_in ,

    // DDR3 pins
    output var logic          o_ddr_ck     , // P side of the pair (SSTL15D)
    output var logic          o_ddr_cke    ,
    output var logic          o_ddr_odt    ,
    output var logic          o_ddr_reset_n,
    output var logic          o_ddr_cs_n   ,
    output var logic          o_ddr_ras_n  ,
    output var logic          o_ddr_cas_n  ,
    output var logic          o_ddr_we_n   ,
    output var logic [3-1:0]  o_ddr_ba     ,
    output var logic [14-1:0] o_ddr_a      ,
    output var logic [2-1:0]  o_ddr_dm     ,
    inout  tri logic [16-1:0] io_ddr_dq    ,
    inout  tri logic [2-1:0]  io_ddr_dqs    // P side of the pairs (SSTL15D)
);
    // Slow control pins: plain registers in the pclk domain.
    always_ff @ (posedge i_pclk) begin
        o_ddr_cke     <= i_cke;
        o_ddr_odt     <= i_odt;
        o_ddr_reset_n <= i_reset_n;
    end

    // Command / address: one command per pclk in CK 0, DESELECT in CK 1.
    // 8 slots per pin: {4{CK1 value}, 4{CK0 value}}.
    logic [8-1:0] cs_n_slots ; always_comb cs_n_slots  = {4'b1111, {4{i_cs_n}}};
    logic [8-1:0] ras_n_slots; always_comb ras_n_slots = {{4{i_ras_n}}, {4{i_ras_n}}};
    logic [8-1:0] cas_n_slots; always_comb cas_n_slots = {{4{i_cas_n}}, {4{i_cas_n}}};
    logic [8-1:0] we_n_slots ; always_comb we_n_slots  = {{4{i_we_n}}, {4{i_we_n}}};

    logic [8-1:0] ba_slots [3] ;
    logic [8-1:0] a_slots  [14];
    always_comb begin
        for (int i = 0; i < 3; i++) begin
            ba_slots[i] = {8{i_ba[i]}};
        end
        for (int i = 0; i < 14; i++) begin
            a_slots[i] = {8{i_a[i]}};
        end
    end

    // DQ / DM / DQS per-pin slot bytes (bit s = slot s).
    logic [8-1:0] dq_slots  [16];
    logic [8-1:0] dm_slots  [2] ;
    logic [8-1:0] dqs_slots [2] ;
    logic [8-1:0] dq_q      [16];
    logic [8-1:0] dqs_q     [2] ;
    always_comb begin
        for (int i = 0; i < 16; i++) begin
            for (int s = 0; s < 8; s++) begin
                dq_slots[i][s]      = i_dq_out[16 * s + i];
                o_dq_in[16 * s + i] = dq_q[i][s];
            end
        end
        for (int i = 0; i < 2; i++) begin
            for (int s = 0; s < 8; s++) begin
                dm_slots[i][s]      = i_dm_out[2 * s + i];
                dqs_slots[i][s]     = i_dqs_out[2 * s + i];
                o_dqs_in[2 * s + i] = dqs_q[i][s];
            end
        end
    end

    // OSER8 TX inputs are "output disabled" (1 = tristate).
    logic [4-1:0] dq_tx ; always_comb dq_tx  = ~i_dq_oe;
    logic [4-1:0] dqs_tx; always_comb dqs_tx = ~i_dqs_oe;

    // ---- CK: constant pattern through OSER8 and a true-LVDS buffer ----
    OSER8 u_oser_ck (
        .Q0    (o_ddr_ck),
        .Q1    (        ),
        .D0    (1'b0    ),
        .D1    (1'b0    ),
        .D2    (1'b1    ),
        .D3    (1'b1    ),
        .D4    (1'b0    ),
        .D5    (1'b0    ),
        .D6    (1'b1    ),
        .D7    (1'b1    ),
        .TX0   (1'b0    ),
        .TX1   (1'b0    ),
        .TX2   (1'b0    ),
        .TX3   (1'b0    ),
        .PCLK  (i_pclk  ),
        .FCLK  (i_fclk  ),
        .RESET (i_rst   )
    );
    // ---- command / address (output only) ----
    OSER8 u_oser_cs (
        .Q0    (o_ddr_cs_n   ),
        .Q1    (             ),
        .D0    (cs_n_slots[0]),
        .D1    (cs_n_slots[1]),
        .D2    (cs_n_slots[2]),
        .D3    (cs_n_slots[3]),
        .D4    (cs_n_slots[4]),
        .D5    (cs_n_slots[5]),
        .D6    (cs_n_slots[6]),
        .D7    (cs_n_slots[7]),
        .TX0   (1'b0         ),
        .TX1   (1'b0         ),
        .TX2   (1'b0         ),
        .TX3   (1'b0         ),
        .PCLK  (i_pclk       ),
        .FCLK  (i_fclk       ),
        .RESET (i_rst        )
    );
    OSER8 u_oser_ras (
        .Q0    (o_ddr_ras_n   ),
        .Q1    (              ),
        .D0    (ras_n_slots[0]),
        .D1    (ras_n_slots[1]),
        .D2    (ras_n_slots[2]),
        .D3    (ras_n_slots[3]),
        .D4    (ras_n_slots[4]),
        .D5    (ras_n_slots[5]),
        .D6    (ras_n_slots[6]),
        .D7    (ras_n_slots[7]),
        .TX0   (1'b0          ),
        .TX1   (1'b0          ),
        .TX2   (1'b0          ),
        .TX3   (1'b0          ),
        .PCLK  (i_pclk        ),
        .FCLK  (i_fclk        ),
        .RESET (i_rst         )
    );
    OSER8 u_oser_cas (
        .Q0    (o_ddr_cas_n   ),
        .Q1    (              ),
        .D0    (cas_n_slots[0]),
        .D1    (cas_n_slots[1]),
        .D2    (cas_n_slots[2]),
        .D3    (cas_n_slots[3]),
        .D4    (cas_n_slots[4]),
        .D5    (cas_n_slots[5]),
        .D6    (cas_n_slots[6]),
        .D7    (cas_n_slots[7]),
        .TX0   (1'b0          ),
        .TX1   (1'b0          ),
        .TX2   (1'b0          ),
        .TX3   (1'b0          ),
        .PCLK  (i_pclk        ),
        .FCLK  (i_fclk        ),
        .RESET (i_rst         )
    );
    OSER8 u_oser_we (
        .Q0    (o_ddr_we_n   ),
        .Q1    (             ),
        .D0    (we_n_slots[0]),
        .D1    (we_n_slots[1]),
        .D2    (we_n_slots[2]),
        .D3    (we_n_slots[3]),
        .D4    (we_n_slots[4]),
        .D5    (we_n_slots[5]),
        .D6    (we_n_slots[6]),
        .D7    (we_n_slots[7]),
        .TX0   (1'b0         ),
        .TX1   (1'b0         ),
        .TX2   (1'b0         ),
        .TX3   (1'b0         ),
        .PCLK  (i_pclk       ),
        .FCLK  (i_fclk       ),
        .RESET (i_rst        )
    );
    for (genvar i = 0; i < 3; i++) begin :g_ba
        OSER8 u_oser (
            .Q0    (o_ddr_ba[i]   ),
            .Q1    (              ),
            .D0    (ba_slots[i][0]),
            .D1    (ba_slots[i][1]),
            .D2    (ba_slots[i][2]),
            .D3    (ba_slots[i][3]),
            .D4    (ba_slots[i][4]),
            .D5    (ba_slots[i][5]),
            .D6    (ba_slots[i][6]),
            .D7    (ba_slots[i][7]),
            .TX0   (1'b0          ),
            .TX1   (1'b0          ),
            .TX2   (1'b0          ),
            .TX3   (1'b0          ),
            .PCLK  (i_pclk        ),
            .FCLK  (i_fclk        ),
            .RESET (i_rst         )
        );
    end
    for (genvar i = 0; i < 14; i++) begin :g_a
        OSER8 u_oser (
            .Q0    (o_ddr_a[i]   ),
            .Q1    (             ),
            .D0    (a_slots[i][0]),
            .D1    (a_slots[i][1]),
            .D2    (a_slots[i][2]),
            .D3    (a_slots[i][3]),
            .D4    (a_slots[i][4]),
            .D5    (a_slots[i][5]),
            .D6    (a_slots[i][6]),
            .D7    (a_slots[i][7]),
            .TX0   (1'b0         ),
            .TX1   (1'b0         ),
            .TX2   (1'b0         ),
            .TX3   (1'b0         ),
            .PCLK  (i_pclk       ),
            .FCLK  (i_fclk       ),
            .RESET (i_rst        )
        );
    end
    for (genvar i = 0; i < 2; i++) begin :g_dm
        OSER8 u_oser (
            .Q0    (o_ddr_dm[i]   ),
            .Q1    (              ),
            .D0    (dm_slots[i][0]),
            .D1    (dm_slots[i][1]),
            .D2    (dm_slots[i][2]),
            .D3    (dm_slots[i][3]),
            .D4    (dm_slots[i][4]),
            .D5    (dm_slots[i][5]),
            .D6    (dm_slots[i][6]),
            .D7    (dm_slots[i][7]),
            .TX0   (1'b0          ),
            .TX1   (1'b0          ),
            .TX2   (1'b0          ),
            .TX3   (1'b0          ),
            .PCLK  (i_pclk        ),
            .FCLK  (i_fclk        ),
            .RESET (i_rst         )
        );
    end

    // ---- DQ: OSER8 -> IOBUF -> IDES8 ----
    logic [16-1:0] dq_o  ;
    logic [16-1:0] dq_oen;
    logic [16-1:0] dq_i  ;
    for (genvar i = 0; i < 16; i++) begin :g_dq
        OSER8 u_oser (
            .Q0    (dq_o[i]       ),
            .Q1    (dq_oen[i]     ),
            .D0    (dq_slots[i][0]),
            .D1    (dq_slots[i][1]),
            .D2    (dq_slots[i][2]),
            .D3    (dq_slots[i][3]),
            .D4    (dq_slots[i][4]),
            .D5    (dq_slots[i][5]),
            .D6    (dq_slots[i][6]),
            .D7    (dq_slots[i][7]),
            .TX0   (dq_tx[0]      ),
            .TX1   (dq_tx[1]      ),
            .TX2   (dq_tx[2]      ),
            .TX3   (dq_tx[3]      ),
            .PCLK  (i_pclk        ),
            .FCLK  (i_fclk        ),
            .RESET (i_rst         )
        );
        IOBUF u_iobuf (
            .O   (dq_i[i]     ),
            .IO  (io_ddr_dq[i]),
            .I   (dq_o[i]     ),
            .OEN (dq_oen[i]   )
        );
        IDES8 u_ides (
            .Q0    (dq_q[i][0]),
            .Q1    (dq_q[i][1]),
            .Q2    (dq_q[i][2]),
            .Q3    (dq_q[i][3]),
            .Q4    (dq_q[i][4]),
            .Q5    (dq_q[i][5]),
            .Q6    (dq_q[i][6]),
            .Q7    (dq_q[i][7]),
            .D     (dq_i[i]   ),
            .CALIB (1'b0      ),
            .PCLK  (i_pclk    ),
            .FCLK  (i_fclk    ),
            .RESET (i_rst     )
        );
    end

    // ---- DQS: OSER8 -> IOBUF -> IDES8 ----
    logic [2-1:0] dqs_o  ;
    logic [2-1:0] dqs_oen;
    logic [2-1:0] dqs_i  ;
    for (genvar i = 0; i < 2; i++) begin :g_dqs
        OSER8 u_oser (
            .Q0    (dqs_o[i]       ),
            .Q1    (dqs_oen[i]     ),
            .D0    (dqs_slots[i][0]),
            .D1    (dqs_slots[i][1]),
            .D2    (dqs_slots[i][2]),
            .D3    (dqs_slots[i][3]),
            .D4    (dqs_slots[i][4]),
            .D5    (dqs_slots[i][5]),
            .D6    (dqs_slots[i][6]),
            .D7    (dqs_slots[i][7]),
            .TX0   (dqs_tx[0]      ),
            .TX1   (dqs_tx[1]      ),
            .TX2   (dqs_tx[2]      ),
            .TX3   (dqs_tx[3]      ),
            .PCLK  (i_pclk         ),
            .FCLK  (i_fclk         ),
            .RESET (i_rst          )
        );
        IOBUF u_iobuf (
            .O   (dqs_i[i]     ),
            .IO  (io_ddr_dqs[i]),
            .I   (dqs_o[i]     ),
            .OEN (dqs_oen[i]   )
        );
        IDES8 u_ides (
            .Q0    (dqs_q[i][0]),
            .Q1    (dqs_q[i][1]),
            .Q2    (dqs_q[i][2]),
            .Q3    (dqs_q[i][3]),
            .Q4    (dqs_q[i][4]),
            .Q5    (dqs_q[i][5]),
            .Q6    (dqs_q[i][6]),
            .Q7    (dqs_q[i][7]),
            .D     (dqs_i[i]   ),
            .CALIB (1'b0       ),
            .PCLK  (i_pclk     ),
            .FCLK  (i_fclk     ),
            .RESET (i_rst      )
        );
    end
endmodule
//# sourceMappingURL=ddr3_phy_gw2a.sv.map
