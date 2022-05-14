module SPIMaster(
  input        clock,
  input        reset,
  input        io_spi_miso,
  output       io_spi_mosi,
  output       io_spi_cs,
  output       io_spi_sck,
  output       io_tx_ready,
  input        io_tx_valid,
  input  [7:0] io_tx_bits,
  input        io_rx_ready,
  output       io_rx_valid,
  output [7:0] io_rx_bits,
  input        io_cs
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
`endif // RANDOMIZE_REG_INIT
  reg [7:0] shiftReg; // @[spi_master.scala 27:27]
  reg  misoReg; // @[spi_master.scala 28:26]
  reg [7:0] rxData; // @[spi_master.scala 29:25]
  reg  rxValid; // @[spi_master.scala 30:26]
  reg  running; // @[spi_master.scala 31:26]
  reg [7:0] bitCounter; // @[spi_master.scala 33:29]
  reg  sck; // @[spi_master.scala 34:22]
  reg  cs; // @[spi_master.scala 35:21]
  reg  csDelay; // @[spi_master.scala 36:26]
  reg  dividerCounter; // @[spi_master.scala 37:33]
  wire  _GEN_0 = rxValid & io_rx_ready ? 1'h0 : rxValid; // @[spi_master.scala 39:36 spi_master.scala 40:17 spi_master.scala 30:26]
  wire  _dividerCounter_T_1 = dividerCounter + 1'h1; // @[spi_master.scala 55:46]
  wire  _GEN_1 = dividerCounter < 1'h1 & dividerCounter + 1'h1; // @[spi_master.scala 54:51 spi_master.scala 55:28 spi_master.scala 58:28]
  wire  _GEN_2 = dividerCounter < 1'h1 & csDelay; // @[spi_master.scala 54:51 spi_master.scala 36:26 spi_master.scala 57:21]
  wire  _T_12 = ~dividerCounter; // @[spi_master.scala 61:29]
  wire [6:0] nextShiftReg_hi = shiftReg[6:0]; // @[spi_master.scala 64:48]
  wire [7:0] nextShiftReg = {nextShiftReg_hi,misoReg}; // @[Cat.scala 30:58]
  wire [7:0] _GEN_3 = bitCounter[0] ? nextShiftReg : rxData; // @[spi_master.scala 65:37 spi_master.scala 66:28 spi_master.scala 29:25]
  wire  _GEN_4 = bitCounter[0] | _GEN_0; // @[spi_master.scala 65:37 spi_master.scala 67:29]
  wire  _GEN_5 = bitCounter[0] ? 1'h0 : running; // @[spi_master.scala 65:37 spi_master.scala 68:29 spi_master.scala 31:26]
  wire  _GEN_6 = bitCounter[0] ? ~io_tx_valid : cs; // @[spi_master.scala 65:37 spi_master.scala 69:24 spi_master.scala 35:21]
  wire [7:0] _bitCounter_T = {{1'd0}, bitCounter[7:1]}; // @[spi_master.scala 72:42]
  wire [7:0] _GEN_7 = sck ? _GEN_3 : rxData; // @[spi_master.scala 63:25 spi_master.scala 29:25]
  wire  _GEN_8 = sck ? _GEN_4 : _GEN_0; // @[spi_master.scala 63:25]
  wire  _GEN_9 = sck ? _GEN_5 : running; // @[spi_master.scala 63:25 spi_master.scala 31:26]
  wire  _GEN_10 = sck ? _GEN_6 : cs; // @[spi_master.scala 63:25 spi_master.scala 35:21]
  wire [7:0] _GEN_11 = sck ? nextShiftReg : shiftReg; // @[spi_master.scala 63:25 spi_master.scala 71:26 spi_master.scala 27:27]
  wire [7:0] _GEN_12 = sck ? _bitCounter_T : bitCounter; // @[spi_master.scala 63:25 spi_master.scala 72:28 spi_master.scala 33:29]
  wire  _GEN_13 = sck ? misoReg : io_spi_miso; // @[spi_master.scala 63:25 spi_master.scala 28:26 spi_master.scala 74:25]
  wire  _GEN_14 = _T_12 ? 1'h0 : _dividerCounter_T_1; // @[spi_master.scala 77:66 spi_master.scala 78:28 spi_master.scala 80:28]
  wire  _GEN_15 = ~dividerCounter ? ~sck : sck; // @[spi_master.scala 61:38 spi_master.scala 62:17 spi_master.scala 34:22]
  wire [7:0] _GEN_16 = ~dividerCounter ? _GEN_7 : rxData; // @[spi_master.scala 61:38 spi_master.scala 29:25]
  wire  _GEN_17 = ~dividerCounter ? _GEN_8 : _GEN_0; // @[spi_master.scala 61:38]
  wire  _GEN_18 = ~dividerCounter ? _GEN_9 : running; // @[spi_master.scala 61:38 spi_master.scala 31:26]
  wire  _GEN_19 = ~dividerCounter ? _GEN_10 : cs; // @[spi_master.scala 61:38 spi_master.scala 35:21]
  wire [7:0] _GEN_20 = ~dividerCounter ? _GEN_11 : shiftReg; // @[spi_master.scala 61:38 spi_master.scala 27:27]
  wire [7:0] _GEN_21 = ~dividerCounter ? _GEN_12 : bitCounter; // @[spi_master.scala 61:38 spi_master.scala 33:29]
  wire  _GEN_22 = ~dividerCounter ? _GEN_13 : misoReg; // @[spi_master.scala 61:38 spi_master.scala 28:26]
  wire  _GEN_23 = ~dividerCounter ? _dividerCounter_T_1 : _GEN_14; // @[spi_master.scala 61:38 spi_master.scala 76:28]
  wire  _GEN_27 = running & ~cs ? _GEN_18 : running; // @[spi_master.scala 60:34 spi_master.scala 31:26]
  wire  _GEN_28 = running & ~cs ? _GEN_19 : cs; // @[spi_master.scala 60:34 spi_master.scala 35:21]
  wire  _GEN_38 = running & csDelay ? running : _GEN_27; // @[spi_master.scala 53:39 spi_master.scala 31:26]
  wire  _GEN_39 = running & csDelay ? cs : _GEN_28; // @[spi_master.scala 53:39 spi_master.scala 35:21]
  wire  _GEN_46 = ~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs | _GEN_38; // @[spi_master.scala 46:80 spi_master.scala 50:17]
  wire  _GEN_48 = ~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs ? 1'h0 : _GEN_39; // @[spi_master.scala 46:80 spi_master.scala 52:12]
  assign io_spi_mosi = shiftReg[7]; // @[spi_master.scala 85:28]
  assign io_spi_cs = io_cs; // @[spi_master.scala 90:19]
  assign io_spi_sck = sck; // @[spi_master.scala 84:16]
  assign io_tx_ready = ~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs; // @[spi_master.scala 46:63]
  assign io_rx_valid = rxValid; // @[spi_master.scala 87:17]
  assign io_rx_bits = rxData; // @[spi_master.scala 86:16]
  always @(posedge clock) begin
    if (reset) begin // @[spi_master.scala 27:27]
      shiftReg <= 8'h0; // @[spi_master.scala 27:27]
    end else if (~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs) begin // @[spi_master.scala 46:80]
      shiftReg <= io_tx_bits; // @[spi_master.scala 48:18]
    end else if (!(running & csDelay)) begin // @[spi_master.scala 53:39]
      if (running & ~cs) begin // @[spi_master.scala 60:34]
        shiftReg <= _GEN_20;
      end
    end
    if (reset) begin // @[spi_master.scala 28:26]
      misoReg <= 1'h0; // @[spi_master.scala 28:26]
    end else if (!(~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs)) begin // @[spi_master.scala 46:80]
      if (!(running & csDelay)) begin // @[spi_master.scala 53:39]
        if (running & ~cs) begin // @[spi_master.scala 60:34]
          misoReg <= _GEN_22;
        end
      end
    end
    if (reset) begin // @[spi_master.scala 29:25]
      rxData <= 8'h0; // @[spi_master.scala 29:25]
    end else if (!(~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs)) begin // @[spi_master.scala 46:80]
      if (!(running & csDelay)) begin // @[spi_master.scala 53:39]
        if (running & ~cs) begin // @[spi_master.scala 60:34]
          rxData <= _GEN_16;
        end
      end
    end
    if (reset) begin // @[spi_master.scala 30:26]
      rxValid <= 1'h0; // @[spi_master.scala 30:26]
    end else if (~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs) begin // @[spi_master.scala 46:80]
      rxValid <= _GEN_0;
    end else if (running & csDelay) begin // @[spi_master.scala 53:39]
      rxValid <= _GEN_0;
    end else if (running & ~cs) begin // @[spi_master.scala 60:34]
      rxValid <= _GEN_17;
    end else begin
      rxValid <= _GEN_0;
    end
    if (reset) begin // @[spi_master.scala 31:26]
      running <= 1'h0; // @[spi_master.scala 31:26]
    end else begin
      running <= _GEN_46;
    end
    if (reset) begin // @[spi_master.scala 33:29]
      bitCounter <= 8'h0; // @[spi_master.scala 33:29]
    end else if (~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs) begin // @[spi_master.scala 46:80]
      bitCounter <= 8'h80; // @[spi_master.scala 49:20]
    end else if (!(running & csDelay)) begin // @[spi_master.scala 53:39]
      if (running & ~cs) begin // @[spi_master.scala 60:34]
        bitCounter <= _GEN_21;
      end
    end
    if (reset) begin // @[spi_master.scala 34:22]
      sck <= 1'h0; // @[spi_master.scala 34:22]
    end else if (!(~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs)) begin // @[spi_master.scala 46:80]
      if (!(running & csDelay)) begin // @[spi_master.scala 53:39]
        if (running & ~cs) begin // @[spi_master.scala 60:34]
          sck <= _GEN_15;
        end
      end
    end
    cs <= reset | _GEN_48; // @[spi_master.scala 35:21 spi_master.scala 35:21]
    if (reset) begin // @[spi_master.scala 36:26]
      csDelay <= 1'h0; // @[spi_master.scala 36:26]
    end else if (~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs) begin // @[spi_master.scala 46:80]
      csDelay <= cs; // @[spi_master.scala 51:17]
    end else if (running & csDelay) begin // @[spi_master.scala 53:39]
      csDelay <= _GEN_2;
    end
    if (reset) begin // @[spi_master.scala 37:33]
      dividerCounter <= 1'h0; // @[spi_master.scala 37:33]
    end else if (!(~running & io_tx_valid & (~rxValid | io_rx_ready) & ~io_cs)) begin // @[spi_master.scala 46:80]
      if (running & csDelay) begin // @[spi_master.scala 53:39]
        dividerCounter <= _GEN_1;
      end else if (running & ~cs) begin // @[spi_master.scala 60:34]
        dividerCounter <= _GEN_23;
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
  shiftReg = _RAND_0[7:0];
  _RAND_1 = {1{`RANDOM}};
  misoReg = _RAND_1[0:0];
  _RAND_2 = {1{`RANDOM}};
  rxData = _RAND_2[7:0];
  _RAND_3 = {1{`RANDOM}};
  rxValid = _RAND_3[0:0];
  _RAND_4 = {1{`RANDOM}};
  running = _RAND_4[0:0];
  _RAND_5 = {1{`RANDOM}};
  bitCounter = _RAND_5[7:0];
  _RAND_6 = {1{`RANDOM}};
  sck = _RAND_6[0:0];
  _RAND_7 = {1{`RANDOM}};
  cs = _RAND_7[0:0];
  _RAND_8 = {1{`RANDOM}};
  csDelay = _RAND_8[0:0];
  _RAND_9 = {1{`RANDOM}};
  dividerCounter = _RAND_9[0:0];
`endif // RANDOMIZE_REG_INIT
  `endif // RANDOMIZE
end // initial
`ifdef FIRRTL_AFTER_INITIAL
`FIRRTL_AFTER_INITIAL
`endif
`endif // SYNTHESIS
endmodule
module LifeGameFram(
  input        clock,
  input        reset,
  output [7:0] data,
  input        initialize,
  output [7:0] row,
  output       spi_sck,
  output       spi_si,
  input        spi_so,
  output       spi_cs_n,
  output       spi_wp_n,
  output       spi_hold_n
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
  reg [31:0] _RAND_16;
  reg [31:0] _RAND_17;
  reg [31:0] _RAND_18;
  reg [31:0] _RAND_19;
  reg [31:0] _RAND_20;
  reg [31:0] _RAND_21;
  reg [31:0] _RAND_22;
  reg [31:0] _RAND_23;
  reg [31:0] _RAND_24;
  reg [31:0] _RAND_25;
  reg [31:0] _RAND_26;
  reg [31:0] _RAND_27;
  reg [31:0] _RAND_28;
  reg [31:0] _RAND_29;
  reg [31:0] _RAND_30;
  reg [31:0] _RAND_31;
  reg [31:0] _RAND_32;
  reg [31:0] _RAND_33;
  reg [31:0] _RAND_34;
  reg [31:0] _RAND_35;
  reg [31:0] _RAND_36;
  reg [31:0] _RAND_37;
  reg [31:0] _RAND_38;
  reg [31:0] _RAND_39;
  reg [31:0] _RAND_40;
`endif // RANDOMIZE_REG_INIT
  wire  spim_clock; // @[lifegame_fram.scala 57:22]
  wire  spim_reset; // @[lifegame_fram.scala 57:22]
  wire  spim_io_spi_miso; // @[lifegame_fram.scala 57:22]
  wire  spim_io_spi_mosi; // @[lifegame_fram.scala 57:22]
  wire  spim_io_spi_cs; // @[lifegame_fram.scala 57:22]
  wire  spim_io_spi_sck; // @[lifegame_fram.scala 57:22]
  wire  spim_io_tx_ready; // @[lifegame_fram.scala 57:22]
  wire  spim_io_tx_valid; // @[lifegame_fram.scala 57:22]
  wire [7:0] spim_io_tx_bits; // @[lifegame_fram.scala 57:22]
  wire  spim_io_rx_ready; // @[lifegame_fram.scala 57:22]
  wire  spim_io_rx_valid; // @[lifegame_fram.scala 57:22]
  wire [7:0] spim_io_rx_bits; // @[lifegame_fram.scala 57:22]
  wire  spim_io_cs; // @[lifegame_fram.scala 57:22]
  reg [7:0] matrix_0; // @[lifegame_fram.scala 42:21]
  reg [7:0] matrix_1; // @[lifegame_fram.scala 42:21]
  reg [7:0] matrix_2; // @[lifegame_fram.scala 42:21]
  reg [7:0] matrix_3; // @[lifegame_fram.scala 42:21]
  reg [7:0] matrix_4; // @[lifegame_fram.scala 42:21]
  reg [7:0] matrix_5; // @[lifegame_fram.scala 42:21]
  reg [7:0] matrix_6; // @[lifegame_fram.scala 42:21]
  reg [7:0] matrix_7; // @[lifegame_fram.scala 42:21]
  reg [7:0] board_0; // @[lifegame_fram.scala 43:20]
  reg [7:0] board_1; // @[lifegame_fram.scala 43:20]
  reg [7:0] board_2; // @[lifegame_fram.scala 43:20]
  reg [7:0] board_3; // @[lifegame_fram.scala 43:20]
  reg [7:0] board_4; // @[lifegame_fram.scala 43:20]
  reg [7:0] board_5; // @[lifegame_fram.scala 43:20]
  reg [7:0] board_6; // @[lifegame_fram.scala 43:20]
  reg [7:0] board_7; // @[lifegame_fram.scala 43:20]
  reg [7:0] boardNext_0; // @[lifegame_fram.scala 44:24]
  reg [7:0] boardNext_1; // @[lifegame_fram.scala 44:24]
  reg [7:0] boardNext_2; // @[lifegame_fram.scala 44:24]
  reg [7:0] boardNext_3; // @[lifegame_fram.scala 44:24]
  reg [7:0] boardNext_4; // @[lifegame_fram.scala 44:24]
  reg [7:0] boardNext_5; // @[lifegame_fram.scala 44:24]
  reg [7:0] boardNext_6; // @[lifegame_fram.scala 44:24]
  reg [7:0] boardNext_7; // @[lifegame_fram.scala 44:24]
  reg [7:0] readChecksum; // @[lifegame_fram.scala 45:31]
  reg [7:0] writeChecksum; // @[lifegame_fram.scala 46:32]
  reg [7:0] spiTxBuffer_4; // @[lifegame_fram.scala 48:26]
  reg [7:0] spiRxBuffer_0; // @[lifegame_fram.scala 49:26]
  reg [7:0] spiRxBuffer_1; // @[lifegame_fram.scala 49:26]
  reg [7:0] spiRxBuffer_2; // @[lifegame_fram.scala 49:26]
  reg [7:0] spiRxBuffer_3; // @[lifegame_fram.scala 49:26]
  reg [3:0] spiTxCounter; // @[lifegame_fram.scala 50:31]
  reg [3:0] spiRxCounter; // @[lifegame_fram.scala 51:31]
  reg [3:0] boardAddress; // @[lifegame_fram.scala 52:31]
  reg [2:0] updateRow; // @[lifegame_fram.scala 53:28]
  reg [2:0] updateColumn; // @[lifegame_fram.scala 54:31]
  reg [24:0] updateCounter; // @[lifegame_fram.scala 55:32]
  reg  cs_n; // @[lifegame_fram.scala 64:23]
  reg [3:0] state; // @[lifegame_fram.scala 81:24]
  wire  _spim_io_tx_bits_T = state == 4'h5; // @[lifegame_fram.scala 85:15]
  wire  _spim_io_tx_bits_T_1 = state == 4'hb; // @[lifegame_fram.scala 86:14]
  wire  _spim_io_tx_bits_T_2 = boardAddress < 4'h8; // @[lifegame_fram.scala 86:51]
  wire  _spim_io_tx_bits_T_3 = state == 4'hb & boardAddress < 4'h8; // @[lifegame_fram.scala 86:35]
  wire  _spim_io_tx_bits_T_7 = _spim_io_tx_bits_T_1 & boardAddress == 4'h8; // @[lifegame_fram.scala 87:35]
  wire [7:0] _spim_io_tx_bits_T_8 = ~writeChecksum; // @[lifegame_fram.scala 87:66]
  wire [7:0] _spim_io_tx_bits_T_9 = _spim_io_tx_bits_T_7 ? _spim_io_tx_bits_T_8 : spiTxBuffer_4; // @[Mux.scala 98:16]
  wire [7:0] _GEN_1 = 3'h1 == boardAddress[2:0] ? boardNext_1 : boardNext_0; // @[Mux.scala 98:16 Mux.scala 98:16]
  wire [7:0] _GEN_2 = 3'h2 == boardAddress[2:0] ? boardNext_2 : _GEN_1; // @[Mux.scala 98:16 Mux.scala 98:16]
  wire [7:0] _GEN_3 = 3'h3 == boardAddress[2:0] ? boardNext_3 : _GEN_2; // @[Mux.scala 98:16 Mux.scala 98:16]
  wire [7:0] _GEN_4 = 3'h4 == boardAddress[2:0] ? boardNext_4 : _GEN_3; // @[Mux.scala 98:16 Mux.scala 98:16]
  wire [7:0] _GEN_5 = 3'h5 == boardAddress[2:0] ? boardNext_5 : _GEN_4; // @[Mux.scala 98:16 Mux.scala 98:16]
  wire [7:0] _GEN_6 = 3'h6 == boardAddress[2:0] ? boardNext_6 : _GEN_5; // @[Mux.scala 98:16 Mux.scala 98:16]
  wire [7:0] _GEN_7 = 3'h7 == boardAddress[2:0] ? boardNext_7 : _GEN_6; // @[Mux.scala 98:16 Mux.scala 98:16]
  wire [7:0] _spim_io_tx_bits_T_10 = _spim_io_tx_bits_T_3 ? _GEN_7 : _spim_io_tx_bits_T_9; // @[Mux.scala 98:16]
  wire  _spim_io_tx_valid_T = spiTxCounter > 4'h0; // @[lifegame_fram.scala 89:38]
  wire  _T_1 = _spim_io_tx_valid_T & spim_io_tx_ready; // @[lifegame_fram.scala 90:30]
  wire [3:0] _spiTxCounter_T_1 = spiTxCounter - 4'h1; // @[lifegame_fram.scala 91:36]
  wire [7:0] _writeChecksum_T_1 = writeChecksum ^ _GEN_7; // @[lifegame_fram.scala 96:42]
  wire [7:0] _GEN_16 = _spim_io_tx_bits_T_2 ? _writeChecksum_T_1 : writeChecksum; // @[lifegame_fram.scala 95:37 lifegame_fram.scala 96:25 lifegame_fram.scala 46:32]
  wire  _T_10 = ~reset; // @[lifegame_fram.scala 100:15]
  wire [3:0] _boardAddress_T_1 = boardAddress + 4'h1; // @[lifegame_fram.scala 101:38]
  wire [3:0] _GEN_27 = _spim_io_tx_bits_T_1 ? _boardAddress_T_1 : boardAddress; // @[lifegame_fram.scala 99:42 lifegame_fram.scala 101:22 lifegame_fram.scala 52:31]
  wire [7:0] _GEN_32 = _spim_io_tx_bits_T_1 ? spiTxBuffer_4 : 8'h0; // @[lifegame_fram.scala 99:42 lifegame_fram.scala 48:26 lifegame_fram.scala 109:21]
  wire [3:0] _GEN_33 = _spim_io_tx_valid_T & spim_io_tx_ready ? _spiTxCounter_T_1 : spiTxCounter; // @[lifegame_fram.scala 90:52 lifegame_fram.scala 91:20 lifegame_fram.scala 50:31]
  wire [3:0] _GEN_35 = _spim_io_tx_valid_T & spim_io_tx_ready ? _GEN_27 : boardAddress; // @[lifegame_fram.scala 90:52 lifegame_fram.scala 52:31]
  wire [7:0] _GEN_40 = _spim_io_tx_valid_T & spim_io_tx_ready ? _GEN_32 : spiTxBuffer_4; // @[lifegame_fram.scala 90:52 lifegame_fram.scala 48:26]
  wire  _spim_io_rx_ready_T = spiRxCounter > 4'h0; // @[lifegame_fram.scala 113:38]
  wire  _T_17 = _spim_io_rx_ready_T & spim_io_rx_valid; // @[lifegame_fram.scala 114:30]
  wire [3:0] _spiRxCounter_T_1 = spiRxCounter - 4'h1; // @[lifegame_fram.scala 116:36]
  wire [7:0] _readChecksum_T = readChecksum ^ spim_io_rx_bits; // @[lifegame_fram.scala 120:38]
  wire [7:0] _board_T_26 = spim_io_rx_bits; // @[lifegame_fram.scala 126:31 lifegame_fram.scala 126:31]
  wire [3:0] _GEN_59 = _spim_io_tx_bits_T ? _boardAddress_T_1 : _GEN_35; // @[lifegame_fram.scala 122:41 lifegame_fram.scala 124:22]
  wire [3:0] _GEN_73 = _spim_io_rx_ready_T & spim_io_rx_valid ? _spiRxCounter_T_1 : spiRxCounter; // @[lifegame_fram.scala 114:52 lifegame_fram.scala 116:20 lifegame_fram.scala 51:31]
  wire [3:0] _GEN_75 = _spim_io_rx_ready_T & spim_io_rx_valid ? _GEN_59 : _GEN_35; // @[lifegame_fram.scala 114:52]
  wire  _T_34 = 4'h0 == state; // @[Conditional.scala 37:30]
  wire  _T_39 = 4'h1 == state; // @[Conditional.scala 37:30]
  wire  _T_42 = spiTxCounter == 4'h0 & spiRxCounter == 4'h0; // @[lifegame_fram.scala 155:35]
  wire [31:0] deviceId = {spiRxBuffer_3,spiRxBuffer_2,spiRxBuffer_1,spiRxBuffer_0}; // @[Cat.scala 30:58]
  wire [1:0] _GEN_89 = deviceId == 32'h47f4803 ? 2'h3 : 2'h2; // @[lifegame_fram.scala 159:44 lifegame_fram.scala 160:19 lifegame_fram.scala 162:19]
  wire  _GEN_90 = spiTxCounter == 4'h0 & spiRxCounter == 4'h0 | cs_n; // @[lifegame_fram.scala 155:60 lifegame_fram.scala 156:16 lifegame_fram.scala 64:23]
  wire  _T_48 = 4'h2 == state; // @[Conditional.scala 37:30]
  wire  _T_51 = 4'h3 == state; // @[Conditional.scala 37:30]
  wire  _T_52 = updateCounter > 25'h0; // @[lifegame_fram.scala 178:29]
  wire [24:0] _updateCounter_T_1 = updateCounter - 25'h1; // @[lifegame_fram.scala 179:42]
  wire [24:0] _GEN_92 = updateCounter > 25'h0 ? _updateCounter_T_1 : 25'h19bfcbf; // @[lifegame_fram.scala 178:37 lifegame_fram.scala 179:25 lifegame_fram.scala 182:25]
  wire  _GEN_93 = updateCounter > 25'h0 & cs_n; // @[lifegame_fram.scala 178:37 lifegame_fram.scala 64:23 lifegame_fram.scala 184:16]
  wire [3:0] _GEN_94 = updateCounter > 25'h0 ? _GEN_33 : 4'h4; // @[lifegame_fram.scala 178:37 lifegame_fram.scala 185:24]
  wire [3:0] _GEN_95 = updateCounter > 25'h0 ? _GEN_73 : 4'h4; // @[lifegame_fram.scala 178:37 lifegame_fram.scala 186:24]
  wire [7:0] _GEN_96 = updateCounter > 25'h0 ? _GEN_40 : 8'h3; // @[lifegame_fram.scala 178:37 lifegame_fram.scala 187:44]
  wire [2:0] _GEN_100 = updateCounter > 25'h0 ? updateRow : 3'h0; // @[lifegame_fram.scala 178:37 lifegame_fram.scala 53:28 lifegame_fram.scala 192:21]
  wire [2:0] _GEN_101 = updateCounter > 25'h0 ? updateColumn : 3'h0; // @[lifegame_fram.scala 178:37 lifegame_fram.scala 54:31 lifegame_fram.scala 193:24]
  wire [3:0] _GEN_102 = updateCounter > 25'h0 ? state : 4'h4; // @[lifegame_fram.scala 178:37 lifegame_fram.scala 81:24 lifegame_fram.scala 195:17]
  wire  _T_57 = 4'h4 == state; // @[Conditional.scala 37:30]
  wire [3:0] _GEN_103 = _T_42 ? 4'h9 : _GEN_33; // @[lifegame_fram.scala 199:60 lifegame_fram.scala 200:24]
  wire [3:0] _GEN_104 = _T_42 ? 4'h9 : _GEN_73; // @[lifegame_fram.scala 199:60 lifegame_fram.scala 201:24]
  wire [3:0] _GEN_105 = _T_42 ? 4'h0 : _GEN_75; // @[lifegame_fram.scala 199:60 lifegame_fram.scala 202:24]
  wire [3:0] _GEN_106 = _T_42 ? 4'h5 : state; // @[lifegame_fram.scala 199:60 lifegame_fram.scala 203:17 lifegame_fram.scala 81:24]
  wire  _T_63 = 4'h5 == state; // @[Conditional.scala 37:30]
  wire  _T_69 = readChecksum == 8'hff; // @[lifegame_fram.scala 210:30]
  wire [7:0] _T_72 = board_0 | board_1; // @[lifegame_fram.scala 214:44]
  wire [7:0] _T_73 = _T_72 | board_2; // @[lifegame_fram.scala 214:44]
  wire [7:0] _T_74 = _T_73 | board_3; // @[lifegame_fram.scala 214:44]
  wire [7:0] _T_75 = _T_74 | board_4; // @[lifegame_fram.scala 214:44]
  wire [7:0] _T_76 = _T_75 | board_5; // @[lifegame_fram.scala 214:44]
  wire [7:0] _T_77 = _T_76 | board_6; // @[lifegame_fram.scala 214:44]
  wire [7:0] _T_78 = _T_77 | board_7; // @[lifegame_fram.scala 214:44]
  wire [2:0] _GEN_107 = _T_78 == 8'h0 ? 3'h6 : 3'h7; // @[lifegame_fram.scala 214:59 lifegame_fram.scala 216:21 lifegame_fram.scala 219:21]
  wire [2:0] _GEN_108 = readChecksum == 8'hff ? 3'h0 : updateColumn; // @[lifegame_fram.scala 210:43 lifegame_fram.scala 212:26 lifegame_fram.scala 54:31]
  wire [2:0] _GEN_109 = readChecksum == 8'hff ? 3'h0 : updateRow; // @[lifegame_fram.scala 210:43 lifegame_fram.scala 213:23 lifegame_fram.scala 53:28]
  wire [2:0] _GEN_110 = readChecksum == 8'hff ? _GEN_107 : 3'h6; // @[lifegame_fram.scala 210:43 lifegame_fram.scala 223:19]
  wire [2:0] _GEN_112 = _T_42 ? _GEN_108 : updateColumn; // @[lifegame_fram.scala 207:60 lifegame_fram.scala 54:31]
  wire [2:0] _GEN_113 = _T_42 ? _GEN_109 : updateRow; // @[lifegame_fram.scala 207:60 lifegame_fram.scala 53:28]
  wire [3:0] _GEN_114 = _T_42 ? {{1'd0}, _GEN_110} : state; // @[lifegame_fram.scala 207:60 lifegame_fram.scala 81:24]
  wire  _T_84 = 4'h6 == state; // @[Conditional.scala 37:30]
  wire  _T_87 = 4'h7 == state; // @[Conditional.scala 37:30]
  wire [2:0] _upperRow_T_2 = updateRow - 3'h1; // @[lifegame_fram.scala 246:61]
  wire [7:0] _GEN_116 = 3'h1 == _upperRow_T_2 ? board_1 : board_0; // @[lifegame_fram.scala 246:27 lifegame_fram.scala 246:27]
  wire [7:0] _GEN_117 = 3'h2 == _upperRow_T_2 ? board_2 : _GEN_116; // @[lifegame_fram.scala 246:27 lifegame_fram.scala 246:27]
  wire [7:0] _GEN_118 = 3'h3 == _upperRow_T_2 ? board_3 : _GEN_117; // @[lifegame_fram.scala 246:27 lifegame_fram.scala 246:27]
  wire [7:0] _GEN_119 = 3'h4 == _upperRow_T_2 ? board_4 : _GEN_118; // @[lifegame_fram.scala 246:27 lifegame_fram.scala 246:27]
  wire [7:0] _GEN_120 = 3'h5 == _upperRow_T_2 ? board_5 : _GEN_119; // @[lifegame_fram.scala 246:27 lifegame_fram.scala 246:27]
  wire [7:0] _GEN_121 = 3'h6 == _upperRow_T_2 ? board_6 : _GEN_120; // @[lifegame_fram.scala 246:27 lifegame_fram.scala 246:27]
  wire [7:0] _GEN_122 = 3'h7 == _upperRow_T_2 ? board_7 : _GEN_121; // @[lifegame_fram.scala 246:27 lifegame_fram.scala 246:27]
  wire [7:0] upperRow = updateRow > 3'h0 ? _GEN_122 : 8'h0; // @[lifegame_fram.scala 246:27]
  wire [2:0] _bottomRow_T_2 = updateRow + 3'h1; // @[lifegame_fram.scala 248:71]
  wire [7:0] _GEN_124 = 3'h1 == _bottomRow_T_2 ? board_1 : board_0; // @[lifegame_fram.scala 248:28 lifegame_fram.scala 248:28]
  wire [7:0] _GEN_125 = 3'h2 == _bottomRow_T_2 ? board_2 : _GEN_124; // @[lifegame_fram.scala 248:28 lifegame_fram.scala 248:28]
  wire [7:0] _GEN_126 = 3'h3 == _bottomRow_T_2 ? board_3 : _GEN_125; // @[lifegame_fram.scala 248:28 lifegame_fram.scala 248:28]
  wire [7:0] _GEN_127 = 3'h4 == _bottomRow_T_2 ? board_4 : _GEN_126; // @[lifegame_fram.scala 248:28 lifegame_fram.scala 248:28]
  wire [7:0] _GEN_128 = 3'h5 == _bottomRow_T_2 ? board_5 : _GEN_127; // @[lifegame_fram.scala 248:28 lifegame_fram.scala 248:28]
  wire [7:0] _GEN_129 = 3'h6 == _bottomRow_T_2 ? board_6 : _GEN_128; // @[lifegame_fram.scala 248:28 lifegame_fram.scala 248:28]
  wire [7:0] _GEN_130 = 3'h7 == _bottomRow_T_2 ? board_7 : _GEN_129; // @[lifegame_fram.scala 248:28 lifegame_fram.scala 248:28]
  wire [7:0] bottomRow = updateRow < 3'h7 ? _GEN_130 : 8'h0; // @[lifegame_fram.scala 248:28]
  wire  _ul_T = updateColumn > 3'h0; // @[lifegame_fram.scala 249:35]
  wire [2:0] _ul_T_2 = updateColumn - 3'h1; // @[lifegame_fram.scala 249:64]
  wire [7:0] _ul_T_3 = upperRow >> _ul_T_2; // @[lifegame_fram.scala 249:50]
  wire  ul = updateColumn > 3'h0 & _ul_T_3[0]; // @[lifegame_fram.scala 249:21]
  wire [7:0] _GEN_132 = 3'h1 == updateRow ? board_1 : board_0; // @[lifegame_fram.scala 250:51 lifegame_fram.scala 250:51]
  wire [7:0] _GEN_133 = 3'h2 == updateRow ? board_2 : _GEN_132; // @[lifegame_fram.scala 250:51 lifegame_fram.scala 250:51]
  wire [7:0] _GEN_134 = 3'h3 == updateRow ? board_3 : _GEN_133; // @[lifegame_fram.scala 250:51 lifegame_fram.scala 250:51]
  wire [7:0] _GEN_135 = 3'h4 == updateRow ? board_4 : _GEN_134; // @[lifegame_fram.scala 250:51 lifegame_fram.scala 250:51]
  wire [7:0] _GEN_136 = 3'h5 == updateRow ? board_5 : _GEN_135; // @[lifegame_fram.scala 250:51 lifegame_fram.scala 250:51]
  wire [7:0] _GEN_137 = 3'h6 == updateRow ? board_6 : _GEN_136; // @[lifegame_fram.scala 250:51 lifegame_fram.scala 250:51]
  wire [7:0] _GEN_138 = 3'h7 == updateRow ? board_7 : _GEN_137; // @[lifegame_fram.scala 250:51 lifegame_fram.scala 250:51]
  wire [7:0] _cl_T_3 = _GEN_138 >> _ul_T_2; // @[lifegame_fram.scala 250:51]
  wire  cl = _ul_T & _cl_T_3[0]; // @[lifegame_fram.scala 250:21]
  wire [7:0] _bl_T_3 = bottomRow >> _ul_T_2; // @[lifegame_fram.scala 251:51]
  wire  bl = _ul_T & _bl_T_3[0]; // @[lifegame_fram.scala 251:21]
  wire [7:0] _uc_T = upperRow >> updateColumn; // @[lifegame_fram.scala 252:26]
  wire  uc = _uc_T[0]; // @[lifegame_fram.scala 252:26]
  wire [7:0] _cc_T = _GEN_138 >> updateColumn; // @[lifegame_fram.scala 253:27]
  wire  cc = _cc_T[0]; // @[lifegame_fram.scala 253:27]
  wire [7:0] _bc_T = bottomRow >> updateColumn; // @[lifegame_fram.scala 254:27]
  wire  bc = _bc_T[0]; // @[lifegame_fram.scala 254:27]
  wire  _ur_T = updateColumn < 3'h7; // @[lifegame_fram.scala 255:35]
  wire [2:0] _ur_T_2 = updateColumn + 3'h1; // @[lifegame_fram.scala 255:76]
  wire [7:0] _ur_T_3 = upperRow >> _ur_T_2; // @[lifegame_fram.scala 255:62]
  wire  ur = updateColumn < 3'h7 & _ur_T_3[0]; // @[lifegame_fram.scala 255:21]
  wire [7:0] _cr_T_3 = _GEN_138 >> _ur_T_2; // @[lifegame_fram.scala 256:63]
  wire  cr = _ur_T & _cr_T_3[0]; // @[lifegame_fram.scala 256:21]
  wire [7:0] _br_T_3 = bottomRow >> _ur_T_2; // @[lifegame_fram.scala 257:63]
  wire  br = _ur_T & _br_T_3[0]; // @[lifegame_fram.scala 257:21]
  wire [3:0] _count_T = {{3'd0}, ul}; // @[lifegame_fram.scala 258:68]
  wire [3:0] _count_T_2 = {{3'd0}, cl}; // @[lifegame_fram.scala 258:68]
  wire [3:0] _count_T_4 = {{3'd0}, bl}; // @[lifegame_fram.scala 258:68]
  wire [3:0] _count_T_6 = {{3'd0}, uc}; // @[lifegame_fram.scala 258:68]
  wire [3:0] _count_T_8 = {{3'd0}, bc}; // @[lifegame_fram.scala 258:68]
  wire [3:0] _count_T_10 = {{3'd0}, ur}; // @[lifegame_fram.scala 258:68]
  wire [3:0] _count_T_12 = {{3'd0}, cr}; // @[lifegame_fram.scala 258:68]
  wire [3:0] _count_T_14 = {{3'd0}, br}; // @[lifegame_fram.scala 258:68]
  wire [2:0] _count_T_17 = _count_T[2:0] + _count_T_2[2:0]; // @[lifegame_fram.scala 258:99]
  wire [2:0] _count_T_19 = _count_T_17 + _count_T_4[2:0]; // @[lifegame_fram.scala 258:99]
  wire [2:0] _count_T_21 = _count_T_19 + _count_T_6[2:0]; // @[lifegame_fram.scala 258:99]
  wire [2:0] _count_T_23 = _count_T_21 + _count_T_8[2:0]; // @[lifegame_fram.scala 258:99]
  wire [2:0] _count_T_25 = _count_T_23 + _count_T_10[2:0]; // @[lifegame_fram.scala 258:99]
  wire [2:0] _count_T_27 = _count_T_25 + _count_T_12[2:0]; // @[lifegame_fram.scala 258:99]
  wire [2:0] count = _count_T_27 + _count_T_14[2:0]; // @[lifegame_fram.scala 258:99]
  wire  _GEN_139 = cc & (count <= 3'h1 | 3'h4 <= count) ? 1'h0 : cc; // @[lifegame_fram.scala 263:60 lifegame_fram.scala 264:16]
  wire  cell_ = ~cc & count == 3'h3 | _GEN_139; // @[lifegame_fram.scala 261:36 lifegame_fram.scala 262:16]
  wire [7:0] _GEN_142 = 3'h1 == updateRow ? boardNext_1 : boardNext_0; // @[lifegame_fram.scala 266:121 lifegame_fram.scala 266:121]
  wire [7:0] _GEN_143 = 3'h2 == updateRow ? boardNext_2 : _GEN_142; // @[lifegame_fram.scala 266:121 lifegame_fram.scala 266:121]
  wire [7:0] _GEN_144 = 3'h3 == updateRow ? boardNext_3 : _GEN_143; // @[lifegame_fram.scala 266:121 lifegame_fram.scala 266:121]
  wire [7:0] _GEN_145 = 3'h4 == updateRow ? boardNext_4 : _GEN_144; // @[lifegame_fram.scala 266:121 lifegame_fram.scala 266:121]
  wire [7:0] _GEN_146 = 3'h5 == updateRow ? boardNext_5 : _GEN_145; // @[lifegame_fram.scala 266:121 lifegame_fram.scala 266:121]
  wire [7:0] _GEN_147 = 3'h6 == updateRow ? boardNext_6 : _GEN_146; // @[lifegame_fram.scala 266:121 lifegame_fram.scala 266:121]
  wire [7:0] _GEN_148 = 3'h7 == updateRow ? boardNext_7 : _GEN_147; // @[lifegame_fram.scala 266:121 lifegame_fram.scala 266:121]
  wire  _boardNext_T_2 = updateColumn == 3'h0 ? cell_ : _GEN_148[0]; // @[lifegame_fram.scala 266:72]
  wire  _boardNext_T_5 = updateColumn == 3'h1 ? cell_ : _GEN_148[1]; // @[lifegame_fram.scala 266:72]
  wire  _boardNext_T_8 = updateColumn == 3'h2 ? cell_ : _GEN_148[2]; // @[lifegame_fram.scala 266:72]
  wire  _boardNext_T_11 = updateColumn == 3'h3 ? cell_ : _GEN_148[3]; // @[lifegame_fram.scala 266:72]
  wire  _boardNext_T_14 = updateColumn == 3'h4 ? cell_ : _GEN_148[4]; // @[lifegame_fram.scala 266:72]
  wire  _boardNext_T_17 = updateColumn == 3'h5 ? cell_ : _GEN_148[5]; // @[lifegame_fram.scala 266:72]
  wire  _boardNext_T_20 = updateColumn == 3'h6 ? cell_ : _GEN_148[6]; // @[lifegame_fram.scala 266:72]
  wire  _boardNext_T_21 = updateColumn == 3'h7; // @[lifegame_fram.scala 266:86]
  wire  _boardNext_T_23 = updateColumn == 3'h7 ? cell_ : _GEN_148[7]; // @[lifegame_fram.scala 266:72]
  wire [7:0] _boardNext_T_24 = {_boardNext_T_23,_boardNext_T_20,_boardNext_T_17,_boardNext_T_14,_boardNext_T_11,
    _boardNext_T_8,_boardNext_T_5,_boardNext_T_2}; // @[lifegame_fram.scala 266:134]
  wire [7:0] _GEN_149 = 3'h0 == updateRow ? _boardNext_T_24 : boardNext_0; // @[lifegame_fram.scala 266:30 lifegame_fram.scala 266:30 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_150 = 3'h1 == updateRow ? _boardNext_T_24 : boardNext_1; // @[lifegame_fram.scala 266:30 lifegame_fram.scala 266:30 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_151 = 3'h2 == updateRow ? _boardNext_T_24 : boardNext_2; // @[lifegame_fram.scala 266:30 lifegame_fram.scala 266:30 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_152 = 3'h3 == updateRow ? _boardNext_T_24 : boardNext_3; // @[lifegame_fram.scala 266:30 lifegame_fram.scala 266:30 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_153 = 3'h4 == updateRow ? _boardNext_T_24 : boardNext_4; // @[lifegame_fram.scala 266:30 lifegame_fram.scala 266:30 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_154 = 3'h5 == updateRow ? _boardNext_T_24 : boardNext_5; // @[lifegame_fram.scala 266:30 lifegame_fram.scala 266:30 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_155 = 3'h6 == updateRow ? _boardNext_T_24 : boardNext_6; // @[lifegame_fram.scala 266:30 lifegame_fram.scala 266:30 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_156 = 3'h7 == updateRow ? _boardNext_T_24 : boardNext_7; // @[lifegame_fram.scala 266:30 lifegame_fram.scala 266:30 lifegame_fram.scala 44:24]
  wire [3:0] _GEN_157 = updateRow == 3'h7 ? 4'h8 : state; // @[lifegame_fram.scala 271:44 lifegame_fram.scala 272:19 lifegame_fram.scala 81:24]
  wire [2:0] _GEN_158 = _boardNext_T_21 ? _bottomRow_T_2 : updateRow; // @[lifegame_fram.scala 268:48 lifegame_fram.scala 269:21 lifegame_fram.scala 53:28]
  wire [2:0] _GEN_159 = _boardNext_T_21 ? 3'h0 : _ur_T_2; // @[lifegame_fram.scala 268:48 lifegame_fram.scala 270:24 lifegame_fram.scala 275:24]
  wire [3:0] _GEN_160 = _boardNext_T_21 ? _GEN_157 : state; // @[lifegame_fram.scala 268:48 lifegame_fram.scala 81:24]
  wire  _T_99 = 4'h8 == state; // @[Conditional.scala 37:30]
  wire [7:0] _stall_T = board_0 ^ boardNext_0; // @[lifegame_fram.scala 279:56]
  wire [7:0] _stall_T_1 = board_1 ^ boardNext_1; // @[lifegame_fram.scala 279:56]
  wire [7:0] _stall_T_2 = board_2 ^ boardNext_2; // @[lifegame_fram.scala 279:56]
  wire [7:0] _stall_T_3 = board_3 ^ boardNext_3; // @[lifegame_fram.scala 279:56]
  wire [7:0] _stall_T_4 = board_4 ^ boardNext_4; // @[lifegame_fram.scala 279:56]
  wire [7:0] _stall_T_5 = board_5 ^ boardNext_5; // @[lifegame_fram.scala 279:56]
  wire [7:0] _stall_T_6 = board_6 ^ boardNext_6; // @[lifegame_fram.scala 279:56]
  wire [7:0] _stall_T_7 = board_7 ^ boardNext_7; // @[lifegame_fram.scala 279:56]
  wire [7:0] _stall_T_8 = _stall_T | _stall_T_1; // @[lifegame_fram.scala 279:83]
  wire [7:0] _stall_T_9 = _stall_T_8 | _stall_T_2; // @[lifegame_fram.scala 279:83]
  wire [7:0] _stall_T_10 = _stall_T_9 | _stall_T_3; // @[lifegame_fram.scala 279:83]
  wire [7:0] _stall_T_11 = _stall_T_10 | _stall_T_4; // @[lifegame_fram.scala 279:83]
  wire [7:0] _stall_T_12 = _stall_T_11 | _stall_T_5; // @[lifegame_fram.scala 279:83]
  wire [7:0] _stall_T_13 = _stall_T_12 | _stall_T_6; // @[lifegame_fram.scala 279:83]
  wire [7:0] _stall_T_14 = _stall_T_13 | _stall_T_7; // @[lifegame_fram.scala 279:83]
  wire  stall = _stall_T_14 == 8'h0; // @[lifegame_fram.scala 279:88]
  wire [3:0] _GEN_161 = stall | initialize ? 4'h6 : 4'h9; // @[lifegame_fram.scala 281:37 lifegame_fram.scala 283:17 lifegame_fram.scala 289:17]
  wire  _GEN_162 = (stall | initialize) & cs_n; // @[lifegame_fram.scala 281:37 lifegame_fram.scala 64:23 lifegame_fram.scala 285:16]
  wire [3:0] _GEN_163 = stall | initialize ? _GEN_33 : 4'h1; // @[lifegame_fram.scala 281:37 lifegame_fram.scala 286:24]
  wire [7:0] _GEN_164 = stall | initialize ? _GEN_40 : 8'h6; // @[lifegame_fram.scala 281:37 lifegame_fram.scala 287:44]
  wire [3:0] _GEN_165 = stall | initialize ? _GEN_73 : 4'h1; // @[lifegame_fram.scala 281:37 lifegame_fram.scala 288:24]
  wire  _T_105 = 4'h9 == state; // @[Conditional.scala 37:30]
  wire [3:0] _GEN_167 = _T_42 ? 4'h4 : _GEN_33; // @[lifegame_fram.scala 294:60 lifegame_fram.scala 296:24]
  wire [7:0] _GEN_168 = _T_42 ? 8'h2 : _GEN_40; // @[lifegame_fram.scala 294:60 lifegame_fram.scala 297:44]
  wire [3:0] _GEN_172 = _T_42 ? 4'h4 : _GEN_73; // @[lifegame_fram.scala 294:60 lifegame_fram.scala 301:24]
  wire [3:0] _GEN_173 = _T_42 ? 4'ha : state; // @[lifegame_fram.scala 294:60 lifegame_fram.scala 302:17 lifegame_fram.scala 81:24]
  wire  _T_111 = 4'ha == state; // @[Conditional.scala 37:30]
  wire [3:0] _GEN_177 = _T_42 ? 4'hb : state; // @[lifegame_fram.scala 307:60 lifegame_fram.scala 311:17 lifegame_fram.scala 81:24]
  wire  _T_117 = 4'hb == state; // @[Conditional.scala 37:30]
  wire [3:0] _GEN_179 = _T_42 ? 4'h3 : state; // @[lifegame_fram.scala 315:60 lifegame_fram.scala 317:17 lifegame_fram.scala 81:24]
  wire  _GEN_180 = _T_117 ? _GEN_90 : cs_n; // @[Conditional.scala 39:67 lifegame_fram.scala 64:23]
  wire [3:0] _GEN_181 = _T_117 ? _GEN_179 : state; // @[Conditional.scala 39:67 lifegame_fram.scala 81:24]
  wire  _GEN_182 = _T_111 ? 1'h0 : _GEN_180; // @[Conditional.scala 39:67 lifegame_fram.scala 306:14]
  wire [3:0] _GEN_183 = _T_111 ? _GEN_103 : _GEN_33; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_184 = _T_111 ? _GEN_104 : _GEN_73; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_185 = _T_111 ? _GEN_105 : _GEN_75; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_186 = _T_111 ? _GEN_177 : _GEN_181; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_187 = _T_105 ? boardNext_0 : matrix_0; // @[Conditional.scala 39:67 lifegame_fram.scala 293:16 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_188 = _T_105 ? boardNext_1 : matrix_1; // @[Conditional.scala 39:67 lifegame_fram.scala 293:16 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_189 = _T_105 ? boardNext_2 : matrix_2; // @[Conditional.scala 39:67 lifegame_fram.scala 293:16 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_190 = _T_105 ? boardNext_3 : matrix_3; // @[Conditional.scala 39:67 lifegame_fram.scala 293:16 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_191 = _T_105 ? boardNext_4 : matrix_4; // @[Conditional.scala 39:67 lifegame_fram.scala 293:16 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_192 = _T_105 ? boardNext_5 : matrix_5; // @[Conditional.scala 39:67 lifegame_fram.scala 293:16 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_193 = _T_105 ? boardNext_6 : matrix_6; // @[Conditional.scala 39:67 lifegame_fram.scala 293:16 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_194 = _T_105 ? boardNext_7 : matrix_7; // @[Conditional.scala 39:67 lifegame_fram.scala 293:16 lifegame_fram.scala 42:21]
  wire  _GEN_195 = _T_105 ? _GEN_90 : _GEN_182; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_196 = _T_105 ? _GEN_167 : _GEN_183; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_197 = _T_105 ? _GEN_168 : _GEN_40; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_201 = _T_105 ? _GEN_172 : _GEN_184; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_202 = _T_105 ? _GEN_173 : _GEN_186; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_203 = _T_105 ? _GEN_75 : _GEN_185; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_204 = _T_99 ? _GEN_161 : _GEN_202; // @[Conditional.scala 39:67]
  wire  _GEN_205 = _T_99 ? _GEN_162 : _GEN_195; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_206 = _T_99 ? _GEN_163 : _GEN_196; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_207 = _T_99 ? _GEN_164 : _GEN_197; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_208 = _T_99 ? _GEN_165 : _GEN_201; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_209 = _T_99 ? matrix_0 : _GEN_187; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_210 = _T_99 ? matrix_1 : _GEN_188; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_211 = _T_99 ? matrix_2 : _GEN_189; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_212 = _T_99 ? matrix_3 : _GEN_190; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_213 = _T_99 ? matrix_4 : _GEN_191; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_214 = _T_99 ? matrix_5 : _GEN_192; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_215 = _T_99 ? matrix_6 : _GEN_193; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_216 = _T_99 ? matrix_7 : _GEN_194; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [3:0] _GEN_220 = _T_99 ? _GEN_75 : _GEN_203; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_221 = _T_87 ? _GEN_149 : boardNext_0; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_222 = _T_87 ? _GEN_150 : boardNext_1; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_223 = _T_87 ? _GEN_151 : boardNext_2; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_224 = _T_87 ? _GEN_152 : boardNext_3; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_225 = _T_87 ? _GEN_153 : boardNext_4; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_226 = _T_87 ? _GEN_154 : boardNext_5; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_227 = _T_87 ? _GEN_155 : boardNext_6; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_228 = _T_87 ? _GEN_156 : boardNext_7; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [2:0] _GEN_229 = _T_87 ? _GEN_158 : updateRow; // @[Conditional.scala 39:67 lifegame_fram.scala 53:28]
  wire [2:0] _GEN_230 = _T_87 ? _GEN_159 : updateColumn; // @[Conditional.scala 39:67 lifegame_fram.scala 54:31]
  wire [3:0] _GEN_231 = _T_87 ? _GEN_160 : _GEN_204; // @[Conditional.scala 39:67]
  wire  _GEN_232 = _T_87 ? cs_n : _GEN_205; // @[Conditional.scala 39:67 lifegame_fram.scala 64:23]
  wire [3:0] _GEN_233 = _T_87 ? _GEN_33 : _GEN_206; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_234 = _T_87 ? _GEN_40 : _GEN_207; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_235 = _T_87 ? _GEN_73 : _GEN_208; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_236 = _T_87 ? matrix_0 : _GEN_209; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_237 = _T_87 ? matrix_1 : _GEN_210; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_238 = _T_87 ? matrix_2 : _GEN_211; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_239 = _T_87 ? matrix_3 : _GEN_212; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_240 = _T_87 ? matrix_4 : _GEN_213; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_241 = _T_87 ? matrix_5 : _GEN_214; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_242 = _T_87 ? matrix_6 : _GEN_215; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_243 = _T_87 ? matrix_7 : _GEN_216; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [3:0] _GEN_247 = _T_87 ? _GEN_75 : _GEN_220; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_248 = _T_84 ? 8'h9 : _GEN_221; // @[Conditional.scala 39:67 lifegame_fram.scala 228:22]
  wire [7:0] _GEN_249 = _T_84 ? 8'h10 : _GEN_222; // @[Conditional.scala 39:67 lifegame_fram.scala 229:22]
  wire [7:0] _GEN_250 = _T_84 ? 8'h11 : _GEN_223; // @[Conditional.scala 39:67 lifegame_fram.scala 230:22]
  wire [7:0] _GEN_251 = _T_84 ? 8'h1e : _GEN_224; // @[Conditional.scala 39:67 lifegame_fram.scala 231:22]
  wire [7:0] _GEN_252 = _T_84 ? 8'h0 : _GEN_225; // @[Conditional.scala 39:67 lifegame_fram.scala 232:22]
  wire [7:0] _GEN_253 = _T_84 ? 8'h40 : _GEN_226; // @[Conditional.scala 39:67 lifegame_fram.scala 233:22]
  wire [7:0] _GEN_254 = _T_84 ? 8'h40 : _GEN_227; // @[Conditional.scala 39:67 lifegame_fram.scala 234:22]
  wire [7:0] _GEN_255 = _T_84 ? 8'h40 : _GEN_228; // @[Conditional.scala 39:67 lifegame_fram.scala 235:22]
  wire  _GEN_256 = _T_84 ? 1'h0 : _GEN_232; // @[Conditional.scala 39:67 lifegame_fram.scala 238:14]
  wire [3:0] _GEN_257 = _T_84 ? 4'h1 : _GEN_233; // @[Conditional.scala 39:67 lifegame_fram.scala 239:22]
  wire [3:0] _GEN_258 = _T_84 ? 4'h1 : _GEN_235; // @[Conditional.scala 39:67 lifegame_fram.scala 240:22]
  wire [7:0] _GEN_259 = _T_84 ? 8'h6 : _GEN_234; // @[Conditional.scala 39:67 lifegame_fram.scala 241:42]
  wire [3:0] _GEN_260 = _T_84 ? 4'h9 : _GEN_231; // @[Conditional.scala 39:67 lifegame_fram.scala 242:15]
  wire [2:0] _GEN_261 = _T_84 ? updateRow : _GEN_229; // @[Conditional.scala 39:67 lifegame_fram.scala 53:28]
  wire [2:0] _GEN_262 = _T_84 ? updateColumn : _GEN_230; // @[Conditional.scala 39:67 lifegame_fram.scala 54:31]
  wire [7:0] _GEN_263 = _T_84 ? matrix_0 : _GEN_236; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_264 = _T_84 ? matrix_1 : _GEN_237; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_265 = _T_84 ? matrix_2 : _GEN_238; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_266 = _T_84 ? matrix_3 : _GEN_239; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_267 = _T_84 ? matrix_4 : _GEN_240; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_268 = _T_84 ? matrix_5 : _GEN_241; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_269 = _T_84 ? matrix_6 : _GEN_242; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_270 = _T_84 ? matrix_7 : _GEN_243; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [3:0] _GEN_274 = _T_84 ? _GEN_75 : _GEN_247; // @[Conditional.scala 39:67]
  wire  _GEN_275 = _T_63 ? _GEN_90 : _GEN_256; // @[Conditional.scala 39:67]
  wire [2:0] _GEN_276 = _T_63 ? _GEN_112 : _GEN_262; // @[Conditional.scala 39:67]
  wire [2:0] _GEN_277 = _T_63 ? _GEN_113 : _GEN_261; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_278 = _T_63 ? _GEN_114 : _GEN_260; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_279 = _T_63 ? boardNext_0 : _GEN_248; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_280 = _T_63 ? boardNext_1 : _GEN_249; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_281 = _T_63 ? boardNext_2 : _GEN_250; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_282 = _T_63 ? boardNext_3 : _GEN_251; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_283 = _T_63 ? boardNext_4 : _GEN_252; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_284 = _T_63 ? boardNext_5 : _GEN_253; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_285 = _T_63 ? boardNext_6 : _GEN_254; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_286 = _T_63 ? boardNext_7 : _GEN_255; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [3:0] _GEN_287 = _T_63 ? _GEN_33 : _GEN_257; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_288 = _T_63 ? _GEN_73 : _GEN_258; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_289 = _T_63 ? _GEN_40 : _GEN_259; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_290 = _T_63 ? matrix_0 : _GEN_263; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_291 = _T_63 ? matrix_1 : _GEN_264; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_292 = _T_63 ? matrix_2 : _GEN_265; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_293 = _T_63 ? matrix_3 : _GEN_266; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_294 = _T_63 ? matrix_4 : _GEN_267; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_295 = _T_63 ? matrix_5 : _GEN_268; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_296 = _T_63 ? matrix_6 : _GEN_269; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_297 = _T_63 ? matrix_7 : _GEN_270; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [3:0] _GEN_301 = _T_63 ? _GEN_75 : _GEN_274; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_302 = _T_57 ? _GEN_103 : _GEN_287; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_303 = _T_57 ? _GEN_104 : _GEN_288; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_304 = _T_57 ? _GEN_105 : _GEN_301; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_305 = _T_57 ? _GEN_106 : _GEN_278; // @[Conditional.scala 39:67]
  wire  _GEN_306 = _T_57 ? cs_n : _GEN_275; // @[Conditional.scala 39:67 lifegame_fram.scala 64:23]
  wire [2:0] _GEN_307 = _T_57 ? updateColumn : _GEN_276; // @[Conditional.scala 39:67 lifegame_fram.scala 54:31]
  wire [2:0] _GEN_308 = _T_57 ? updateRow : _GEN_277; // @[Conditional.scala 39:67 lifegame_fram.scala 53:28]
  wire [7:0] _GEN_309 = _T_57 ? boardNext_0 : _GEN_279; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_310 = _T_57 ? boardNext_1 : _GEN_280; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_311 = _T_57 ? boardNext_2 : _GEN_281; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_312 = _T_57 ? boardNext_3 : _GEN_282; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_313 = _T_57 ? boardNext_4 : _GEN_283; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_314 = _T_57 ? boardNext_5 : _GEN_284; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_315 = _T_57 ? boardNext_6 : _GEN_285; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_316 = _T_57 ? boardNext_7 : _GEN_286; // @[Conditional.scala 39:67 lifegame_fram.scala 44:24]
  wire [7:0] _GEN_317 = _T_57 ? _GEN_40 : _GEN_289; // @[Conditional.scala 39:67]
  wire [7:0] _GEN_318 = _T_57 ? matrix_0 : _GEN_290; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_319 = _T_57 ? matrix_1 : _GEN_291; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_320 = _T_57 ? matrix_2 : _GEN_292; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_321 = _T_57 ? matrix_3 : _GEN_293; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_322 = _T_57 ? matrix_4 : _GEN_294; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_323 = _T_57 ? matrix_5 : _GEN_295; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_324 = _T_57 ? matrix_6 : _GEN_296; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [7:0] _GEN_325 = _T_57 ? matrix_7 : _GEN_297; // @[Conditional.scala 39:67 lifegame_fram.scala 42:21]
  wire [24:0] _GEN_329 = _T_51 ? _GEN_92 : updateCounter; // @[Conditional.scala 39:67 lifegame_fram.scala 55:32]
  wire  _GEN_330 = _T_51 ? _GEN_93 : _GEN_306; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_331 = _T_51 ? _GEN_94 : _GEN_302; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_332 = _T_51 ? _GEN_95 : _GEN_303; // @[Conditional.scala 39:67]
  wire [2:0] _GEN_337 = _T_51 ? _GEN_100 : _GEN_308; // @[Conditional.scala 39:67]
  wire [2:0] _GEN_338 = _T_51 ? _GEN_101 : _GEN_307; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_339 = _T_51 ? _GEN_102 : _GEN_305; // @[Conditional.scala 39:67]
  wire [3:0] _GEN_340 = _T_51 ? _GEN_75 : _GEN_304; // @[Conditional.scala 39:67]
  wire  _GEN_367 = _T_48 ? cs_n : _GEN_330; // @[Conditional.scala 39:67 lifegame_fram.scala 64:23]
  wire  _GEN_385 = _T_39 ? _GEN_90 : _GEN_367; // @[Conditional.scala 39:67]
  wire  _GEN_413 = _T_34 ? 1'h0 : _GEN_385; // @[Conditional.scala 40:58 lifegame_fram.scala 144:14]
  reg [14:0] refreshCounter; // @[lifegame_fram.scala 322:33]
  reg [7:0] rowReg; // @[lifegame_fram.scala 323:25]
  wire  _GEN_443 = refreshCounter < 15'h6977 ? 1'h0 : 1'h1; // @[lifegame_fram.scala 334:61 lifegame_fram.scala 335:17]
  wire  _GEN_445 = refreshCounter == 15'h6869 ? 1'h0 : _GEN_443; // @[lifegame_fram.scala 331:86 lifegame_fram.scala 332:17]
  wire  rowEnable = refreshCounter < 15'h675b | _GEN_445; // @[lifegame_fram.scala 330:79]
  wire  _data_T_1 = rowReg == 8'h1; // @[lifegame_fram.scala 327:63]
  wire  _data_T_3 = rowReg == 8'h2; // @[lifegame_fram.scala 327:63]
  wire  _data_T_5 = rowReg == 8'h4; // @[lifegame_fram.scala 327:63]
  wire  _data_T_7 = rowReg == 8'h8; // @[lifegame_fram.scala 327:63]
  wire  _data_T_9 = rowReg == 8'h10; // @[lifegame_fram.scala 327:63]
  wire  _data_T_11 = rowReg == 8'h20; // @[lifegame_fram.scala 327:63]
  wire  _data_T_13 = rowReg == 8'h40; // @[lifegame_fram.scala 327:63]
  wire  _data_T_15 = rowReg == 8'h80; // @[lifegame_fram.scala 327:63]
  wire [7:0] _data_T_16 = _data_T_15 ? matrix_7 : 8'h0; // @[Mux.scala 98:16]
  wire [7:0] _data_T_17 = _data_T_13 ? matrix_6 : _data_T_16; // @[Mux.scala 98:16]
  wire [7:0] _data_T_18 = _data_T_11 ? matrix_5 : _data_T_17; // @[Mux.scala 98:16]
  wire [7:0] _data_T_19 = _data_T_9 ? matrix_4 : _data_T_18; // @[Mux.scala 98:16]
  wire [7:0] _data_T_20 = _data_T_7 ? matrix_3 : _data_T_19; // @[Mux.scala 98:16]
  wire [7:0] _data_T_21 = _data_T_5 ? matrix_2 : _data_T_20; // @[Mux.scala 98:16]
  wire [7:0] _data_T_22 = _data_T_3 ? matrix_1 : _data_T_21; // @[Mux.scala 98:16]
  wire [14:0] _refreshCounter_T_1 = refreshCounter + 15'h1; // @[lifegame_fram.scala 329:38]
  wire [8:0] _rowReg_T = {rowReg, 1'h0}; // @[lifegame_fram.scala 333:25]
  wire [8:0] _GEN_451 = {{8'd0}, rowReg[7]}; // @[lifegame_fram.scala 333:31]
  wire [8:0] _rowReg_T_2 = _rowReg_T | _GEN_451; // @[lifegame_fram.scala 333:31]
  wire [14:0] _GEN_442 = refreshCounter == 15'h6977 ? 15'h0 : _refreshCounter_T_1; // @[lifegame_fram.scala 336:63 lifegame_fram.scala 337:22 lifegame_fram.scala 329:20]
  wire [8:0] _GEN_446 = refreshCounter == 15'h6869 ? _rowReg_T_2 : {{1'd0}, rowReg}; // @[lifegame_fram.scala 331:86 lifegame_fram.scala 333:14 lifegame_fram.scala 323:25]
  wire [8:0] _GEN_449 = refreshCounter < 15'h675b ? {{1'd0}, rowReg} : _GEN_446; // @[lifegame_fram.scala 330:79 lifegame_fram.scala 323:25]
  wire  _GEN_458 = ~_T_34; // @[lifegame_fram.scala 158:17]
  wire  _GEN_465 = _GEN_458 & ~_T_39 & ~_T_48; // @[lifegame_fram.scala 181:17]
  wire  _GEN_477 = _GEN_465 & ~_T_51 & ~_T_57; // @[lifegame_fram.scala 209:17]
  wire  _GEN_479 = _GEN_465 & ~_T_51 & ~_T_57 & _T_63 & _T_42; // @[lifegame_fram.scala 209:17]
  SPIMaster spim ( // @[lifegame_fram.scala 57:22]
    .clock(spim_clock),
    .reset(spim_reset),
    .io_spi_miso(spim_io_spi_miso),
    .io_spi_mosi(spim_io_spi_mosi),
    .io_spi_cs(spim_io_spi_cs),
    .io_spi_sck(spim_io_spi_sck),
    .io_tx_ready(spim_io_tx_ready),
    .io_tx_valid(spim_io_tx_valid),
    .io_tx_bits(spim_io_tx_bits),
    .io_rx_ready(spim_io_rx_ready),
    .io_rx_valid(spim_io_rx_valid),
    .io_rx_bits(spim_io_rx_bits),
    .io_cs(spim_io_cs)
  );
  assign data = _data_T_1 ? matrix_0 : _data_T_22; // @[Mux.scala 98:16]
  assign row = rowEnable ? rowReg : 8'h0; // @[lifegame_fram.scala 325:15]
  assign spi_sck = spim_io_spi_sck; // @[lifegame_fram.scala 58:13]
  assign spi_si = spim_io_spi_mosi; // @[lifegame_fram.scala 59:12]
  assign spi_cs_n = spim_io_spi_cs; // @[lifegame_fram.scala 60:14]
  assign spi_wp_n = 1'h1; // @[lifegame_fram.scala 62:14]
  assign spi_hold_n = 1'h1; // @[lifegame_fram.scala 63:16]
  assign spim_clock = clock;
  assign spim_reset = reset;
  assign spim_io_spi_miso = spi_so; // @[lifegame_fram.scala 61:22]
  assign spim_io_tx_valid = spiTxCounter > 4'h0; // @[lifegame_fram.scala 89:38]
  assign spim_io_tx_bits = _spim_io_tx_bits_T ? 8'h0 : _spim_io_tx_bits_T_10; // @[Mux.scala 98:16]
  assign spim_io_rx_ready = spiRxCounter > 4'h0; // @[lifegame_fram.scala 113:38]
  assign spim_io_cs = cs_n; // @[lifegame_fram.scala 65:20]
  always @(posedge clock) begin
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (_T_48) begin // @[Conditional.scala 39:67]
          matrix_0 <= 8'h81; // @[lifegame_fram.scala 167:19]
        end else if (!(_T_51)) begin // @[Conditional.scala 39:67]
          matrix_0 <= _GEN_318;
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (_T_48) begin // @[Conditional.scala 39:67]
          matrix_1 <= 8'h42; // @[lifegame_fram.scala 168:19]
        end else if (!(_T_51)) begin // @[Conditional.scala 39:67]
          matrix_1 <= _GEN_319;
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (_T_48) begin // @[Conditional.scala 39:67]
          matrix_2 <= 8'h24; // @[lifegame_fram.scala 169:19]
        end else if (!(_T_51)) begin // @[Conditional.scala 39:67]
          matrix_2 <= _GEN_320;
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (_T_48) begin // @[Conditional.scala 39:67]
          matrix_3 <= 8'h18; // @[lifegame_fram.scala 170:19]
        end else if (!(_T_51)) begin // @[Conditional.scala 39:67]
          matrix_3 <= _GEN_321;
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (_T_48) begin // @[Conditional.scala 39:67]
          matrix_4 <= 8'h18; // @[lifegame_fram.scala 171:19]
        end else if (!(_T_51)) begin // @[Conditional.scala 39:67]
          matrix_4 <= _GEN_322;
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (_T_48) begin // @[Conditional.scala 39:67]
          matrix_5 <= 8'h24; // @[lifegame_fram.scala 172:19]
        end else if (!(_T_51)) begin // @[Conditional.scala 39:67]
          matrix_5 <= _GEN_323;
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (_T_48) begin // @[Conditional.scala 39:67]
          matrix_6 <= 8'h42; // @[lifegame_fram.scala 173:19]
        end else if (!(_T_51)) begin // @[Conditional.scala 39:67]
          matrix_6 <= _GEN_324;
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (_T_48) begin // @[Conditional.scala 39:67]
          matrix_7 <= 8'h81; // @[lifegame_fram.scala 174:19]
        end else if (!(_T_51)) begin // @[Conditional.scala 39:67]
          matrix_7 <= _GEN_325;
        end
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 122:41]
        if (_spim_io_tx_bits_T_2) begin // @[lifegame_fram.scala 125:39]
          if (3'h0 == boardAddress[2:0]) begin // @[lifegame_fram.scala 126:31]
            board_0 <= _board_T_26; // @[lifegame_fram.scala 126:31]
          end
        end
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 122:41]
        if (_spim_io_tx_bits_T_2) begin // @[lifegame_fram.scala 125:39]
          if (3'h1 == boardAddress[2:0]) begin // @[lifegame_fram.scala 126:31]
            board_1 <= _board_T_26; // @[lifegame_fram.scala 126:31]
          end
        end
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 122:41]
        if (_spim_io_tx_bits_T_2) begin // @[lifegame_fram.scala 125:39]
          if (3'h2 == boardAddress[2:0]) begin // @[lifegame_fram.scala 126:31]
            board_2 <= _board_T_26; // @[lifegame_fram.scala 126:31]
          end
        end
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 122:41]
        if (_spim_io_tx_bits_T_2) begin // @[lifegame_fram.scala 125:39]
          if (3'h3 == boardAddress[2:0]) begin // @[lifegame_fram.scala 126:31]
            board_3 <= _board_T_26; // @[lifegame_fram.scala 126:31]
          end
        end
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 122:41]
        if (_spim_io_tx_bits_T_2) begin // @[lifegame_fram.scala 125:39]
          if (3'h4 == boardAddress[2:0]) begin // @[lifegame_fram.scala 126:31]
            board_4 <= _board_T_26; // @[lifegame_fram.scala 126:31]
          end
        end
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 122:41]
        if (_spim_io_tx_bits_T_2) begin // @[lifegame_fram.scala 125:39]
          if (3'h5 == boardAddress[2:0]) begin // @[lifegame_fram.scala 126:31]
            board_5 <= _board_T_26; // @[lifegame_fram.scala 126:31]
          end
        end
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 122:41]
        if (_spim_io_tx_bits_T_2) begin // @[lifegame_fram.scala 125:39]
          if (3'h6 == boardAddress[2:0]) begin // @[lifegame_fram.scala 126:31]
            board_6 <= _board_T_26; // @[lifegame_fram.scala 126:31]
          end
        end
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 122:41]
        if (_spim_io_tx_bits_T_2) begin // @[lifegame_fram.scala 125:39]
          if (3'h7 == boardAddress[2:0]) begin // @[lifegame_fram.scala 126:31]
            board_7 <= _board_T_26; // @[lifegame_fram.scala 126:31]
          end
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          if (!(_T_51)) begin // @[Conditional.scala 39:67]
            boardNext_0 <= _GEN_309;
          end
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          if (!(_T_51)) begin // @[Conditional.scala 39:67]
            boardNext_1 <= _GEN_310;
          end
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          if (!(_T_51)) begin // @[Conditional.scala 39:67]
            boardNext_2 <= _GEN_311;
          end
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          if (!(_T_51)) begin // @[Conditional.scala 39:67]
            boardNext_3 <= _GEN_312;
          end
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          if (!(_T_51)) begin // @[Conditional.scala 39:67]
            boardNext_4 <= _GEN_313;
          end
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          if (!(_T_51)) begin // @[Conditional.scala 39:67]
            boardNext_5 <= _GEN_314;
          end
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          if (!(_T_51)) begin // @[Conditional.scala 39:67]
            boardNext_6 <= _GEN_315;
          end
        end
      end
    end
    if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          if (!(_T_51)) begin // @[Conditional.scala 39:67]
            boardNext_7 <= _GEN_316;
          end
        end
      end
    end
    if (reset) begin // @[lifegame_fram.scala 45:31]
      readChecksum <= 8'h0; // @[lifegame_fram.scala 45:31]
    end else if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (state == 4'h4) begin // @[lifegame_fram.scala 117:41]
        readChecksum <= 8'h0; // @[lifegame_fram.scala 118:22]
      end else if (_spim_io_tx_bits_T) begin // @[lifegame_fram.scala 119:48]
        readChecksum <= _readChecksum_T; // @[lifegame_fram.scala 120:22]
      end
    end
    if (reset) begin // @[lifegame_fram.scala 46:32]
      writeChecksum <= 8'h0; // @[lifegame_fram.scala 46:32]
    end else if (_spim_io_tx_valid_T & spim_io_tx_ready) begin // @[lifegame_fram.scala 90:52]
      if (state == 4'ha) begin // @[lifegame_fram.scala 92:42]
        writeChecksum <= 8'h0; // @[lifegame_fram.scala 93:23]
      end else if (_spim_io_tx_bits_T_1) begin // @[lifegame_fram.scala 94:49]
        writeChecksum <= _GEN_16;
      end
    end
    if (_T_34) begin // @[Conditional.scala 40:58]
      spiTxBuffer_4 <= 8'h9f; // @[lifegame_fram.scala 147:42]
    end else if (_T_39) begin // @[Conditional.scala 39:67]
      spiTxBuffer_4 <= _GEN_40;
    end else if (_T_48) begin // @[Conditional.scala 39:67]
      spiTxBuffer_4 <= _GEN_40;
    end else if (_T_51) begin // @[Conditional.scala 39:67]
      spiTxBuffer_4 <= _GEN_96;
    end else begin
      spiTxBuffer_4 <= _GEN_317;
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (!(_spim_io_tx_bits_T)) begin // @[lifegame_fram.scala 122:41]
        spiRxBuffer_0 <= _board_T_26; // @[lifegame_fram.scala 135:21]
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (!(_spim_io_tx_bits_T)) begin // @[lifegame_fram.scala 122:41]
        spiRxBuffer_1 <= spiRxBuffer_0; // @[lifegame_fram.scala 135:21]
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (!(_spim_io_tx_bits_T)) begin // @[lifegame_fram.scala 122:41]
        spiRxBuffer_2 <= spiRxBuffer_1; // @[lifegame_fram.scala 135:21]
      end
    end
    if (_spim_io_rx_ready_T & spim_io_rx_valid) begin // @[lifegame_fram.scala 114:52]
      if (!(_spim_io_tx_bits_T)) begin // @[lifegame_fram.scala 122:41]
        spiRxBuffer_3 <= spiRxBuffer_2; // @[lifegame_fram.scala 135:21]
      end
    end
    if (reset) begin // @[lifegame_fram.scala 50:31]
      spiTxCounter <= 4'h0; // @[lifegame_fram.scala 50:31]
    end else if (_T_34) begin // @[Conditional.scala 40:58]
      spiTxCounter <= 4'h5; // @[lifegame_fram.scala 145:22]
    end else if (_T_39) begin // @[Conditional.scala 39:67]
      spiTxCounter <= _GEN_33;
    end else if (_T_48) begin // @[Conditional.scala 39:67]
      spiTxCounter <= _GEN_33;
    end else begin
      spiTxCounter <= _GEN_331;
    end
    if (reset) begin // @[lifegame_fram.scala 51:31]
      spiRxCounter <= 4'h0; // @[lifegame_fram.scala 51:31]
    end else if (_T_34) begin // @[Conditional.scala 40:58]
      spiRxCounter <= 4'h5; // @[lifegame_fram.scala 146:22]
    end else if (_T_39) begin // @[Conditional.scala 39:67]
      spiRxCounter <= _GEN_73;
    end else if (_T_48) begin // @[Conditional.scala 39:67]
      spiRxCounter <= _GEN_73;
    end else begin
      spiRxCounter <= _GEN_332;
    end
    if (reset) begin // @[lifegame_fram.scala 52:31]
      boardAddress <= 4'h0; // @[lifegame_fram.scala 52:31]
    end else if (_T_34) begin // @[Conditional.scala 40:58]
      boardAddress <= _GEN_75;
    end else if (_T_39) begin // @[Conditional.scala 39:67]
      boardAddress <= _GEN_75;
    end else if (_T_48) begin // @[Conditional.scala 39:67]
      boardAddress <= _GEN_75;
    end else begin
      boardAddress <= _GEN_340;
    end
    if (reset) begin // @[lifegame_fram.scala 53:28]
      updateRow <= 3'h0; // @[lifegame_fram.scala 53:28]
    end else if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          updateRow <= _GEN_337;
        end
      end
    end
    if (reset) begin // @[lifegame_fram.scala 54:31]
      updateColumn <= 3'h0; // @[lifegame_fram.scala 54:31]
    end else if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          updateColumn <= _GEN_338;
        end
      end
    end
    if (reset) begin // @[lifegame_fram.scala 55:32]
      updateCounter <= 25'h0; // @[lifegame_fram.scala 55:32]
    end else if (!(_T_34)) begin // @[Conditional.scala 40:58]
      if (!(_T_39)) begin // @[Conditional.scala 39:67]
        if (!(_T_48)) begin // @[Conditional.scala 39:67]
          updateCounter <= _GEN_329;
        end
      end
    end
    cs_n <= reset | _GEN_413; // @[lifegame_fram.scala 64:23 lifegame_fram.scala 64:23]
    if (reset) begin // @[lifegame_fram.scala 81:24]
      state <= 4'h0; // @[lifegame_fram.scala 81:24]
    end else if (_T_34) begin // @[Conditional.scala 40:58]
      state <= 4'h1; // @[lifegame_fram.scala 152:15]
    end else if (_T_39) begin // @[Conditional.scala 39:67]
      if (spiTxCounter == 4'h0 & spiRxCounter == 4'h0) begin // @[lifegame_fram.scala 155:60]
        state <= {{2'd0}, _GEN_89};
      end
    end else if (_T_48) begin // @[Conditional.scala 39:67]
      state <= 4'h2; // @[lifegame_fram.scala 175:15]
    end else begin
      state <= _GEN_339;
    end
    if (reset) begin // @[lifegame_fram.scala 322:33]
      refreshCounter <= 15'h0; // @[lifegame_fram.scala 322:33]
    end else if (refreshCounter < 15'h675b) begin // @[lifegame_fram.scala 330:79]
      refreshCounter <= _refreshCounter_T_1; // @[lifegame_fram.scala 329:20]
    end else if (refreshCounter == 15'h6869) begin // @[lifegame_fram.scala 331:86]
      refreshCounter <= _refreshCounter_T_1; // @[lifegame_fram.scala 329:20]
    end else if (refreshCounter < 15'h6977) begin // @[lifegame_fram.scala 334:61]
      refreshCounter <= _refreshCounter_T_1; // @[lifegame_fram.scala 329:20]
    end else begin
      refreshCounter <= _GEN_442;
    end
    if (reset) begin // @[lifegame_fram.scala 323:25]
      rowReg <= 8'h1; // @[lifegame_fram.scala 323:25]
    end else begin
      rowReg <= _GEN_449[7:0];
    end
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_T_1 & _spim_io_tx_bits_T_1 & ~reset) begin
          $fwrite(32'h80000002,"[LIFEGAME] WriteBoard %x, %x, spiTxCounterNext=%d\n",boardAddress,_GEN_7,
            _spiTxCounter_T_1); // @[lifegame_fram.scala 100:15]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_T_1 & ~_spim_io_tx_bits_T_1 & _T_10) begin
          $fwrite(32'h80000002,"[LIFEGAME] Write Sent=%x BufferNext=%x, spiTxCounterNext=%d\n",spiTxBuffer_4,40'h0,
            _spiTxCounter_T_1); // @[lifegame_fram.scala 110:15]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_T_17 & _spim_io_tx_bits_T & _T_10) begin
          $fwrite(32'h80000002,"[LIFEGAME] ReadBoard %x, %x, spiRxCounterNext=%d\n",boardAddress,spim_io_rx_bits,
            _spiRxCounter_T_1); // @[lifegame_fram.scala 123:15]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_T_17 & ~_spim_io_tx_bits_T & _T_10) begin
          $fwrite(32'h80000002,"[LIFEGAME] Read %x, spiRxCounterNext=%d\n",{spiRxBuffer_3,spiRxBuffer_2,spiRxBuffer_1,
            spiRxBuffer_0,_board_T_26},_spiRxCounter_T_1); // @[lifegame_fram.scala 136:15]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_T_34 & _T_10) begin
          $fwrite(32'h80000002,"[LIFEGAME] Reset\n"); // @[lifegame_fram.scala 143:15]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (~_T_34 & _T_39 & _T_42 & _T_10) begin
          $fwrite(32'h80000002,"[LIFEGAME] ReadId DeviceID=%x\n",deviceId); // @[lifegame_fram.scala 158:17]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_GEN_458 & ~_T_39 & ~_T_48 & _T_51 & ~_T_52 & _T_10) begin
          $fwrite(32'h80000002,"[LIFEGAME] Idle->IssueRead\n"); // @[lifegame_fram.scala 181:17]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_GEN_465 & ~_T_51 & ~_T_57 & _T_63 & _T_42 & _T_10) begin
          $fwrite(32'h80000002,"[LIFEGAME] Checksum=%x ",readChecksum); // @[lifegame_fram.scala 209:17]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_GEN_479 & _T_69 & _T_10) begin
          $fwrite(32'h80000002,"Valid\n"); // @[lifegame_fram.scala 211:19]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_GEN_479 & ~_T_69 & _T_10) begin
          $fwrite(32'h80000002,"Invalid\n"); // @[lifegame_fram.scala 222:19]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
    `ifndef SYNTHESIS
    `ifdef PRINTF_COND
      if (`PRINTF_COND) begin
    `endif
        if (_GEN_477 & ~_T_63 & ~_T_84 & ~_T_87 & _T_99 & _T_10) begin
          $fwrite(32'h80000002,"[LIFEGAME] CheckStall %d\n",stall); // @[lifegame_fram.scala 280:15]
        end
    `ifdef PRINTF_COND
      end
    `endif
    `endif // SYNTHESIS
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
  matrix_0 = _RAND_0[7:0];
  _RAND_1 = {1{`RANDOM}};
  matrix_1 = _RAND_1[7:0];
  _RAND_2 = {1{`RANDOM}};
  matrix_2 = _RAND_2[7:0];
  _RAND_3 = {1{`RANDOM}};
  matrix_3 = _RAND_3[7:0];
  _RAND_4 = {1{`RANDOM}};
  matrix_4 = _RAND_4[7:0];
  _RAND_5 = {1{`RANDOM}};
  matrix_5 = _RAND_5[7:0];
  _RAND_6 = {1{`RANDOM}};
  matrix_6 = _RAND_6[7:0];
  _RAND_7 = {1{`RANDOM}};
  matrix_7 = _RAND_7[7:0];
  _RAND_8 = {1{`RANDOM}};
  board_0 = _RAND_8[7:0];
  _RAND_9 = {1{`RANDOM}};
  board_1 = _RAND_9[7:0];
  _RAND_10 = {1{`RANDOM}};
  board_2 = _RAND_10[7:0];
  _RAND_11 = {1{`RANDOM}};
  board_3 = _RAND_11[7:0];
  _RAND_12 = {1{`RANDOM}};
  board_4 = _RAND_12[7:0];
  _RAND_13 = {1{`RANDOM}};
  board_5 = _RAND_13[7:0];
  _RAND_14 = {1{`RANDOM}};
  board_6 = _RAND_14[7:0];
  _RAND_15 = {1{`RANDOM}};
  board_7 = _RAND_15[7:0];
  _RAND_16 = {1{`RANDOM}};
  boardNext_0 = _RAND_16[7:0];
  _RAND_17 = {1{`RANDOM}};
  boardNext_1 = _RAND_17[7:0];
  _RAND_18 = {1{`RANDOM}};
  boardNext_2 = _RAND_18[7:0];
  _RAND_19 = {1{`RANDOM}};
  boardNext_3 = _RAND_19[7:0];
  _RAND_20 = {1{`RANDOM}};
  boardNext_4 = _RAND_20[7:0];
  _RAND_21 = {1{`RANDOM}};
  boardNext_5 = _RAND_21[7:0];
  _RAND_22 = {1{`RANDOM}};
  boardNext_6 = _RAND_22[7:0];
  _RAND_23 = {1{`RANDOM}};
  boardNext_7 = _RAND_23[7:0];
  _RAND_24 = {1{`RANDOM}};
  readChecksum = _RAND_24[7:0];
  _RAND_25 = {1{`RANDOM}};
  writeChecksum = _RAND_25[7:0];
  _RAND_26 = {1{`RANDOM}};
  spiTxBuffer_4 = _RAND_26[7:0];
  _RAND_27 = {1{`RANDOM}};
  spiRxBuffer_0 = _RAND_27[7:0];
  _RAND_28 = {1{`RANDOM}};
  spiRxBuffer_1 = _RAND_28[7:0];
  _RAND_29 = {1{`RANDOM}};
  spiRxBuffer_2 = _RAND_29[7:0];
  _RAND_30 = {1{`RANDOM}};
  spiRxBuffer_3 = _RAND_30[7:0];
  _RAND_31 = {1{`RANDOM}};
  spiTxCounter = _RAND_31[3:0];
  _RAND_32 = {1{`RANDOM}};
  spiRxCounter = _RAND_32[3:0];
  _RAND_33 = {1{`RANDOM}};
  boardAddress = _RAND_33[3:0];
  _RAND_34 = {1{`RANDOM}};
  updateRow = _RAND_34[2:0];
  _RAND_35 = {1{`RANDOM}};
  updateColumn = _RAND_35[2:0];
  _RAND_36 = {1{`RANDOM}};
  updateCounter = _RAND_36[24:0];
  _RAND_37 = {1{`RANDOM}};
  cs_n = _RAND_37[0:0];
  _RAND_38 = {1{`RANDOM}};
  state = _RAND_38[3:0];
  _RAND_39 = {1{`RANDOM}};
  refreshCounter = _RAND_39[14:0];
  _RAND_40 = {1{`RANDOM}};
  rowReg = _RAND_40[7:0];
`endif // RANDOMIZE_REG_INIT
  `endif // RANDOMIZE
end // initial
`ifdef FIRRTL_AFTER_INITIAL
`FIRRTL_AFTER_INITIAL
`endif
`endif // SYNTHESIS
endmodule
