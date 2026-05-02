module DviOut(
  input         clock,
  input         reset,
  input  [23:0] io_video_pixelData,
  input         io_video_hSync,
  input         io_video_vSync,
  input         io_video_dataEnable,
  output [9:0]  io_dviClock,
  output [9:0]  io_dviData0,
  output [9:0]  io_dviData1,
  output [9:0]  io_dviData2
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
`endif // RANDOMIZE_REG_INIT
  reg [9:0] dviData_0; // @[dvi_out.scala 26:26]
  reg [9:0] dviData_1; // @[dvi_out.scala 26:26]
  reg [9:0] dviData_2; // @[dvi_out.scala 26:26]
  reg [26:0] videoRegs_0_pixelData; // @[dvi_out.scala 34:28]
  reg  videoRegs_0_hSync; // @[dvi_out.scala 34:28]
  reg  videoRegs_0_vSync; // @[dvi_out.scala 34:28]
  reg  videoRegs_0_dataEnable; // @[dvi_out.scala 34:28]
  reg [26:0] videoRegs_1_pixelData; // @[dvi_out.scala 34:28]
  reg  videoRegs_1_hSync; // @[dvi_out.scala 34:28]
  reg  videoRegs_1_vSync; // @[dvi_out.scala 34:28]
  reg  videoRegs_1_dataEnable; // @[dvi_out.scala 34:28]
  reg [26:0] videoRegs_2_pixelData; // @[dvi_out.scala 34:28]
  reg  videoRegs_2_hSync; // @[dvi_out.scala 34:28]
  reg  videoRegs_2_vSync; // @[dvi_out.scala 34:28]
  reg  videoRegs_2_dataEnable; // @[dvi_out.scala 34:28]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_8 = io_video_pixelData[0] + io_video_pixelData[1]; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_10 = io_video_pixelData[2] + io_video_pixelData[3]; // @[Bitwise.scala 47:55]
  wire [2:0] _videoRegs_2_pixelData_popCount_T_12 = _videoRegs_2_pixelData_popCount_T_8 +
    _videoRegs_2_pixelData_popCount_T_10; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_14 = io_video_pixelData[4] + io_video_pixelData[5]; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_16 = io_video_pixelData[6] + io_video_pixelData[7]; // @[Bitwise.scala 47:55]
  wire [2:0] _videoRegs_2_pixelData_popCount_T_18 = _videoRegs_2_pixelData_popCount_T_14 +
    _videoRegs_2_pixelData_popCount_T_16; // @[Bitwise.scala 47:55]
  wire [3:0] videoRegs_2_pixelData_popCount = _videoRegs_2_pixelData_popCount_T_12 +
    _videoRegs_2_pixelData_popCount_T_18; // @[Bitwise.scala 47:55]
  wire  videoRegs_2_pixelData_xnorProcess = videoRegs_2_pixelData_popCount > 4'h4 | videoRegs_2_pixelData_popCount == 4'h4
     & ~io_video_pixelData[0]; // @[dvi_out.scala 46:42]
  wire  videoRegs_2_pixelData_bits__1 = io_video_pixelData[0] ^ io_video_pixelData[1] ^
    videoRegs_2_pixelData_xnorProcess; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits__2 = videoRegs_2_pixelData_bits__1 ^ io_video_pixelData[2] ^
    videoRegs_2_pixelData_xnorProcess; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits__3 = videoRegs_2_pixelData_bits__2 ^ io_video_pixelData[3] ^
    videoRegs_2_pixelData_xnorProcess; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits__4 = videoRegs_2_pixelData_bits__3 ^ io_video_pixelData[4] ^
    videoRegs_2_pixelData_xnorProcess; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits__5 = videoRegs_2_pixelData_bits__4 ^ io_video_pixelData[5] ^
    videoRegs_2_pixelData_xnorProcess; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits__6 = videoRegs_2_pixelData_bits__5 ^ io_video_pixelData[6] ^
    videoRegs_2_pixelData_xnorProcess; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits__7 = videoRegs_2_pixelData_bits__6 ^ io_video_pixelData[7] ^
    videoRegs_2_pixelData_xnorProcess; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_hi = ~videoRegs_2_pixelData_xnorProcess; // @[dvi_out.scala 52:13]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_29 = io_video_pixelData[8] + io_video_pixelData[9]; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_31 = io_video_pixelData[10] + io_video_pixelData[11]; // @[Bitwise.scala 47:55]
  wire [2:0] _videoRegs_2_pixelData_popCount_T_33 = _videoRegs_2_pixelData_popCount_T_29 +
    _videoRegs_2_pixelData_popCount_T_31; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_35 = io_video_pixelData[12] + io_video_pixelData[13]; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_37 = io_video_pixelData[14] + io_video_pixelData[15]; // @[Bitwise.scala 47:55]
  wire [2:0] _videoRegs_2_pixelData_popCount_T_39 = _videoRegs_2_pixelData_popCount_T_35 +
    _videoRegs_2_pixelData_popCount_T_37; // @[Bitwise.scala 47:55]
  wire [3:0] videoRegs_2_pixelData_popCount_1 = _videoRegs_2_pixelData_popCount_T_33 +
    _videoRegs_2_pixelData_popCount_T_39; // @[Bitwise.scala 47:55]
  wire  videoRegs_2_pixelData_xnorProcess_1 = videoRegs_2_pixelData_popCount_1 > 4'h4 | videoRegs_2_pixelData_popCount_1
     == 4'h4 & ~io_video_pixelData[8]; // @[dvi_out.scala 46:42]
  wire  videoRegs_2_pixelData_bits_1_1 = io_video_pixelData[8] ^ io_video_pixelData[9] ^
    videoRegs_2_pixelData_xnorProcess_1; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_1_2 = videoRegs_2_pixelData_bits_1_1 ^ io_video_pixelData[10] ^
    videoRegs_2_pixelData_xnorProcess_1; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_1_3 = videoRegs_2_pixelData_bits_1_2 ^ io_video_pixelData[11] ^
    videoRegs_2_pixelData_xnorProcess_1; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_1_4 = videoRegs_2_pixelData_bits_1_3 ^ io_video_pixelData[12] ^
    videoRegs_2_pixelData_xnorProcess_1; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_1_5 = videoRegs_2_pixelData_bits_1_4 ^ io_video_pixelData[13] ^
    videoRegs_2_pixelData_xnorProcess_1; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_1_6 = videoRegs_2_pixelData_bits_1_5 ^ io_video_pixelData[14] ^
    videoRegs_2_pixelData_xnorProcess_1; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_1_7 = videoRegs_2_pixelData_bits_1_6 ^ io_video_pixelData[15] ^
    videoRegs_2_pixelData_xnorProcess_1; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_hi_2 = ~videoRegs_2_pixelData_xnorProcess_1; // @[dvi_out.scala 52:13]
  wire [8:0] videoRegs_2_pixelData_hi_lo_2 = {videoRegs_2_pixelData_hi_2,videoRegs_2_pixelData_bits_1_7,
    videoRegs_2_pixelData_bits_1_6,videoRegs_2_pixelData_bits_1_5,videoRegs_2_pixelData_bits_1_4,
    videoRegs_2_pixelData_bits_1_3,videoRegs_2_pixelData_bits_1_2,videoRegs_2_pixelData_bits_1_1,io_video_pixelData[8]}; // @[Cat.scala 30:58]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_50 = io_video_pixelData[16] + io_video_pixelData[17]; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_52 = io_video_pixelData[18] + io_video_pixelData[19]; // @[Bitwise.scala 47:55]
  wire [2:0] _videoRegs_2_pixelData_popCount_T_54 = _videoRegs_2_pixelData_popCount_T_50 +
    _videoRegs_2_pixelData_popCount_T_52; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_56 = io_video_pixelData[20] + io_video_pixelData[21]; // @[Bitwise.scala 47:55]
  wire [1:0] _videoRegs_2_pixelData_popCount_T_58 = io_video_pixelData[22] + io_video_pixelData[23]; // @[Bitwise.scala 47:55]
  wire [2:0] _videoRegs_2_pixelData_popCount_T_60 = _videoRegs_2_pixelData_popCount_T_56 +
    _videoRegs_2_pixelData_popCount_T_58; // @[Bitwise.scala 47:55]
  wire [3:0] videoRegs_2_pixelData_popCount_2 = _videoRegs_2_pixelData_popCount_T_54 +
    _videoRegs_2_pixelData_popCount_T_60; // @[Bitwise.scala 47:55]
  wire  videoRegs_2_pixelData_xnorProcess_2 = videoRegs_2_pixelData_popCount_2 > 4'h4 | videoRegs_2_pixelData_popCount_2
     == 4'h4 & ~io_video_pixelData[16]; // @[dvi_out.scala 46:42]
  wire  videoRegs_2_pixelData_bits_2_1 = io_video_pixelData[16] ^ io_video_pixelData[17] ^
    videoRegs_2_pixelData_xnorProcess_2; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_2_2 = videoRegs_2_pixelData_bits_2_1 ^ io_video_pixelData[18] ^
    videoRegs_2_pixelData_xnorProcess_2; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_2_3 = videoRegs_2_pixelData_bits_2_2 ^ io_video_pixelData[19] ^
    videoRegs_2_pixelData_xnorProcess_2; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_2_4 = videoRegs_2_pixelData_bits_2_3 ^ io_video_pixelData[20] ^
    videoRegs_2_pixelData_xnorProcess_2; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_2_5 = videoRegs_2_pixelData_bits_2_4 ^ io_video_pixelData[21] ^
    videoRegs_2_pixelData_xnorProcess_2; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_2_6 = videoRegs_2_pixelData_bits_2_5 ^ io_video_pixelData[22] ^
    videoRegs_2_pixelData_xnorProcess_2; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_bits_2_7 = videoRegs_2_pixelData_bits_2_6 ^ io_video_pixelData[23] ^
    videoRegs_2_pixelData_xnorProcess_2; // @[dvi_out.scala 50:46]
  wire  videoRegs_2_pixelData_hi_4 = ~videoRegs_2_pixelData_xnorProcess_2; // @[dvi_out.scala 52:13]
  wire [17:0] videoRegs_2_pixelData_hi_6 = {videoRegs_2_pixelData_hi_4,videoRegs_2_pixelData_bits_2_7,
    videoRegs_2_pixelData_bits_2_6,videoRegs_2_pixelData_bits_2_5,videoRegs_2_pixelData_bits_2_4,
    videoRegs_2_pixelData_bits_2_3,videoRegs_2_pixelData_bits_2_2,videoRegs_2_pixelData_bits_2_1,io_video_pixelData[16],
    videoRegs_2_pixelData_hi_lo_2}; // @[Cat.scala 30:58]
  wire [26:0] _videoRegs_2_pixelData_T_3 = {videoRegs_2_pixelData_hi_6,videoRegs_2_pixelData_hi,
    videoRegs_2_pixelData_bits__7,videoRegs_2_pixelData_bits__6,videoRegs_2_pixelData_bits__5,
    videoRegs_2_pixelData_bits__4,videoRegs_2_pixelData_bits__3,videoRegs_2_pixelData_bits__2,
    videoRegs_2_pixelData_bits__1,io_video_pixelData[0]}; // @[Cat.scala 30:58]
  reg [7:0] counter_0; // @[dvi_out.scala 110:26]
  reg [7:0] counter_1; // @[dvi_out.scala 110:26]
  reg [7:0] counter_2; // @[dvi_out.scala 110:26]
  wire [1:0] _dviData_0_T = {videoRegs_0_vSync,videoRegs_0_hSync}; // @[Cat.scala 30:58]
  wire [9:0] _dviData_0_T_2 = 2'h1 == _dviData_0_T ? 10'hab : 10'h354; // @[Mux.scala 80:57]
  wire [8:0] out_lo = videoRegs_0_pixelData[8:0]; // @[dvi_out.scala 121:71]
  wire [1:0] _n1_T_9 = out_lo[0] + out_lo[1]; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_11 = out_lo[2] + out_lo[3]; // @[Bitwise.scala 47:55]
  wire [2:0] _n1_T_13 = _n1_T_9 + _n1_T_11; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_15 = out_lo[4] + out_lo[5]; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_17 = out_lo[6] + out_lo[7]; // @[Bitwise.scala 47:55]
  wire [2:0] _n1_T_19 = _n1_T_15 + _n1_T_17; // @[Bitwise.scala 47:55]
  wire [3:0] n1 = _n1_T_13 + _n1_T_19; // @[Bitwise.scala 47:55]
  wire [4:0] _n0n1_T = {n1, 1'h0}; // @[dvi_out.scala 58:30]
  wire [5:0] _n0n1_T_1 = {1'b0,$signed(_n0n1_T)}; // @[dvi_out.scala 58:36]
  wire [5:0] n0n1 = 6'sh8 - $signed(_n0n1_T_1); // @[dvi_out.scala 58:24]
  wire  out_hi_hi = ~out_lo[8]; // @[dvi_out.scala 64:17]
  wire [7:0] _out_T_5 = ~out_lo[7:0]; // @[dvi_out.scala 66:38]
  wire [7:0] out_lo_1 = out_lo[8] ? out_lo[7:0] : _out_T_5; // @[dvi_out.scala 66:20]
  wire [9:0] _out_T_6 = {out_hi_hi,out_lo[8],out_lo_1}; // @[Cat.scala 30:58]
  wire [7:0] _GEN_27 = {{2{n0n1[5]}},n0n1}; // @[dvi_out.scala 69:39]
  wire [7:0] _newCounter_T_2 = $signed(counter_0) - $signed(_GEN_27); // @[dvi_out.scala 69:39]
  wire [7:0] _newCounter_T_5 = $signed(counter_0) + $signed(_GEN_27); // @[dvi_out.scala 71:39]
  wire [9:0] _out_T_8 = {1'h1,out_lo[8],_out_T_5}; // @[Cat.scala 30:58]
  wire [7:0] _newCounter_T_11 = $signed(_newCounter_T_5) + 8'sh2; // @[dvi_out.scala 80:46]
  wire [7:0] _GEN_1 = out_lo[8] ? $signed(_newCounter_T_11) : $signed(_newCounter_T_5); // @[dvi_out.scala 79:27 dvi_out.scala 80:28 dvi_out.scala 82:28]
  wire [9:0] _out_T_9 = {1'h0,out_lo[8],out_lo[7:0]}; // @[Cat.scala 30:58]
  wire [7:0] _newCounter_T_23 = $signed(_newCounter_T_2) - 8'sh2; // @[dvi_out.scala 93:46]
  wire [7:0] _GEN_2 = out_lo[8] ? $signed(_newCounter_T_2) : $signed(_newCounter_T_23); // @[dvi_out.scala 90:27 dvi_out.scala 91:28 dvi_out.scala 93:28]
  wire [8:0] out_lo_4 = videoRegs_0_pixelData[17:9]; // @[dvi_out.scala 121:71]
  wire [1:0] _n1_T_31 = out_lo_4[0] + out_lo_4[1]; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_33 = out_lo_4[2] + out_lo_4[3]; // @[Bitwise.scala 47:55]
  wire [2:0] _n1_T_35 = _n1_T_31 + _n1_T_33; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_37 = out_lo_4[4] + out_lo_4[5]; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_39 = out_lo_4[6] + out_lo_4[7]; // @[Bitwise.scala 47:55]
  wire [2:0] _n1_T_41 = _n1_T_37 + _n1_T_39; // @[Bitwise.scala 47:55]
  wire [3:0] n1_1 = _n1_T_35 + _n1_T_41; // @[Bitwise.scala 47:55]
  wire [4:0] _n0n1_T_4 = {n1_1, 1'h0}; // @[dvi_out.scala 58:30]
  wire [5:0] _n0n1_T_5 = {1'b0,$signed(_n0n1_T_4)}; // @[dvi_out.scala 58:36]
  wire [5:0] n0n1_1 = 6'sh8 - $signed(_n0n1_T_5); // @[dvi_out.scala 58:24]
  wire  out_hi_hi_1 = ~out_lo_4[8]; // @[dvi_out.scala 64:17]
  wire [7:0] _out_T_15 = ~out_lo_4[7:0]; // @[dvi_out.scala 66:38]
  wire [7:0] out_lo_5 = out_lo_4[8] ? out_lo_4[7:0] : _out_T_15; // @[dvi_out.scala 66:20]
  wire [9:0] _out_T_16 = {out_hi_hi_1,out_lo_4[8],out_lo_5}; // @[Cat.scala 30:58]
  wire [7:0] _GEN_33 = {{2{n0n1_1[5]}},n0n1_1}; // @[dvi_out.scala 69:39]
  wire [7:0] _newCounter_T_26 = $signed(counter_1) - $signed(_GEN_33); // @[dvi_out.scala 69:39]
  wire [7:0] _newCounter_T_29 = $signed(counter_1) + $signed(_GEN_33); // @[dvi_out.scala 71:39]
  wire [9:0] _out_T_18 = {1'h1,out_lo_4[8],_out_T_15}; // @[Cat.scala 30:58]
  wire [7:0] _newCounter_T_35 = $signed(_newCounter_T_29) + 8'sh2; // @[dvi_out.scala 80:46]
  wire [7:0] _GEN_8 = out_lo_4[8] ? $signed(_newCounter_T_35) : $signed(_newCounter_T_29); // @[dvi_out.scala 79:27 dvi_out.scala 80:28 dvi_out.scala 82:28]
  wire [9:0] _out_T_19 = {1'h0,out_lo_4[8],out_lo_4[7:0]}; // @[Cat.scala 30:58]
  wire [7:0] _newCounter_T_47 = $signed(_newCounter_T_26) - 8'sh2; // @[dvi_out.scala 93:46]
  wire [7:0] _GEN_9 = out_lo_4[8] ? $signed(_newCounter_T_26) : $signed(_newCounter_T_47); // @[dvi_out.scala 90:27 dvi_out.scala 91:28 dvi_out.scala 93:28]
  wire [8:0] out_lo_8 = videoRegs_0_pixelData[26:18]; // @[dvi_out.scala 121:71]
  wire [1:0] _n1_T_53 = out_lo_8[0] + out_lo_8[1]; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_55 = out_lo_8[2] + out_lo_8[3]; // @[Bitwise.scala 47:55]
  wire [2:0] _n1_T_57 = _n1_T_53 + _n1_T_55; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_59 = out_lo_8[4] + out_lo_8[5]; // @[Bitwise.scala 47:55]
  wire [1:0] _n1_T_61 = out_lo_8[6] + out_lo_8[7]; // @[Bitwise.scala 47:55]
  wire [2:0] _n1_T_63 = _n1_T_59 + _n1_T_61; // @[Bitwise.scala 47:55]
  wire [3:0] n1_2 = _n1_T_57 + _n1_T_63; // @[Bitwise.scala 47:55]
  wire [4:0] _n0n1_T_8 = {n1_2, 1'h0}; // @[dvi_out.scala 58:30]
  wire [5:0] _n0n1_T_9 = {1'b0,$signed(_n0n1_T_8)}; // @[dvi_out.scala 58:36]
  wire [5:0] n0n1_2 = 6'sh8 - $signed(_n0n1_T_9); // @[dvi_out.scala 58:24]
  wire  out_hi_hi_2 = ~out_lo_8[8]; // @[dvi_out.scala 64:17]
  wire [7:0] _out_T_25 = ~out_lo_8[7:0]; // @[dvi_out.scala 66:38]
  wire [7:0] out_lo_9 = out_lo_8[8] ? out_lo_8[7:0] : _out_T_25; // @[dvi_out.scala 66:20]
  wire [9:0] _out_T_26 = {out_hi_hi_2,out_lo_8[8],out_lo_9}; // @[Cat.scala 30:58]
  wire [7:0] _GEN_39 = {{2{n0n1_2[5]}},n0n1_2}; // @[dvi_out.scala 69:39]
  wire [7:0] _newCounter_T_50 = $signed(counter_2) - $signed(_GEN_39); // @[dvi_out.scala 69:39]
  wire [7:0] _newCounter_T_53 = $signed(counter_2) + $signed(_GEN_39); // @[dvi_out.scala 71:39]
  wire [9:0] _out_T_28 = {1'h1,out_lo_8[8],_out_T_25}; // @[Cat.scala 30:58]
  wire [7:0] _newCounter_T_59 = $signed(_newCounter_T_53) + 8'sh2; // @[dvi_out.scala 80:46]
  wire [7:0] _GEN_15 = out_lo_8[8] ? $signed(_newCounter_T_59) : $signed(_newCounter_T_53); // @[dvi_out.scala 79:27 dvi_out.scala 80:28 dvi_out.scala 82:28]
  wire [9:0] _out_T_29 = {1'h0,out_lo_8[8],out_lo_8[7:0]}; // @[Cat.scala 30:58]
  wire [7:0] _newCounter_T_71 = $signed(_newCounter_T_50) - 8'sh2; // @[dvi_out.scala 93:46]
  wire [7:0] _GEN_16 = out_lo_8[8] ? $signed(_newCounter_T_50) : $signed(_newCounter_T_71); // @[dvi_out.scala 90:27 dvi_out.scala 91:28 dvi_out.scala 93:28]
  assign io_dviClock = 10'h1f; // @[dvi_out.scala 30:17]
  assign io_dviData0 = dviData_0; // @[dvi_out.scala 27:17]
  assign io_dviData1 = dviData_1; // @[dvi_out.scala 28:17]
  assign io_dviData2 = dviData_2; // @[dvi_out.scala 29:17]
  always @(posedge clock) begin
    if (reset) begin // @[dvi_out.scala 26:26]
      dviData_0 <= 10'h0; // @[dvi_out.scala 26:26]
    end else if (~videoRegs_0_dataEnable) begin // @[dvi_out.scala 111:29]
      if (2'h3 == _dviData_0_T) begin // @[Mux.scala 80:57]
        dviData_0 <= 10'h2ab;
      end else if (2'h2 == _dviData_0_T) begin // @[Mux.scala 80:57]
        dviData_0 <= 10'h154;
      end else begin
        dviData_0 <= _dviData_0_T_2;
      end
    end else if ($signed(counter_0) == 8'sh0 | $signed(n0n1) == 6'sh0) begin // @[dvi_out.scala 62:47]
      dviData_0 <= _out_T_6; // @[dvi_out.scala 63:17]
    end else if ($signed(counter_0) > 8'sh0 & $signed(n0n1) < 6'sh0 | $signed(counter_0) < 8'sh0 & $signed(n0n1) > 6'sh0
      ) begin // @[dvi_out.scala 73:87]
      dviData_0 <= _out_T_8; // @[dvi_out.scala 74:17]
    end else begin
      dviData_0 <= _out_T_9; // @[dvi_out.scala 85:17]
    end
    if (reset) begin // @[dvi_out.scala 26:26]
      dviData_1 <= 10'h0; // @[dvi_out.scala 26:26]
    end else if (~videoRegs_0_dataEnable) begin // @[dvi_out.scala 111:29]
      dviData_1 <= 10'h354; // @[dvi_out.scala 113:20]
    end else if ($signed(counter_1) == 8'sh0 | $signed(n0n1_1) == 6'sh0) begin // @[dvi_out.scala 62:47]
      dviData_1 <= _out_T_16; // @[dvi_out.scala 63:17]
    end else if ($signed(counter_1) > 8'sh0 & $signed(n0n1_1) < 6'sh0 | $signed(counter_1) < 8'sh0 & $signed(n0n1_1) > 6'sh0
      ) begin // @[dvi_out.scala 73:87]
      dviData_1 <= _out_T_18; // @[dvi_out.scala 74:17]
    end else begin
      dviData_1 <= _out_T_19; // @[dvi_out.scala 85:17]
    end
    if (reset) begin // @[dvi_out.scala 26:26]
      dviData_2 <= 10'h0; // @[dvi_out.scala 26:26]
    end else if (~videoRegs_0_dataEnable) begin // @[dvi_out.scala 111:29]
      dviData_2 <= 10'h354; // @[dvi_out.scala 114:20]
    end else if ($signed(counter_2) == 8'sh0 | $signed(n0n1_2) == 6'sh0) begin // @[dvi_out.scala 62:47]
      dviData_2 <= _out_T_26; // @[dvi_out.scala 63:17]
    end else if ($signed(counter_2) > 8'sh0 & $signed(n0n1_2) < 6'sh0 | $signed(counter_2) < 8'sh0 & $signed(n0n1_2) > 6'sh0
      ) begin // @[dvi_out.scala 73:87]
      dviData_2 <= _out_T_28; // @[dvi_out.scala 74:17]
    end else begin
      dviData_2 <= _out_T_29; // @[dvi_out.scala 85:17]
    end
    if (reset) begin // @[dvi_out.scala 34:28]
      videoRegs_0_pixelData <= 27'h0; // @[dvi_out.scala 34:28]
    end else begin
      videoRegs_0_pixelData <= videoRegs_1_pixelData; // @[dvi_out.scala 40:22]
    end
    videoRegs_0_hSync <= reset | videoRegs_1_hSync; // @[dvi_out.scala 34:28 dvi_out.scala 34:28 dvi_out.scala 40:22]
    videoRegs_0_vSync <= reset | videoRegs_1_vSync; // @[dvi_out.scala 34:28 dvi_out.scala 34:28 dvi_out.scala 40:22]
    if (reset) begin // @[dvi_out.scala 34:28]
      videoRegs_0_dataEnable <= 1'h0; // @[dvi_out.scala 34:28]
    end else begin
      videoRegs_0_dataEnable <= videoRegs_1_dataEnable; // @[dvi_out.scala 40:22]
    end
    if (reset) begin // @[dvi_out.scala 34:28]
      videoRegs_1_pixelData <= 27'h0; // @[dvi_out.scala 34:28]
    end else begin
      videoRegs_1_pixelData <= videoRegs_2_pixelData; // @[dvi_out.scala 40:22]
    end
    videoRegs_1_hSync <= reset | videoRegs_2_hSync; // @[dvi_out.scala 34:28 dvi_out.scala 34:28 dvi_out.scala 40:22]
    videoRegs_1_vSync <= reset | videoRegs_2_vSync; // @[dvi_out.scala 34:28 dvi_out.scala 34:28 dvi_out.scala 40:22]
    if (reset) begin // @[dvi_out.scala 34:28]
      videoRegs_1_dataEnable <= 1'h0; // @[dvi_out.scala 34:28]
    end else begin
      videoRegs_1_dataEnable <= videoRegs_2_dataEnable; // @[dvi_out.scala 40:22]
    end
    if (reset) begin // @[dvi_out.scala 34:28]
      videoRegs_2_pixelData <= 27'h0; // @[dvi_out.scala 34:28]
    end else begin
      videoRegs_2_pixelData <= _videoRegs_2_pixelData_T_3; // @[dvi_out.scala 38:43]
    end
    videoRegs_2_hSync <= reset | io_video_hSync; // @[dvi_out.scala 34:28 dvi_out.scala 34:28 dvi_out.scala 36:39]
    videoRegs_2_vSync <= reset | io_video_vSync; // @[dvi_out.scala 34:28 dvi_out.scala 34:28 dvi_out.scala 37:39]
    if (reset) begin // @[dvi_out.scala 34:28]
      videoRegs_2_dataEnable <= 1'h0; // @[dvi_out.scala 34:28]
    end else begin
      videoRegs_2_dataEnable <= io_video_dataEnable; // @[dvi_out.scala 35:44]
    end
    if (reset) begin // @[dvi_out.scala 110:26]
      counter_0 <= 8'sh0; // @[dvi_out.scala 110:26]
    end else if (~videoRegs_0_dataEnable) begin // @[dvi_out.scala 111:29]
      counter_0 <= 8'sh0; // @[dvi_out.scala 116:25]
    end else if ($signed(counter_0) == 8'sh0 | $signed(n0n1) == 6'sh0) begin // @[dvi_out.scala 62:47]
      if (out_lo[8]) begin // @[dvi_out.scala 68:27]
        counter_0 <= _newCounter_T_2; // @[dvi_out.scala 69:28]
      end else begin
        counter_0 <= _newCounter_T_5; // @[dvi_out.scala 71:28]
      end
    end else if ($signed(counter_0) > 8'sh0 & $signed(n0n1) < 6'sh0 | $signed(counter_0) < 8'sh0 & $signed(n0n1) > 6'sh0
      ) begin // @[dvi_out.scala 73:87]
      counter_0 <= _GEN_1;
    end else begin
      counter_0 <= _GEN_2;
    end
    if (reset) begin // @[dvi_out.scala 110:26]
      counter_1 <= 8'sh0; // @[dvi_out.scala 110:26]
    end else if (~videoRegs_0_dataEnable) begin // @[dvi_out.scala 111:29]
      counter_1 <= 8'sh0; // @[dvi_out.scala 116:25]
    end else if ($signed(counter_1) == 8'sh0 | $signed(n0n1_1) == 6'sh0) begin // @[dvi_out.scala 62:47]
      if (out_lo_4[8]) begin // @[dvi_out.scala 68:27]
        counter_1 <= _newCounter_T_26; // @[dvi_out.scala 69:28]
      end else begin
        counter_1 <= _newCounter_T_29; // @[dvi_out.scala 71:28]
      end
    end else if ($signed(counter_1) > 8'sh0 & $signed(n0n1_1) < 6'sh0 | $signed(counter_1) < 8'sh0 & $signed(n0n1_1) > 6'sh0
      ) begin // @[dvi_out.scala 73:87]
      counter_1 <= _GEN_8;
    end else begin
      counter_1 <= _GEN_9;
    end
    if (reset) begin // @[dvi_out.scala 110:26]
      counter_2 <= 8'sh0; // @[dvi_out.scala 110:26]
    end else if (~videoRegs_0_dataEnable) begin // @[dvi_out.scala 111:29]
      counter_2 <= 8'sh0; // @[dvi_out.scala 116:25]
    end else if ($signed(counter_2) == 8'sh0 | $signed(n0n1_2) == 6'sh0) begin // @[dvi_out.scala 62:47]
      if (out_lo_8[8]) begin // @[dvi_out.scala 68:27]
        counter_2 <= _newCounter_T_50; // @[dvi_out.scala 69:28]
      end else begin
        counter_2 <= _newCounter_T_53; // @[dvi_out.scala 71:28]
      end
    end else if ($signed(counter_2) > 8'sh0 & $signed(n0n1_2) < 6'sh0 | $signed(counter_2) < 8'sh0 & $signed(n0n1_2) > 6'sh0
      ) begin // @[dvi_out.scala 73:87]
      counter_2 <= _GEN_15;
    end else begin
      counter_2 <= _GEN_16;
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
  dviData_0 = _RAND_0[9:0];
  _RAND_1 = {1{`RANDOM}};
  dviData_1 = _RAND_1[9:0];
  _RAND_2 = {1{`RANDOM}};
  dviData_2 = _RAND_2[9:0];
  _RAND_3 = {1{`RANDOM}};
  videoRegs_0_pixelData = _RAND_3[26:0];
  _RAND_4 = {1{`RANDOM}};
  videoRegs_0_hSync = _RAND_4[0:0];
  _RAND_5 = {1{`RANDOM}};
  videoRegs_0_vSync = _RAND_5[0:0];
  _RAND_6 = {1{`RANDOM}};
  videoRegs_0_dataEnable = _RAND_6[0:0];
  _RAND_7 = {1{`RANDOM}};
  videoRegs_1_pixelData = _RAND_7[26:0];
  _RAND_8 = {1{`RANDOM}};
  videoRegs_1_hSync = _RAND_8[0:0];
  _RAND_9 = {1{`RANDOM}};
  videoRegs_1_vSync = _RAND_9[0:0];
  _RAND_10 = {1{`RANDOM}};
  videoRegs_1_dataEnable = _RAND_10[0:0];
  _RAND_11 = {1{`RANDOM}};
  videoRegs_2_pixelData = _RAND_11[26:0];
  _RAND_12 = {1{`RANDOM}};
  videoRegs_2_hSync = _RAND_12[0:0];
  _RAND_13 = {1{`RANDOM}};
  videoRegs_2_vSync = _RAND_13[0:0];
  _RAND_14 = {1{`RANDOM}};
  videoRegs_2_dataEnable = _RAND_14[0:0];
  _RAND_15 = {1{`RANDOM}};
  counter_0 = _RAND_15[7:0];
  _RAND_16 = {1{`RANDOM}};
  counter_1 = _RAND_16[7:0];
  _RAND_17 = {1{`RANDOM}};
  counter_2 = _RAND_17[7:0];
`endif // RANDOMIZE_REG_INIT
  `endif // RANDOMIZE
end // initial
`ifdef FIRRTL_AFTER_INITIAL
`FIRRTL_AFTER_INITIAL
`endif
`endif // SYNTHESIS
endmodule
