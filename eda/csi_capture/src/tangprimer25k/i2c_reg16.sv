// SPDX-License-Identifier: BSL-1.0
// Copyright Kenta Ida 2026.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          https://www.boost.org/LICENSE_1_0.txt)
/**
 * @file i2c_reg16.sv
 * @brief I2C master for 16-bit register address / 8-bit data sensors
 *        (CCI: IMX219, OV5647, ...).
 *
 *   write: S dev+W A a[15:8] A a[7:0] A d A P
 *   read : S dev+W A a[15:8] A a[7:0] A Sr dev+R A d N P
 *
 * One transaction per i_start pulse (i_read selects). o_nack is set when
 * any byte the master sent was not acknowledged (the transaction still
 * runs to its STOP). Open-drain pads: o_scl_oe / o_sda_oe = 1 pulls low.
 * SCL = CLOCK_HZ / (4 * QDIV); no clock stretching.
 */
`default_nettype none
module i2c_reg16 #(
    parameter int CLOCK_HZ = 50_000_000,
    parameter int SCL_HZ   = 100_000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        i_start,
    input  wire        i_read,
    input  wire [6:0]  i_dev,
    input  wire [15:0] i_addr,
    input  wire [7:0]  i_wdata,
    output logic       o_busy,
    output logic       o_done,     // pulse
    output logic [7:0] o_rdata,
    output logic       o_nack,
    output logic       o_scl_oe,
    output logic       o_sda_oe,
    input  wire        i_sda,
    input  wire        i_scl
);
    localparam int QDIV = CLOCK_HZ / (4 * SCL_HZ);

    // micro-ops
    typedef enum logic [2:0] { OP_START, OP_WR, OP_RD, OP_STOP, OP_END } op_t;

    logic [3:0]  step;          // index into the transaction program
    logic        rd;
    logic [7:0]  sh;
    logic [3:0]  bitn;          // 0..8 (8 = ACK slot)
    logic [1:0]  q;
    logic [$clog2(QDIV)-1:0] qc;
    logic        run_op;
    logic [1:0]  sda_s, scl_s;

    always_ff @(posedge clk) begin
        sda_s <= {sda_s[0], i_sda};
        scl_s <= {scl_s[0], i_scl};
    end

    // program: step -> op, byte to send
    op_t        op;
    logic [7:0] obyte;
    always_comb begin
        op    = OP_END;
        obyte = 8'h00;
        case (step)
            4'd0: op = OP_START;
            4'd1: begin op = OP_WR; obyte = {i_dev, 1'b0}; end
            4'd2: begin op = OP_WR; obyte = i_addr[15:8]; end
            4'd3: begin op = OP_WR; obyte = i_addr[7:0]; end
            4'd4: if (rd) op = OP_START; else begin op = OP_WR; obyte = i_wdata; end
            4'd5: if (rd) begin op = OP_WR; obyte = {i_dev, 1'b1}; end else op = OP_STOP;
            4'd6: op = rd ? OP_RD : OP_END;
            4'd7: op = rd ? OP_STOP : OP_END;
            default: op = OP_END;
        endcase
    end

    wire qtick = qc == QDIV - 1;

    always_ff @(posedge clk) begin
        o_done <= 1'b0;
        if (rst) begin
            o_busy   <= 1'b0;
            o_nack   <= 1'b0;
            o_rdata  <= 8'h00;
            o_scl_oe <= 1'b0;
            o_sda_oe <= 1'b0;
            step     <= 4'd0;
            run_op   <= 1'b0;
            q        <= 2'd0;
            qc       <= '0;
            bitn     <= 4'd0;
            rd       <= 1'b0;
        end else if (!o_busy) begin
            if (i_start) begin
                o_busy <= 1'b1;
                o_nack <= 1'b0;
                rd     <= i_read;
                step   <= 4'd0;
                run_op <= 1'b0;
            end
        end else if (!run_op) begin
            // load the next op
            if (op == OP_END) begin
                o_busy <= 1'b0;
                o_done <= 1'b1;
            end else begin
                run_op <= 1'b1;
                q      <= 2'd0;
                qc     <= '0;
                bitn   <= 4'd0;
                sh     <= obyte;
            end
        end else begin
            qc <= qtick ? '0 : qc + 1'b1;
            if (qtick) begin
                q <= q + 2'd1;
                // q0: SCL low, set SDA; q1: SCL high; q2: sample / condition; q3: SCL low
                case (op)
                    OP_START: case (q)
                        2'd0: begin o_sda_oe <= 1'b0; end                // SDA high (SCL low or idle)
                        2'd1: begin o_scl_oe <= 1'b0; end                // SCL high
                        2'd2: begin o_sda_oe <= 1'b1; end                // SDA falls while SCL high
                        2'd3: begin o_scl_oe <= 1'b1; run_op <= 1'b0; step <= step + 1'b1; end
                    endcase
                    OP_STOP: case (q)
                        2'd0: begin o_scl_oe <= 1'b1; o_sda_oe <= 1'b1; end
                        2'd1: begin o_scl_oe <= 1'b0; end
                        2'd2: begin o_sda_oe <= 1'b0; end                // SDA rises while SCL high
                        2'd3: begin run_op <= 1'b0; step <= step + 1'b1; end
                    endcase
                    OP_WR, OP_RD: case (q)
                        2'd0: begin
                            o_scl_oe <= 1'b1;
                            if (op == OP_WR) o_sda_oe <= (bitn < 4'd8) ? ~sh[7] : 1'b0;      // release for ACK
                            else             o_sda_oe <= 1'b0;                              // read: released, NACK in the ACK slot
                        end
                        2'd1: o_scl_oe <= 1'b0;
                        2'd2: begin
                            if (op == OP_WR && bitn == 4'd8 && sda_s[1]) o_nack <= 1'b1;
                            if (op == OP_RD && bitn < 4'd8) o_rdata <= {o_rdata[6:0], sda_s[1]};
                        end
                        2'd3: begin
                            o_scl_oe <= 1'b1;
                            sh <= {sh[6:0], 1'b0};
                            if (bitn == 4'd8) begin run_op <= 1'b0; step <= step + 1'b1; end
                            bitn <= bitn + 1'b1;
                        end
                    endcase
                    default: ;
                endcase
            end
        end
    end
endmodule
`default_nettype wire
