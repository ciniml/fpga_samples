/**
 * @file top.sv
 * @brief Top module for PicoRV32 matrix LED example
 */
// Copyright 2022 Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
`default_nettype none

module top (
  input  wire        clk,
  output logic [7:0] anode,
  output logic [7:0] cathode,
  output logic [5:0] led,
  output logic       seven_seg
);
  localparam int IMEM_SIZE_BYTES = 2048;  // BSRAM = 9x16k[bit] = 2048[bytes] wo ECC
  localparam int DMEM_SIZE_BYTES = 2048;  // 32bit RAM requires 2 BSRAM instances

  // Reset generator
  logic reset;
  logic [15:0] reset_reg = '1;
  assign reset = reset_reg[0];
  always_ff @(posedge clk) begin
      reset_reg <= {1'b0, reset_reg[15:1]};
  end

  assign seven_seg = 1;

  // Debug LED
  logic [5:0] led_out;
  assign led = ~led_out;

  function automatic logic [7:0] bitreverse8(input logic [7:0] in);
  begin
    for(int i = 0; i < 8; i++) bitreverse8[7-i] = in[i];
  end
  endfunction

  logic [7:0] data[7:0];
  logic [7:0] row, col;
  assign anode   = ~row;
  assign cathode = col;

  matrix_led_driver inst_0 (
    .clk  (clk),
    .data (data),
    .row  (row),
    .col  (col)
  );

  // picorv32
  logic        mem_valid;
  logic        mem_instr;
  logic        mem_ready;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [ 3:0] mem_wstrb;
  logic [31:0] mem_rdata;

  // Pico Co-Processor Interface (PCPI)
  logic        pcpi_valid;
  logic [31:0] pcpi_insn = 0;
  logic [31:0] pcpi_rs1;
  logic [31:0] pcpi_rs2;
  logic        pcpi_wr = 0;
  logic [31:0] pcpi_rd = 0;
  logic        pcpi_wait = 0;
  logic        pcpi_ready = 0;

  // IRQ Interface
  logic [31:0] irq = 0;
  logic [31:0] eoi;

  picorv32 #(
      .PROGADDR_RESET(32'h8000_0000)
  ) picorv_inst (
      .clk(clk),
      .resetn(!reset),
      
      .mem_valid(mem_valid),
      .mem_instr(mem_instr),
      .mem_ready(mem_ready),
      .mem_addr(mem_addr),
      .mem_wdata(mem_wdata),
      .mem_wstrb(mem_wstrb),
      .mem_rdata(mem_rdata),
      .pcpi_valid(pcpi_valid),
      .pcpi_insn(pcpi_insn),
      .pcpi_rs1(pcpi_rs1),
      .pcpi_rs2(pcpi_rs2),
      .pcpi_wr(pcpi_wr),
      .pcpi_rd(pcpi_rd),
      .pcpi_wait(pcpi_wait),
      .pcpi_ready(pcpi_ready),
      .irq(irq),
      .eoi(eoi)
  );

  // Bus access
  localparam bit[3:0] IBUS_REG_SPACE  = 4'h8;  // 32'h8000_0000 ~ 32'h8fff_ffff
  localparam bit[3:0] DBUS_REG_SPACE  = 4'h3;  // 32'h3000_0000 ~ 32'h3fff_ffff
  localparam bit[5:0] REG_ID          = 8'h00;
  localparam bit[5:0] REG_CLOCK_HZ    = 8'h01;
  localparam bit[5:0] REG_LED         = 8'h02;
  localparam bit[5:0] REG_MATRIX_0    = 8'h03;
  localparam bit[5:0] REG_MATRIX_1    = 8'h04;

  localparam bit[31:0] REG_ID_VALUE = 32'h01234567;

  localparam int IMEM_ADDR_BITS = $clog2(IMEM_SIZE_BYTES);
  localparam int DMEM_ADDR_BITS = $clog2(DMEM_SIZE_BYTES);
  logic [31:0] imem [0:IMEM_SIZE_BYTES/4-1];
  logic [31:0] dmem [0:DMEM_SIZE_BYTES/4-1];
  logic mem_read;
  logic mem_partial_write = 0;
  logic [31:0] mem_write_buffer = 0;
  assign mem_read = ~|mem_wstrb;

  always_ff @(posedge clk) begin
      if( reset ) begin
          mem_ready <= 0;
          mem_partial_write <= 0;
      end
      else begin
          mem_ready <= 0;

          if( mem_valid && !mem_ready) begin
              mem_ready <= 1;
              if( mem_read ) begin
                  if( mem_instr ) begin
                      mem_rdata <= imem[mem_addr[IMEM_ADDR_BITS-1:2]];
                  end
                  else begin
                      if( mem_addr[31:28] == DBUS_REG_SPACE) begin  // Peripheral reg access
                          case (mem_addr[7:2])
                              REG_ID:          mem_rdata <= REG_ID_VALUE;
                              REG_CLOCK_HZ:    mem_rdata <= 32'd27_000_000;
                              REG_LED:         mem_rdata <= {24'b0, led_out};
                              REG_MATRIX_0:    mem_rdata <= {bitreverse8(data[3]), bitreverse8(data[2]), bitreverse8(data[1]), bitreverse8(data[0])};
                              REG_MATRIX_1:    mem_rdata <= {bitreverse8(data[7]), bitreverse8(data[6]), bitreverse8(data[5]), bitreverse8(data[4])};
                              default:         mem_rdata <= 32'hdeadbeef;
                          endcase
                      end
                      else if( mem_addr[31:28] == IBUS_REG_SPACE ) begin
                          mem_rdata <= imem[mem_addr[IMEM_ADDR_BITS-1:2]];
                      end 
                      else begin
                          mem_rdata <= dmem[mem_addr[DMEM_ADDR_BITS-1:2]];
                      end
                  end
              end
              else begin
                  if( mem_addr[31:28] == DBUS_REG_SPACE) begin  // Peripheral reg access
                      case (mem_addr[7:2])
                          REG_LED: led_out <= mem_wdata[5:0];
                          REG_MATRIX_0: begin
                            data[0] <= bitreverse8(mem_wdata[ 0 +: 8]);
                            data[1] <= bitreverse8(mem_wdata[ 8 +: 8]);
                            data[2] <= bitreverse8(mem_wdata[16 +: 8]);
                            data[3] <= bitreverse8(mem_wdata[24 +: 8]);
                          end
                          REG_MATRIX_1: begin
                            data[4] <= bitreverse8(mem_wdata[ 0 +: 8]);
                            data[5] <= bitreverse8(mem_wdata[ 8 +: 8]);
                            data[6] <= bitreverse8(mem_wdata[16 +: 8]);
                            data[7] <= bitreverse8(mem_wdata[24 +: 8]);
                          end
                      endcase
                  end
                  else begin
                      if( ~&mem_wstrb ) begin
                          if( mem_partial_write ) begin
                              logic [31:0] buffer;
                              buffer = mem_write_buffer;
                              if( mem_wstrb[0] ) buffer[ 7: 0] = mem_wdata[ 7: 0];
                              if( mem_wstrb[1] ) buffer[15: 8] = mem_wdata[15: 8];
                              if( mem_wstrb[2] ) buffer[23:16] = mem_wdata[23:16];
                              if( mem_wstrb[3] ) buffer[31:24] = mem_wdata[31:24];

                              mem_partial_write <= 0;
                              dmem[mem_addr[DMEM_ADDR_BITS-1:2]] <= buffer;
                          end
                          else begin
                              mem_ready <= 0;
                              mem_partial_write <= 1;
                              mem_write_buffer <= dmem[mem_addr[DMEM_ADDR_BITS-1:2]];
                          end
                      end
                      else begin
                          dmem[mem_addr[DMEM_ADDR_BITS-1:2]] <= mem_wdata;
                      end
                  end
              end
          end
      end
  end

  initial begin
      $readmemh("../sw/bootrom.hex", imem);
  end
endmodule

module matrix_led_driver (
  input  wire       clk,
  input  wire [7:0] data[7:0],
  output wire [7:0] row,
  output wire [7:0] col
);

  logic [2:0] row_cnt = 'd0;
  logic       overflow;

  assign row = 'b00000001 << row_cnt;
  assign col = {data[row_cnt][7], // CPUとの接続が容易になるように
                data[row_cnt][6], // data[行][列] の順に変更
                data[row_cnt][5],
                data[row_cnt][4],
                data[row_cnt][3],
                data[row_cnt][2],
                data[row_cnt][1],
                data[row_cnt][0]};

  always_ff @ (posedge clk) begin
    if (overflow) begin
      row_cnt <= row_cnt + 'd1;
    end
  end

  timer #(
    .COUNT_MAX (27000)
  ) inst_0 (
    .clk      (clk),
    .overflow (overflow)
  );

endmodule

module timer #(
  parameter COUNT_MAX = 27000000
) (
  input  wire  clk,
  output logic overflow
);

  logic [$clog2(COUNT_MAX+1)-1:0] counter = 'd0;

  always_ff @ (posedge clk) begin
    if (counter == COUNT_MAX) begin
      counter  <= 'd0;
      overflow <= 'd1;
    end else begin
      counter  <= counter + 'd1;
      overflow <= 'd0;
    end
  end

endmodule


`default_nettype wire