/**
* @file top.sv
* @brief Top module for PicoRV32 matrix LED example
*/
// Copyright 2022 Eisuke Mochizuki
//                Kenta IDA
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)
`default_nettype none

module top (
  input  wire        clk,       // クロック入力 (27[MHz])
  output logic [7:0] anode,     // マトリクスLED出力 (アノード)
  output logic [7:0] cathode,   // マトリクスLED出力 (カソード)
  output logic [5:0] led        // デバッグ用LED出力
);
  localparam int IMEM_SIZE_BYTES = 2048;  // BSRAM = 9x2k[bit] = 2048[bytes] wo ECC
  localparam int DMEM_SIZE_BYTES = 2048;
  localparam int CLOCK_HZ = 32'd27_000_000; // クロック周波数
  // リセット回路 (16サイクル)
  logic reset;
  logic [15:0] reset_reg = '1;
  assign reset = reset_reg[0];
  always_ff @(posedge clk) begin
      reset_reg <= {1'b0, reset_reg[15:1]};
  end

  // デバッグLED
  logic [5:0] led_out;
  assign led = ~led_out;  // Active Lowなので反転しておく

  // 8bit ビット反転 bit[0] -> bit[7], bit[1] -> bit[6], ...
  function automatic logic [7:0] bitreverse8(input logic [7:0] in);
    for(int i = 0; i < 8; i++) bitreverse8[7-i] = in[i];
  endfunction

  logic [7:0] data[7:0];  // マトリクスLED出力信号
  logic [7:0] row, col;   // 行出力、列出力
  assign anode   = col;
  assign cathode = ~row;

  // マトリクスLED制御モジュール
  matrix_led_driver matrix_led_inst_0 (
    .clk  (clk),
    .data (data),
    .row  (row),
    .col  (col)
  );

  // PicoRV32 メモリインターフェース信号
  logic        mem_valid;
  logic        mem_instr;
  logic        mem_ready;
  logic [31:0] mem_addr;
  logic [31:0] mem_wdata;
  logic [ 3:0] mem_wstrb;
  logic [31:0] mem_rdata;

  // Pico Co-Processor Interface (PCPI)
  // PicoRV32固有のCPUのコプロセッサを繋ぐインターフェース (未使用)
  logic        pcpi_valid;
  logic [31:0] pcpi_insn = 0;
  logic [31:0] pcpi_rs1;
  logic [31:0] pcpi_rs2;
  logic        pcpi_wr = 0;
  logic [31:0] pcpi_rd = 0;
  logic        pcpi_wait = 0;
  logic        pcpi_ready = 0;

  // 割り込みインターフェース (未使用)
  logic [31:0] irq = 0;
  logic [31:0] eoi;
  // Look-Ahead インターフェース (未使用)
	logic        mem_la_read;
	logic        mem_la_write;
	logic [31:0] mem_la_addr;
	logic [31:0] mem_la_wdata;
	logic [ 3:0] mem_la_wstrb;
  logic        trap;
  // トレースIF (未使用)
	logic        trace_valid;
	logic [35:0] trace_data;

  // PicoRV32のインスタンス
  picorv32 #(
      .PROGADDR_RESET(32'h8000_0000)  // リセットアドレス = 32'h8000_0000
  ) picorv_inst (
    .clk(clk),        // クロック
    .resetn(!reset),  // リセット
    .*
  );

  // バスアクセス周り
  localparam bit[3:0] IBUS_REG_SPACE  = 4'h8;   // 命令メモリ空間  : 32'h8000_0000 ~ 32'h8fff_ffff
  localparam bit[3:0] DBUS_REG_SPACE  = 4'h3;   // データメモリ空間: 32'h3000_0000 ~ 32'h3fff_ffff
  localparam bit[5:0] REG_ID          = 8'h00;  // IDレジスタ
  localparam bit[5:0] REG_CLOCK_HZ    = 8'h01;  // クロック周波数レジスタ
  localparam bit[5:0] REG_LED         = 8'h02;  // LEDレジスタ
  localparam bit[5:0] REG_MATRIX_0    = 8'h03;  // マトリクスLEDレジスタ0
  localparam bit[5:0] REG_MATRIX_1    = 8'h04;  // マトリクスLEDレジスタ1

  localparam bit[31:0] REG_ID_VALUE = 32'h01234567; // IDレジスタの値

  localparam int IMEM_ADDR_BITS = $clog2(IMEM_SIZE_BYTES);  // 命令メモリアドレスビット幅
  localparam int DMEM_ADDR_BITS = $clog2(DMEM_SIZE_BYTES);  // データメモリアドレスビット幅
  logic [31:0] imem [0:IMEM_SIZE_BYTES/4-1];  // 命令メモリ
  logic [31:0] dmem [0:DMEM_SIZE_BYTES/4-1];  // データメモリ
  logic mem_read;                             // メモリ読み出し？
  logic mem_partial_write = 0;                // メモリ部分書き込み？
  logic [31:0] mem_write_buffer = 0;          // 書き込みバッファ
  assign mem_read = mem_wstrb == '0;          // 書き込みストローブが0なら読み出し

  always_ff @(posedge clk) begin
    if( reset ) begin
      mem_ready <= 0;
      mem_partial_write <= 0;
    end
    else begin
      mem_ready <= 0;

      if( mem_valid && !mem_ready) begin
        mem_ready <= 1;
        if( mem_read ) begin  // 読み出し
            if( mem_instr ) begin // 命令メモリ？
                mem_rdata <= imem[mem_addr[IMEM_ADDR_BITS-1:2]];  // 命令メモリから読み出し
            end
            else begin
              if( mem_addr[31:28] == DBUS_REG_SPACE) begin  // ペリフェラルレジスタへのアクセス
                case (mem_addr[7:2])
                  REG_ID:          mem_rdata <= REG_ID_VALUE;     // IDレジスタ
                  REG_CLOCK_HZ:    mem_rdata <= CLOCK_HZ;         // クロックレジスタ
                  REG_LED:         mem_rdata <= {24'b0, led_out}; // LEDレジスタ
                  REG_MATRIX_0:    mem_rdata <= {bitreverse8(data[3]), bitreverse8(data[2]), bitreverse8(data[1]), bitreverse8(data[0])}; // マトリクス0レジスタ
                  REG_MATRIX_1:    mem_rdata <= {bitreverse8(data[7]), bitreverse8(data[6]), bitreverse8(data[5]), bitreverse8(data[4])}; // マトリクス1レジスタ
                  default:         mem_rdata <= 32'hdeadbeef;
                endcase
              end
              else if( mem_addr[31:28] == IBUS_REG_SPACE ) begin
                mem_rdata <= imem[mem_addr[IMEM_ADDR_BITS-1:2]];  // 命令メモリ
              end 
              else begin
                mem_rdata <= dmem[mem_addr[DMEM_ADDR_BITS-1:2]];  // データメモリ
              end
            end
        end
        else begin  // 書き込み
          if( mem_addr[31:28] == DBUS_REG_SPACE) begin  // Peripheral reg access
            case (mem_addr[7:2])
              REG_LED: led_out <= mem_wdata[5:0]; // LEDレジスタ
              REG_MATRIX_0: begin
                data[0] <= bitreverse8(mem_wdata[ 0 +: 8]); // マトリクス1行目
                data[1] <= bitreverse8(mem_wdata[ 8 +: 8]); // マトリクス2行目
                data[2] <= bitreverse8(mem_wdata[16 +: 8]); // マトリクス3行目
                data[3] <= bitreverse8(mem_wdata[24 +: 8]); // マトリクス4行目
              end
              REG_MATRIX_1: begin
                data[4] <= bitreverse8(mem_wdata[ 0 +: 8]); // マトリクス5行目
                data[5] <= bitreverse8(mem_wdata[ 8 +: 8]); // マトリクス6行目
                data[6] <= bitreverse8(mem_wdata[16 +: 8]); // マトリクス7行目
                data[7] <= bitreverse8(mem_wdata[24 +: 8]); // マトリクス8行目
              end
            endcase
          end
          else begin
            if( ~&mem_wstrb ) begin // WSTRBが一部0なのでバイト書き込み
              if( mem_partial_write ) begin // パーシャルライトの書き込みフェーズ
                logic [31:0] buffer;
                buffer = mem_write_buffer;  // WSTRBのビットが立っているバイトを書き込みデータで更新
                if( mem_wstrb[0] ) buffer[ 7: 0] = mem_wdata[ 7: 0];
                if( mem_wstrb[1] ) buffer[15: 8] = mem_wdata[15: 8];
                if( mem_wstrb[2] ) buffer[23:16] = mem_wdata[23:16];
                if( mem_wstrb[3] ) buffer[31:24] = mem_wdata[31:24];

                mem_partial_write <= 0; // パーシャルライトの書き込みフェーズを終了
                dmem[mem_addr[DMEM_ADDR_BITS-1:2]] <= buffer; // 実際にメモリに書き込み
              end
              else begin
                mem_ready <= 0; 
                mem_partial_write <= 1; // 書き込みフェーズを開始
                mem_write_buffer <= dmem[mem_addr[DMEM_ADDR_BITS-1:2]]; // バッファに対象アドレスの内容を読み出し
              end
            end
            else begin  // WSTRBが4'b1111なのでワード書き込み
              dmem[mem_addr[DMEM_ADDR_BITS-1:2]] <= mem_wdata;
            end
          end
        end
      end
    end
  end

  initial begin
      $readmemh("../sw/bootrom.hex", imem); // プログラムをimemに読み込んでおく
  end
endmodule

// マトリクスLEDドライバ、タイマーモジュールは基礎編3章とdataの持ち方以外は同じ
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