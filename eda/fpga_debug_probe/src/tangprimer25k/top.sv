/**
 * @file top.sv
 * @brief Top module for ethernet ICMP echo reply system.
 */
// Copyright 2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

`default_nettype none
module top(
    input wire clock,

    // Input button
    input wire button_s0,
    input wire button_s1,

    // Output LED
    output logic [5:0] led,

    // EasyCDR TX/RX
    input wire easycdr_rxp,
    input wire easycdr_rxn,
    output logic easycdr_txp,
    output logic easycdr_txn
);
    logic reset_n;
    logic pll_lock;
    logic pll_clkout0;
    logic pll_clkout1;
    logic pll_clkout2;
    logic pll_clkout3;
    logic easycdr_rstn;
    logic easycdr_share_clk0;
    logic easycdr_share_clk1;
    logic easycdr_share_clk2;
    logic easycdr_share_clk3;
    logic easycdr_share_clk4;
    logic easycdr_share_reset;
    logic [15:0] easycdr_dout;
    logic        easycdr_dout_en;
    logic        easycdr_error;

    logic [15:0] reset_seq = '1;
    always_ff @(posedge clock) begin
        reset_seq <= {reset_seq[14:0], 1'b0};
    end
    assign reset_n = ~reset_seq[15];

    Gowin_PLL pll_easycdr_clock(
        .lock   (pll_lock   ), //output lock
        .clkout0(pll_clkout0), //output clkout0
        .clkout1(pll_clkout1), //output clkout1
        .clkout2(pll_clkout2), //output clkout2
        .clkout3(pll_clkout3), //output clkout3
        .clkin  (clock      )  //input clkin
    );

	EasyCDR_Top easycdr_inst(
		.rxp_i(easycdr_rxp), //input rxp_i
		.rxn_i(easycdr_rxn), //input rxn_i
		.rstn_i(reset_n),    //input rstn_i
		.pll_clkin_i  (clock), //input pll_clkin_i
		.pll_clkout0_i(pll_clkout0), //input pll_clkout0_i
		.pll_clkout1_i(pll_clkout1), //input pll_clkout1_i
		.pll_clkout2_i(pll_clkout2), //input pll_clkout2_i
		.pll_clkout3_i(pll_clkout3), //input pll_clkout3_i
		.pll_lock_i   (pll_lock   ), //input pll_lock_i
		.share_clk0_o(easycdr_share_clk0), //output share_clk0_o
		.share_clk1_o(easycdr_share_clk1), //output share_clk1_o
		.share_clk2_o(easycdr_share_clk2), //output share_clk2_o
		.share_clk3_o(easycdr_share_clk3), //output share_clk3_o
		.share_clk4_o(easycdr_share_clk4), //output share_clk4_o
		.share_reset_o(easycdr_share_reset), //output share_reset_o
		.dout_o   (easycdr_dout), //output [15:0] dout_o
		.dout_en_o(easycdr_dout_en), //output dout_en_o
		.error_o  (easycdr_error) //output error_o
	);
    localparam bit [15:0] EASYCDR_ALIGN_PATTERN = 16'hec92;
    logic [1:0]  easycdr_dout_en_reg;
    logic [31:0] easycdr_dout_reg;
    logic [15:0] easycdr_shift;
    logic [15:0] easycdr_dout_shifted;
    always_comb begin
        case(easycdr_shift)
            16'b0000_0000_0000_0001: easycdr_dout_shifted = easycdr_dout_reg[15:0];
            16'b0000_0000_0000_0010: easycdr_dout_shifted = easycdr_dout_reg[16:1];
            16'b0000_0000_0000_0100: easycdr_dout_shifted = easycdr_dout_reg[17:2];
            16'b0000_0000_0000_1000: easycdr_dout_shifted = easycdr_dout_reg[18:3];
            16'b0000_0000_0001_0000: easycdr_dout_shifted = easycdr_dout_reg[19:4];
            16'b0000_0000_0010_0000: easycdr_dout_shifted = easycdr_dout_reg[20:5];
            16'b0000_0000_0100_0000: easycdr_dout_shifted = easycdr_dout_reg[21:6];
            16'b0000_0000_1000_0000: easycdr_dout_shifted = easycdr_dout_reg[22:7];
            16'b0000_0001_0000_0000: easycdr_dout_shifted = easycdr_dout_reg[23:8];
            16'b0000_0010_0000_0000: easycdr_dout_shifted = easycdr_dout_reg[24:9];
            16'b0000_0100_0000_0000: easycdr_dout_shifted = easycdr_dout_reg[25:10];
            16'b0000_1000_0000_0000: easycdr_dout_shifted = easycdr_dout_reg[26:11];
            16'b0001_0000_0000_0000: easycdr_dout_shifted = easycdr_dout_reg[27:12];
            16'b0010_0000_0000_0000: easycdr_dout_shifted = easycdr_dout_reg[28:13];
            16'b0100_0000_0000_0000: easycdr_dout_shifted = easycdr_dout_reg[29:14];
            16'b1000_0000_0000_0000: easycdr_dout_shifted = easycdr_dout_reg[30:15];
            default:                 easycdr_dout_shifted = easycdr_dout_reg[15:0];
        endcase
    end

    always_ff @(posedge easycdr_share_clk4) begin
        if (easycdr_share_reset) begin
            easycdr_dout_en_reg <= 0;
            easycdr_dout_reg <= 0;
        end else begin
            easycdr_dout_en_reg <= {easycdr_dout_en_reg[0], easycdr_dout_en};
            easycdr_dout_reg <= {easycdr_dout_reg[15:0], easycdr_dout};
            if( easycdr_dout_en_reg == 2'b11 && button_s0 ) begin
                if( easycdr_dout_reg[15:0] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_0000_0001;
                end else if( easycdr_dout_reg[16:1] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_0000_0010;
                end else if( easycdr_dout_reg[17:2] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_0000_0100;
                end else if( easycdr_dout_reg[18:3] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_0000_1000;
                end else if( easycdr_dout_reg[19:4] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_0001_0000;
                end else if( easycdr_dout_reg[20:5] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_0010_0000;
                end else if( easycdr_dout_reg[21:6] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_0100_0000;
                end else if( easycdr_dout_reg[22:7] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_1000_0000;
                end else if( easycdr_dout_reg[23:8] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0001_0000_0000;
                end else if( easycdr_dout_reg[24:9] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0010_0000_0000;
                end else if( easycdr_dout_reg[25:10] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0100_0000_0000;
                end else if( easycdr_dout_reg[26:11] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_1000_0000_0000;
                end else if( easycdr_dout_reg[27:12] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0001_0000_0000_0000;
                end else if( easycdr_dout_reg[28:13] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0010_0000_0000_0000;
                end else if( easycdr_dout_reg[29:14] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0100_0000_0000_0000;
                end else if( easycdr_dout_reg[30:15] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b1000_0000_0000_0000;
                end else if( easycdr_dout_reg[31:16] == EASYCDR_ALIGN_PATTERN ) begin
                    easycdr_shift <= 16'b0000_0000_0000_0001;
                end else begin
                    easycdr_shift <= 16'b0000_0000_0000_0000;
                end
            end
        end
    end

    localparam int TXCLOCK_HZ = 125000000;
    localparam int BLINKCOUNTER_MAX = TXCLOCK_HZ / 2;
    logic [$bits(BLINKCOUNTER_MAX)-1:0] blink_counter;
    logic blink = 0;
    logic [7:0] tx_data = 0;
    logic tx_data_align_phase = 0;
    always_ff @(posedge easycdr_share_clk4) begin
        if (easycdr_share_reset) begin
            blink_counter <= 0;
            blink <= 0;
            tx_data <= 0;
            tx_data_align_phase <= 0;
            led <= 0;
        end else begin
            blink_counter <= blink_counter + 1;
            if (blink_counter == BLINKCOUNTER_MAX - 1) begin
                blink_counter <= 0;
                blink <= ~blink;
            end
            if( !button_s0 ) begin
                //tx_data[7:1] <= 0;
                tx_data <= 0;
                tx_data[1] <= ~tx_data[1];
                tx_data[0] <= blink;
            end
            else begin
                tx_data <= tx_data_align_phase ? EASYCDR_ALIGN_PATTERN[15:8] : EASYCDR_ALIGN_PATTERN[7:0];
                tx_data_align_phase <= ~tx_data_align_phase;
            end
            
            if( easycdr_dout_en_reg == 2'b11 ) begin
                led <= easycdr_dout_shifted[5:0];
            end
        end
    end

    logic easycdr_tx;
    OSER8 oser8_tx(
        .Q0       (easycdr_tx         ),
        .Q1       (                   ),
        .D0       (tx_data[0]         ),
        .D1       (tx_data[1]         ),
        .D2       (tx_data[2]         ),
        .D3       (tx_data[3]         ),
        .D4       (tx_data[4]         ),
        .D5       (tx_data[5]         ),
        .D6       (tx_data[6]         ), 
        .D7       (tx_data[7]         ), 
        .TX0      (1'b0               ),
        .TX1      (1'b0               ),
        .TX2      (1'b0               ),
        .TX3      (1'b0               ),
        .PCLK     (easycdr_share_clk4 ),
        .FCLK     (easycdr_share_clk0 ),
        .RESET    (easycdr_share_reset | !reset_n)
    );
    ELVDS_OBUF obuf_tx (
        .I     (easycdr_tx ),
        .O     (easycdr_txp),
        .OB    (easycdr_txn)
    );
endmodule
`default_nettype wire