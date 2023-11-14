module mixer(
  input wire clk,
  input wire reset,
  input wire [63:0] mixer__inputs_ch,
  input wire mixer__inputs_ch_vld,
  input wire [63:0] mixer__volumes_ch,
  input wire mixer__volumes_ch_vld,
  input wire mixer__output_ch_rdy,
  output wire [31:0] mixer__output_ch,
  output wire mixer__output_ch_vld,
  output wire mixer__inputs_ch_rdy,
  output wire mixer__volumes_ch_rdy
);
  // lint_off MULTIPLY
  function automatic [31:0] umul32b_32b_x_16b (input reg [31:0] lhs, input reg [15:0] rhs);
    begin
      umul32b_32b_x_16b = lhs * rhs;
    end
  endfunction
  // lint_on MULTIPLY
  wire [15:0] __mixer__inputs_ch_reg_init[0:1][0:1];
  assign __mixer__inputs_ch_reg_init[0][0] = 16'h0000;
  assign __mixer__inputs_ch_reg_init[0][1] = 16'h0000;
  assign __mixer__inputs_ch_reg_init[1][0] = 16'h0000;
  assign __mixer__inputs_ch_reg_init[1][1] = 16'h0000;
  wire [15:0] __mixer__volumes_ch_reg_init[0:1][0:1];
  assign __mixer__volumes_ch_reg_init[0][0] = 16'h0000;
  assign __mixer__volumes_ch_reg_init[0][1] = 16'h0000;
  assign __mixer__volumes_ch_reg_init[1][0] = 16'h0000;
  assign __mixer__volumes_ch_reg_init[1][1] = 16'h0000;
  wire [15:0] __mixer__output_ch_reg_init[0:1];
  assign __mixer__output_ch_reg_init[0] = 16'h0000;
  assign __mixer__output_ch_reg_init[1] = 16'h0000;
  wire [15:0] mixer__inputs_ch_unflattened[0:1][0:1];
  assign mixer__inputs_ch_unflattened[0][0] = mixer__inputs_ch[15:0];
  assign mixer__inputs_ch_unflattened[0][1] = mixer__inputs_ch[31:16];
  assign mixer__inputs_ch_unflattened[1][0] = mixer__inputs_ch[47:32];
  assign mixer__inputs_ch_unflattened[1][1] = mixer__inputs_ch[63:48];
  wire [15:0] mixer__volumes_ch_unflattened[0:1][0:1];
  assign mixer__volumes_ch_unflattened[0][0] = mixer__volumes_ch[15:0];
  assign mixer__volumes_ch_unflattened[0][1] = mixer__volumes_ch[31:16];
  assign mixer__volumes_ch_unflattened[1][0] = mixer__volumes_ch[47:32];
  assign mixer__volumes_ch_unflattened[1][1] = mixer__volumes_ch[63:48];
  reg [15:0] __mixer__inputs_ch_reg[0:1][0:1];
  reg __mixer__inputs_ch_valid_reg;
  reg [15:0] __mixer__volumes_ch_reg[0:1][0:1];
  reg __mixer__volumes_ch_valid_reg;
  reg [15:0] __mixer__output_ch_reg[0:1];
  reg __mixer__output_ch_valid_reg;
  wire p0_all_active_inputs_valid;
  wire p0_all_active_states_valid;
  wire mixer__output_ch_valid_inv;
  wire [31:0] umul_383;
  wire [31:0] umul_384;
  wire [31:0] umul_385;
  wire [31:0] umul_386;
  wire __mixer__output_ch_vld_buf;
  wire mixer__output_ch_valid_load_en;
  wire [31:0] acc;
  wire [31:0] acc__1;
  wire mixer__output_ch_load_en;
  wire p0_all_active_states_ready;
  wire p0_stage_done;
  wire pipeline_enable;
  wire mixer__inputs_ch_valid_inv;
  wire mixer__volumes_ch_valid_inv;
  wire [31:0] add_395;
  wire [31:0] add_396;
  wire mixer__inputs_ch_valid_load_en;
  wire mixer__volumes_ch_valid_load_en;
  wire mixer__inputs_ch_load_en;
  wire mixer__volumes_ch_load_en;
  wire [15:0] outputs[0:1];
  assign p0_all_active_inputs_valid = __mixer__inputs_ch_valid_reg & __mixer__volumes_ch_valid_reg;
  assign p0_all_active_states_valid = 1'h1;
  assign mixer__output_ch_valid_inv = ~__mixer__output_ch_valid_reg;
  assign umul_383 = umul32b_32b_x_16b({{16{__mixer__inputs_ch_reg[1'h0][1'h0][15]}}, __mixer__inputs_ch_reg[1'h0][1'h0]}, __mixer__volumes_ch_reg[1'h0][1'h0]);
  assign umul_384 = umul32b_32b_x_16b({{16{__mixer__inputs_ch_reg[1'h1][1'h0][15]}}, __mixer__inputs_ch_reg[1'h1][1'h0]}, __mixer__volumes_ch_reg[1'h1][1'h0]);
  assign umul_385 = umul32b_32b_x_16b({{16{__mixer__inputs_ch_reg[1'h0][1'h1][15]}}, __mixer__inputs_ch_reg[1'h0][1'h1]}, __mixer__volumes_ch_reg[1'h0][1'h1]);
  assign umul_386 = umul32b_32b_x_16b({{16{__mixer__inputs_ch_reg[1'h1][1'h1][15]}}, __mixer__inputs_ch_reg[1'h1][1'h1]}, __mixer__volumes_ch_reg[1'h1][1'h1]);
  assign __mixer__output_ch_vld_buf = p0_all_active_inputs_valid & p0_all_active_states_valid & 1'h1;
  assign mixer__output_ch_valid_load_en = mixer__output_ch_rdy | mixer__output_ch_valid_inv;
  assign acc = umul_383 + umul_384;
  assign acc__1 = umul_385 + umul_386;
  assign mixer__output_ch_load_en = __mixer__output_ch_vld_buf & mixer__output_ch_valid_load_en;
  assign p0_all_active_states_ready = 1'h1;
  assign p0_stage_done = p0_all_active_states_valid & p0_all_active_inputs_valid & mixer__output_ch_load_en & p0_all_active_states_ready;
  assign pipeline_enable = p0_stage_done & p0_stage_done;
  assign mixer__inputs_ch_valid_inv = ~__mixer__inputs_ch_valid_reg;
  assign mixer__volumes_ch_valid_inv = ~__mixer__volumes_ch_valid_reg;
  assign add_395 = acc + {31'h0000_0000, acc[31]};
  assign add_396 = acc__1 + {31'h0000_0000, acc__1[31]};
  assign mixer__inputs_ch_valid_load_en = pipeline_enable | mixer__inputs_ch_valid_inv;
  assign mixer__volumes_ch_valid_load_en = pipeline_enable | mixer__volumes_ch_valid_inv;
  assign mixer__inputs_ch_load_en = mixer__inputs_ch_vld & mixer__inputs_ch_valid_load_en;
  assign mixer__volumes_ch_load_en = mixer__volumes_ch_vld & mixer__volumes_ch_valid_load_en;
  assign outputs[0] = add_395[31:16];
  assign outputs[1] = add_396[31:16];
  always @ (posedge clk) begin
    if (reset) begin
      __mixer__inputs_ch_reg[0][0] <= __mixer__inputs_ch_reg_init[0][0];
      __mixer__inputs_ch_reg[0][1] <= __mixer__inputs_ch_reg_init[0][1];
      __mixer__inputs_ch_reg[1][0] <= __mixer__inputs_ch_reg_init[1][0];
      __mixer__inputs_ch_reg[1][1] <= __mixer__inputs_ch_reg_init[1][1];
      __mixer__inputs_ch_valid_reg <= 1'h0;
      __mixer__volumes_ch_reg[0][0] <= __mixer__volumes_ch_reg_init[0][0];
      __mixer__volumes_ch_reg[0][1] <= __mixer__volumes_ch_reg_init[0][1];
      __mixer__volumes_ch_reg[1][0] <= __mixer__volumes_ch_reg_init[1][0];
      __mixer__volumes_ch_reg[1][1] <= __mixer__volumes_ch_reg_init[1][1];
      __mixer__volumes_ch_valid_reg <= 1'h0;
      __mixer__output_ch_reg[0] <= __mixer__output_ch_reg_init[0];
      __mixer__output_ch_reg[1] <= __mixer__output_ch_reg_init[1];
      __mixer__output_ch_valid_reg <= 1'h0;
    end else begin
      __mixer__inputs_ch_reg[0][0] <= mixer__inputs_ch_load_en ? mixer__inputs_ch_unflattened[0][0] : __mixer__inputs_ch_reg[0][0];
      __mixer__inputs_ch_reg[0][1] <= mixer__inputs_ch_load_en ? mixer__inputs_ch_unflattened[0][1] : __mixer__inputs_ch_reg[0][1];
      __mixer__inputs_ch_reg[1][0] <= mixer__inputs_ch_load_en ? mixer__inputs_ch_unflattened[1][0] : __mixer__inputs_ch_reg[1][0];
      __mixer__inputs_ch_reg[1][1] <= mixer__inputs_ch_load_en ? mixer__inputs_ch_unflattened[1][1] : __mixer__inputs_ch_reg[1][1];
      __mixer__inputs_ch_valid_reg <= mixer__inputs_ch_valid_load_en ? mixer__inputs_ch_vld : __mixer__inputs_ch_valid_reg;
      __mixer__volumes_ch_reg[0][0] <= mixer__volumes_ch_load_en ? mixer__volumes_ch_unflattened[0][0] : __mixer__volumes_ch_reg[0][0];
      __mixer__volumes_ch_reg[0][1] <= mixer__volumes_ch_load_en ? mixer__volumes_ch_unflattened[0][1] : __mixer__volumes_ch_reg[0][1];
      __mixer__volumes_ch_reg[1][0] <= mixer__volumes_ch_load_en ? mixer__volumes_ch_unflattened[1][0] : __mixer__volumes_ch_reg[1][0];
      __mixer__volumes_ch_reg[1][1] <= mixer__volumes_ch_load_en ? mixer__volumes_ch_unflattened[1][1] : __mixer__volumes_ch_reg[1][1];
      __mixer__volumes_ch_valid_reg <= mixer__volumes_ch_valid_load_en ? mixer__volumes_ch_vld : __mixer__volumes_ch_valid_reg;
      __mixer__output_ch_reg[0] <= mixer__output_ch_load_en ? outputs[0] : __mixer__output_ch_reg[0];
      __mixer__output_ch_reg[1] <= mixer__output_ch_load_en ? outputs[1] : __mixer__output_ch_reg[1];
      __mixer__output_ch_valid_reg <= mixer__output_ch_valid_load_en ? __mixer__output_ch_vld_buf : __mixer__output_ch_valid_reg;
    end
  end
  assign mixer__output_ch = {__mixer__output_ch_reg[1], __mixer__output_ch_reg[0]};
  assign mixer__output_ch_vld = __mixer__output_ch_valid_reg;
  assign mixer__inputs_ch_rdy = mixer__inputs_ch_load_en;
  assign mixer__volumes_ch_rdy = mixer__volumes_ch_load_en;
endmodule
