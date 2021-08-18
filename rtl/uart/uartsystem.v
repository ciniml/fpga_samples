module UartRx(
  input        clock,
  input        reset,
  input        io_out_ready,
  output       io_out_valid,
  output [7:0] io_out_bits,
  input        io_rx
);
`ifdef RANDOMIZE_REG_INIT
  reg [31:0] _RAND_0;
  reg [31:0] _RAND_1;
  reg [31:0] _RAND_2;
  reg [31:0] _RAND_3;
  reg [31:0] _RAND_4;
  reg [31:0] _RAND_5;
  reg [31:0] _RAND_6;
  reg [31:0] _RAND_7;
  reg [31:0] _RAND_8;
  reg [31:0] _RAND_9;
  reg [31:0] _RAND_10;
  reg [31:0] _RAND_11;
  reg [31:0] _RAND_12;
  reg [31:0] _RAND_13;
  reg [31:0] _RAND_14;
  reg [31:0] _RAND_15;
`endif // RANDOMIZE_REG_INIT
  reg [8:0] rateCounter; // @[uart.scala 44:30]
  reg [2:0] bitCounter; // @[uart.scala 45:29]
  reg  bits_1; // @[uart.scala 46:19]
  reg  bits_2; // @[uart.scala 46:19]
  reg  bits_3; // @[uart.scala 46:19]
  reg  bits_4; // @[uart.scala 46:19]
  reg  bits_5; // @[uart.scala 46:19]
  reg  bits_6; // @[uart.scala 46:19]
  reg  bits_7; // @[uart.scala 46:19]
  reg  rxRegs_0; // @[uart.scala 47:25]
  reg  rxRegs_1; // @[uart.scala 47:25]
  reg  rxRegs_2; // @[uart.scala 47:25]
  reg  rxRegs_3; // @[uart.scala 47:25]
  reg  running; // @[uart.scala 49:26]
  reg  outValid; // @[uart.scala 51:27]
  reg [7:0] outBits; // @[uart.scala 52:22]
  wire  _GEN_0 = outValid & io_out_ready ? 1'h0 : outValid; // @[uart.scala 57:32 uart.scala 58:18 uart.scala 51:27]
  wire  _GEN_3 = ~rxRegs_1 & rxRegs_0 | running; // @[uart.scala 68:39 uart.scala 71:21 uart.scala 49:26]
  wire [7:0] _outBits_T = {rxRegs_0,bits_7,bits_6,bits_5,bits_4,bits_3,bits_2,bits_1}; // @[Cat.scala 30:58]
  wire [2:0] _bitCounter_T_1 = bitCounter - 3'h1; // @[uart.scala 84:42]
  wire  _GEN_4 = bitCounter == 3'h0 | _GEN_0; // @[uart.scala 77:38 uart.scala 78:26]
  wire [8:0] _rateCounter_T_1 = rateCounter - 9'h1; // @[uart.scala 87:40]
  assign io_out_valid = outValid; // @[uart.scala 54:18]
  assign io_out_bits = outBits; // @[uart.scala 55:17]
  always @(posedge clock) begin
    if (reset) begin // @[uart.scala 44:30]
      rateCounter <= 9'h0; // @[uart.scala 44:30]
    end else if (~running) begin // @[uart.scala 67:20]
      if (~rxRegs_1 & rxRegs_0) begin // @[uart.scala 68:39]
        rateCounter <= 9'h137; // @[uart.scala 69:25]
      end
    end else if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
      if (!(bitCounter == 3'h0)) begin // @[uart.scala 77:38]
        rateCounter <= 9'hcf; // @[uart.scala 83:29]
      end
    end else begin
      rateCounter <= _rateCounter_T_1; // @[uart.scala 87:25]
    end
    if (reset) begin // @[uart.scala 45:29]
      bitCounter <= 3'h0; // @[uart.scala 45:29]
    end else if (~running) begin // @[uart.scala 67:20]
      if (~rxRegs_1 & rxRegs_0) begin // @[uart.scala 68:39]
        bitCounter <= 3'h7; // @[uart.scala 70:24]
      end
    end else if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
      if (!(bitCounter == 3'h0)) begin // @[uart.scala 77:38]
        bitCounter <= _bitCounter_T_1; // @[uart.scala 84:28]
      end
    end
    if (!(~running)) begin // @[uart.scala 67:20]
      if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
        bits_1 <= bits_2; // @[uart.scala 76:58]
      end
    end
    if (!(~running)) begin // @[uart.scala 67:20]
      if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
        bits_2 <= bits_3; // @[uart.scala 76:58]
      end
    end
    if (!(~running)) begin // @[uart.scala 67:20]
      if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
        bits_3 <= bits_4; // @[uart.scala 76:58]
      end
    end
    if (!(~running)) begin // @[uart.scala 67:20]
      if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
        bits_4 <= bits_5; // @[uart.scala 76:58]
      end
    end
    if (!(~running)) begin // @[uart.scala 67:20]
      if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
        bits_5 <= bits_6; // @[uart.scala 76:58]
      end
    end
    if (!(~running)) begin // @[uart.scala 67:20]
      if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
        bits_6 <= bits_7; // @[uart.scala 76:58]
      end
    end
    if (!(~running)) begin // @[uart.scala 67:20]
      if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
        bits_7 <= rxRegs_0; // @[uart.scala 75:34]
      end
    end
    if (reset) begin // @[uart.scala 47:25]
      rxRegs_0 <= 1'h0; // @[uart.scala 47:25]
    end else begin
      rxRegs_0 <= rxRegs_1; // @[uart.scala 63:52]
    end
    if (reset) begin // @[uart.scala 47:25]
      rxRegs_1 <= 1'h0; // @[uart.scala 47:25]
    end else begin
      rxRegs_1 <= rxRegs_2; // @[uart.scala 63:52]
    end
    if (reset) begin // @[uart.scala 47:25]
      rxRegs_2 <= 1'h0; // @[uart.scala 47:25]
    end else begin
      rxRegs_2 <= rxRegs_3; // @[uart.scala 63:52]
    end
    if (reset) begin // @[uart.scala 47:25]
      rxRegs_3 <= 1'h0; // @[uart.scala 47:25]
    end else begin
      rxRegs_3 <= io_rx; // @[uart.scala 62:26]
    end
    if (reset) begin // @[uart.scala 49:26]
      running <= 1'h0; // @[uart.scala 49:26]
    end else if (~running) begin // @[uart.scala 67:20]
      running <= _GEN_3;
    end else if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
      if (bitCounter == 3'h0) begin // @[uart.scala 77:38]
        running <= 1'h0; // @[uart.scala 81:25]
      end
    end
    if (reset) begin // @[uart.scala 51:27]
      outValid <= 1'h0; // @[uart.scala 51:27]
    end else if (~running) begin // @[uart.scala 67:20]
      outValid <= _GEN_0;
    end else if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
      outValid <= _GEN_4;
    end else begin
      outValid <= _GEN_0;
    end
    if (!(~running)) begin // @[uart.scala 67:20]
      if (rateCounter == 9'h0) begin // @[uart.scala 74:35]
        if (bitCounter == 3'h0) begin // @[uart.scala 77:38]
          outBits <= _outBits_T; // @[uart.scala 79:25]
        end
      end
    end
  end
// Register and memory initialization
`ifdef RANDOMIZE_GARBAGE_ASSIGN
`define RANDOMIZE
`endif
`ifdef RANDOMIZE_INVALID_ASSIGN
`define RANDOMIZE
`endif
`ifdef RANDOMIZE_REG_INIT
`define RANDOMIZE
`endif
`ifdef RANDOMIZE_MEM_INIT
`define RANDOMIZE
`endif
`ifndef RANDOM
`define RANDOM $random
`endif
`ifdef RANDOMIZE_MEM_INIT
  integer initvar;
`endif
`ifndef SYNTHESIS
`ifdef FIRRTL_BEFORE_INITIAL
`FIRRTL_BEFORE_INITIAL
`endif
initial begin
  `ifdef RANDOMIZE
    `ifdef INIT_RANDOM
      `INIT_RANDOM
    `endif
    `ifndef VERILATOR
      `ifdef RANDOMIZE_DELAY
        #`RANDOMIZE_DELAY begin end
      `else
        #0.002 begin end
      `endif
    `endif
`ifdef RANDOMIZE_REG_INIT
  _RAND_0 = {1{`RANDOM}};
  rateCounter = _RAND_0[8:0];
  _RAND_1 = {1{`RANDOM}};
  bitCounter = _RAND_1[2:0];
  _RAND_2 = {1{`RANDOM}};
  bits_1 = _RAND_2[0:0];
  _RAND_3 = {1{`RANDOM}};
  bits_2 = _RAND_3[0:0];
  _RAND_4 = {1{`RANDOM}};
  bits_3 = _RAND_4[0:0];
  _RAND_5 = {1{`RANDOM}};
  bits_4 = _RAND_5[0:0];
  _RAND_6 = {1{`RANDOM}};
  bits_5 = _RAND_6[0:0];
  _RAND_7 = {1{`RANDOM}};
  bits_6 = _RAND_7[0:0];
  _RAND_8 = {1{`RANDOM}};
  bits_7 = _RAND_8[0:0];
  _RAND_9 = {1{`RANDOM}};
  rxRegs_0 = _RAND_9[0:0];
  _RAND_10 = {1{`RANDOM}};
  rxRegs_1 = _RAND_10[0:0];
  _RAND_11 = {1{`RANDOM}};
  rxRegs_2 = _RAND_11[0:0];
  _RAND_12 = {1{`RANDOM}};
  rxRegs_3 = _RAND_12[0:0];
  _RAND_13 = {1{`RANDOM}};
  running = _RAND_13[0:0];
  _RAND_14 = {1{`RANDOM}};
  outValid = _RAND_14[0:0];
  _RAND_15 = {1{`RANDOM}};
  outBits = _RAND_15[7:0];
`endif // RANDOMIZE_REG_INIT
  `endif // RANDOMIZE
end // initial
`ifdef FIRRTL_AFTER_INITIAL
`FIRRTL_AFTER_INITIAL
`endif
`endif // SYNTHESIS
endmodule
module UartTx(
  input        clock,
  input        reset,
  output       io_in_ready,
  input        io_in_valid,
  input  [7:0] io_in_bits,
  output       io_tx
);
`ifdef RANDOMIZE_REG_INIT
  reg [31:0] _RAND_0;
  reg [31:0] _RAND_1;
  reg [31:0] _RAND_2;
  reg [31:0] _RAND_3;
  reg [31:0] _RAND_4;
  reg [31:0] _RAND_5;
  reg [31:0] _RAND_6;
  reg [31:0] _RAND_7;
  reg [31:0] _RAND_8;
  reg [31:0] _RAND_9;
  reg [31:0] _RAND_10;
  reg [31:0] _RAND_11;
`endif // RANDOMIZE_REG_INIT
  reg [7:0] rateCounter; // @[uart.scala 12:30]
  reg [3:0] bitCounter; // @[uart.scala 13:29]
  reg  bits_0; // @[uart.scala 14:19]
  reg  bits_1; // @[uart.scala 14:19]
  reg  bits_2; // @[uart.scala 14:19]
  reg  bits_3; // @[uart.scala 14:19]
  reg  bits_4; // @[uart.scala 14:19]
  reg  bits_5; // @[uart.scala 14:19]
  reg  bits_6; // @[uart.scala 14:19]
  reg  bits_7; // @[uart.scala 14:19]
  reg  bits_8; // @[uart.scala 14:19]
  reg  bits_9; // @[uart.scala 14:19]
  wire [9:0] _T_1 = {1'h1,io_in_bits,1'h0}; // @[Cat.scala 30:58]
  wire  _GEN_0 = io_in_valid & io_in_ready ? _T_1[0] : bits_0; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire  _GEN_1 = io_in_valid & io_in_ready ? _T_1[1] : bits_1; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire  _GEN_2 = io_in_valid & io_in_ready ? _T_1[2] : bits_2; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire  _GEN_3 = io_in_valid & io_in_ready ? _T_1[3] : bits_3; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire  _GEN_4 = io_in_valid & io_in_ready ? _T_1[4] : bits_4; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire  _GEN_5 = io_in_valid & io_in_ready ? _T_1[5] : bits_5; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire  _GEN_6 = io_in_valid & io_in_ready ? _T_1[6] : bits_6; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire  _GEN_7 = io_in_valid & io_in_ready ? _T_1[7] : bits_7; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire  _GEN_8 = io_in_valid & io_in_ready ? _T_1[8] : bits_8; // @[uart.scala 19:38 uart.scala 20:14 uart.scala 14:19]
  wire [3:0] _GEN_10 = io_in_valid & io_in_ready ? 4'ha : bitCounter; // @[uart.scala 19:38 uart.scala 21:20 uart.scala 13:29]
  wire [3:0] _bitCounter_T_1 = bitCounter - 4'h1; // @[uart.scala 29:38]
  wire [7:0] _rateCounter_T_1 = rateCounter - 8'h1; // @[uart.scala 32:40]
  assign io_in_ready = bitCounter == 4'h0; // @[uart.scala 17:31]
  assign io_tx = bitCounter == 4'h0 | bits_0; // @[uart.scala 16:33]
  always @(posedge clock) begin
    if (reset) begin // @[uart.scala 12:30]
      rateCounter <= 8'h0; // @[uart.scala 12:30]
    end else if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        rateCounter <= 8'hcf; // @[uart.scala 30:25]
      end else begin
        rateCounter <= _rateCounter_T_1; // @[uart.scala 32:25]
      end
    end else if (io_in_valid & io_in_ready) begin // @[uart.scala 19:38]
      rateCounter <= 8'hcf; // @[uart.scala 22:21]
    end
    if (reset) begin // @[uart.scala 13:29]
      bitCounter <= 4'h0; // @[uart.scala 13:29]
    end else if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bitCounter <= _bitCounter_T_1; // @[uart.scala 29:24]
      end else begin
        bitCounter <= _GEN_10;
      end
    end else begin
      bitCounter <= _GEN_10;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_0 <= bits_1; // @[uart.scala 28:54]
      end else begin
        bits_0 <= _GEN_0;
      end
    end else begin
      bits_0 <= _GEN_0;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_1 <= bits_2; // @[uart.scala 28:54]
      end else begin
        bits_1 <= _GEN_1;
      end
    end else begin
      bits_1 <= _GEN_1;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_2 <= bits_3; // @[uart.scala 28:54]
      end else begin
        bits_2 <= _GEN_2;
      end
    end else begin
      bits_2 <= _GEN_2;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_3 <= bits_4; // @[uart.scala 28:54]
      end else begin
        bits_3 <= _GEN_3;
      end
    end else begin
      bits_3 <= _GEN_3;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_4 <= bits_5; // @[uart.scala 28:54]
      end else begin
        bits_4 <= _GEN_4;
      end
    end else begin
      bits_4 <= _GEN_4;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_5 <= bits_6; // @[uart.scala 28:54]
      end else begin
        bits_5 <= _GEN_5;
      end
    end else begin
      bits_5 <= _GEN_5;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_6 <= bits_7; // @[uart.scala 28:54]
      end else begin
        bits_6 <= _GEN_6;
      end
    end else begin
      bits_6 <= _GEN_6;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_7 <= bits_8; // @[uart.scala 28:54]
      end else begin
        bits_7 <= _GEN_7;
      end
    end else begin
      bits_7 <= _GEN_7;
    end
    if (bitCounter > 4'h0) begin // @[uart.scala 25:30]
      if (rateCounter == 8'h0) begin // @[uart.scala 26:35]
        bits_8 <= bits_9; // @[uart.scala 28:54]
      end else begin
        bits_8 <= _GEN_8;
      end
    end else begin
      bits_8 <= _GEN_8;
    end
    if (io_in_valid & io_in_ready) begin // @[uart.scala 19:38]
      bits_9 <= _T_1[9]; // @[uart.scala 20:14]
    end
  end
// Register and memory initialization
`ifdef RANDOMIZE_GARBAGE_ASSIGN
`define RANDOMIZE
`endif
`ifdef RANDOMIZE_INVALID_ASSIGN
`define RANDOMIZE
`endif
`ifdef RANDOMIZE_REG_INIT
`define RANDOMIZE
`endif
`ifdef RANDOMIZE_MEM_INIT
`define RANDOMIZE
`endif
`ifndef RANDOM
`define RANDOM $random
`endif
`ifdef RANDOMIZE_MEM_INIT
  integer initvar;
`endif
`ifndef SYNTHESIS
`ifdef FIRRTL_BEFORE_INITIAL
`FIRRTL_BEFORE_INITIAL
`endif
initial begin
  `ifdef RANDOMIZE
    `ifdef INIT_RANDOM
      `INIT_RANDOM
    `endif
    `ifndef VERILATOR
      `ifdef RANDOMIZE_DELAY
        #`RANDOMIZE_DELAY begin end
      `else
        #0.002 begin end
      `endif
    `endif
`ifdef RANDOMIZE_REG_INIT
  _RAND_0 = {1{`RANDOM}};
  rateCounter = _RAND_0[7:0];
  _RAND_1 = {1{`RANDOM}};
  bitCounter = _RAND_1[3:0];
  _RAND_2 = {1{`RANDOM}};
  bits_0 = _RAND_2[0:0];
  _RAND_3 = {1{`RANDOM}};
  bits_1 = _RAND_3[0:0];
  _RAND_4 = {1{`RANDOM}};
  bits_2 = _RAND_4[0:0];
  _RAND_5 = {1{`RANDOM}};
  bits_3 = _RAND_5[0:0];
  _RAND_6 = {1{`RANDOM}};
  bits_4 = _RAND_6[0:0];
  _RAND_7 = {1{`RANDOM}};
  bits_5 = _RAND_7[0:0];
  _RAND_8 = {1{`RANDOM}};
  bits_6 = _RAND_8[0:0];
  _RAND_9 = {1{`RANDOM}};
  bits_7 = _RAND_9[0:0];
  _RAND_10 = {1{`RANDOM}};
  bits_8 = _RAND_10[0:0];
  _RAND_11 = {1{`RANDOM}};
  bits_9 = _RAND_11[0:0];
`endif // RANDOMIZE_REG_INIT
  `endif // RANDOMIZE
end // initial
`ifdef FIRRTL_AFTER_INITIAL
`FIRRTL_AFTER_INITIAL
`endif
`endif // SYNTHESIS
endmodule
module UartSystem(
  input   clock,
  input   resetn,
  output  tx,
  input   rx
);
  wire  uartRx_clock; // @[sample_uart.scala 18:24]
  wire  uartRx_reset; // @[sample_uart.scala 18:24]
  wire  uartRx_io_out_ready; // @[sample_uart.scala 18:24]
  wire  uartRx_io_out_valid; // @[sample_uart.scala 18:24]
  wire [7:0] uartRx_io_out_bits; // @[sample_uart.scala 18:24]
  wire  uartRx_io_rx; // @[sample_uart.scala 18:24]
  wire  uartTx_clock; // @[sample_uart.scala 19:24]
  wire  uartTx_reset; // @[sample_uart.scala 19:24]
  wire  uartTx_io_in_ready; // @[sample_uart.scala 19:24]
  wire  uartTx_io_in_valid; // @[sample_uart.scala 19:24]
  wire [7:0] uartTx_io_in_bits; // @[sample_uart.scala 19:24]
  wire  uartTx_io_tx; // @[sample_uart.scala 19:24]
  UartRx uartRx ( // @[sample_uart.scala 18:24]
    .clock(uartRx_clock),
    .reset(uartRx_reset),
    .io_out_ready(uartRx_io_out_ready),
    .io_out_valid(uartRx_io_out_valid),
    .io_out_bits(uartRx_io_out_bits),
    .io_rx(uartRx_io_rx)
  );
  UartTx uartTx ( // @[sample_uart.scala 19:24]
    .clock(uartTx_clock),
    .reset(uartTx_reset),
    .io_in_ready(uartTx_io_in_ready),
    .io_in_valid(uartTx_io_in_valid),
    .io_in_bits(uartTx_io_in_bits),
    .io_tx(uartTx_io_tx)
  );
  assign tx = uartTx_io_tx; // @[sample_uart.scala 23:8]
  assign uartRx_clock = clock;
  assign uartRx_reset = ~resetn; // @[sample_uart.scala 15:28]
  assign uartRx_io_out_ready = uartTx_io_in_ready; // @[sample_uart.scala 21:19]
  assign uartRx_io_rx = rx; // @[sample_uart.scala 24:8]
  assign uartTx_clock = clock;
  assign uartTx_reset = ~resetn; // @[sample_uart.scala 15:28]
  assign uartTx_io_in_valid = uartRx_io_out_valid; // @[sample_uart.scala 21:19]
  assign uartTx_io_in_bits = uartRx_io_out_bits; // @[sample_uart.scala 21:19]
endmodule
