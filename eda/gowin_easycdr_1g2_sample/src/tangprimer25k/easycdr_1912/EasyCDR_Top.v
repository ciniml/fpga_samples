`include "define.v"
`include "static_macro_define.v"
module `MODULE_NAME (
            input           rxp_i,
            input           rxn_i,

    `ifdef SHARED_LOGIC
            input           pll_clkin_i,
            input           pll_clkout0_i,
            input           pll_clkout1_i,
            input           pll_clkout2_i,
            input           pll_clkout3_i,
            input           pll_lock_i,
            output          share_clk0_o,
            output          share_clk1_o,
            output          share_clk2_o,
            output          share_clk3_o,
            output          share_clk4_o,
            output          share_reset_o,
    `else
            input           share_clk0_i,
            input           share_clk1_i,
            input           share_clk2_i,
            input           share_clk3_i,
            input           share_clk4_i,
            input           share_reset_i,
    `endif

            input           rstn_i,
            output          dout_en_o,
    `ifdef BEYOND_1G
        `ifdef OUTPUT32BIT
            output  [31:0]  dout_o
        `else
            output  [19:0]  dout_o
        `endif
    `else
        `ifdef OUTPUT16BIT
            output  [15:0]  dout_o
        `else
            `ifdef WORD_ALI
            output          align_flag_o,
            `ifdef DECODE_8B10B
            output          error_o,
            `endif
            `endif
            output  [ 9:0]  dout_o
        `endif
    `endif
    );

`getname(easycdr,`MODULE_NAME) u_easycdr(
        .rxp_i              (rxp_i              ),
        .rxn_i              (rxn_i              ),

    `ifdef SHARED_LOGIC
        .pll_clkin_i        (pll_clkin_i        ),
        .pll_clkout0_i      (pll_clkout0_i      ),
        .pll_clkout1_i      (pll_clkout1_i      ),
        .pll_clkout2_i      (pll_clkout2_i      ),
        .pll_clkout3_i      (pll_clkout3_i      ),
        .pll_lock_i         (pll_lock_i         ),
        .share_clk0_o       (share_clk0_o       ),
        .share_clk1_o       (share_clk1_o       ),
        .share_clk2_o       (share_clk2_o       ),
        .share_clk3_o       (share_clk3_o       ),
        .share_clk4_o       (share_clk4_o       ),
        .share_reset_o      (share_reset_o      ),
    `else
        .share_clk0_i       (share_clk0_i       ),
        .share_clk1_i       (share_clk1_i       ),
        .share_clk2_i       (share_clk2_i       ),
        .share_clk3_i       (share_clk3_i       ),
        .share_clk4_i       (share_clk4_i       ),
        .share_reset_i      (share_reset_i      ),
    `endif

        .rstn_i             (rstn_i             ),

        .dout_en_o          (dout_en_o          ),

    `ifndef BEYOND_1G
        `ifndef OUTPUT16BIT
            `ifdef WORD_ALI
                .align_flag_o       (align_flag_o       ),
            `ifdef DECODE_8B10B
                .error_o            (error_o            ),
            `endif
            `endif
        `endif
    `endif
    
        .dout_o             (dout_o             )
    );

endmodule