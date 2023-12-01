module moving_average(
  input wire clk,
  input wire reset,
  input wire [15:0] moving_average__input_consumer,
  input wire moving_average__input_consumer_vld,
  input wire moving_average__output_producer_rdy,
  output wire [15:0] moving_average__output_producer,
  output wire moving_average__output_producer_vld,
  output wire moving_average__input_consumer_rdy
);
  wire [15:0] ____state_0_init[0:7];
  assign ____state_0_init[0] = 16'h0000;
  assign ____state_0_init[1] = 16'h0000;
  assign ____state_0_init[2] = 16'h0000;
  assign ____state_0_init[3] = 16'h0000;
  assign ____state_0_init[4] = 16'h0000;
  assign ____state_0_init[5] = 16'h0000;
  assign ____state_0_init[6] = 16'h0000;
  assign ____state_0_init[7] = 16'h0000;
  reg [15:0] ____state_0[0:7];
  reg [2:0] ____state_2;
  reg ____state_3;
  reg [18:0] ____state_1;
  reg [15:0] __moving_average__input_consumer_reg;
  reg __moving_average__input_consumer_valid_reg;
  reg [15:0] __moving_average__output_producer_reg;
  reg __moving_average__output_producer_valid_reg;
  wire p0_all_active_states_valid;
  wire moving_average__output_producer_valid_inv;
  wire __moving_average__output_producer_vld_buf;
  wire moving_average__output_producer_valid_load_en;
  wire moving_average__output_producer_load_en;
  wire p0_all_active_states_ready;
  wire [15:0] old;
  wire p0_stage_done;
  wire pipeline_enable;
  wire moving_average__input_consumer_valid_inv;
  wire [18:0] sub_83;
  wire moving_average__input_consumer_valid_load_en;
  wire [18:0] accumulator;
  wire [15:0] buffer[0:7];
  wire [2:0] index;
  wire filled;
  wire moving_average__input_consumer_load_en;
  wire [15:0] __moving_average__output_producer_buf;
  assign p0_all_active_states_valid = 1'h1;
  assign moving_average__output_producer_valid_inv = ~__moving_average__output_producer_valid_reg;
  assign __moving_average__output_producer_vld_buf = __moving_average__input_consumer_valid_reg & p0_all_active_states_valid & 1'h1;
  assign moving_average__output_producer_valid_load_en = moving_average__output_producer_rdy | moving_average__output_producer_valid_inv;
  assign moving_average__output_producer_load_en = __moving_average__output_producer_vld_buf & moving_average__output_producer_valid_load_en;
  assign p0_all_active_states_ready = 1'h1;
  assign old = ____state_0[____state_2] & {16{____state_3}};
  assign p0_stage_done = p0_all_active_states_valid & __moving_average__input_consumer_valid_reg & moving_average__output_producer_load_en & p0_all_active_states_ready;
  assign pipeline_enable = p0_stage_done & p0_stage_done;
  assign moving_average__input_consumer_valid_inv = ~__moving_average__input_consumer_valid_reg;
  assign sub_83 = ____state_1 - {{3{old[15]}}, old};
  assign moving_average__input_consumer_valid_load_en = pipeline_enable | moving_average__input_consumer_valid_inv;
  assign accumulator = sub_83 + {{3{__moving_average__input_consumer_reg[15]}}, __moving_average__input_consumer_reg};
  assign buffer[0] = ____state_2 == 3'h0 ? __moving_average__input_consumer_reg : ____state_0[0];
  assign buffer[1] = ____state_2 == 3'h1 ? __moving_average__input_consumer_reg : ____state_0[1];
  assign buffer[2] = ____state_2 == 3'h2 ? __moving_average__input_consumer_reg : ____state_0[2];
  assign buffer[3] = ____state_2 == 3'h3 ? __moving_average__input_consumer_reg : ____state_0[3];
  assign buffer[4] = ____state_2 == 3'h4 ? __moving_average__input_consumer_reg : ____state_0[4];
  assign buffer[5] = ____state_2 == 3'h5 ? __moving_average__input_consumer_reg : ____state_0[5];
  assign buffer[6] = ____state_2 == 3'h6 ? __moving_average__input_consumer_reg : ____state_0[6];
  assign buffer[7] = ____state_2 == 3'h7 ? __moving_average__input_consumer_reg : ____state_0[7];
  assign index = ____state_2 + 3'h1;
  assign filled = ____state_3 | ____state_2 == 3'h7;
  assign moving_average__input_consumer_load_en = moving_average__input_consumer_vld & moving_average__input_consumer_valid_load_en;
  assign __moving_average__output_producer_buf = accumulator[18:3];
  always @ (posedge clk) begin
    if (reset) begin
      ____state_0[0] <= ____state_0_init[0];
      ____state_0[1] <= ____state_0_init[1];
      ____state_0[2] <= ____state_0_init[2];
      ____state_0[3] <= ____state_0_init[3];
      ____state_0[4] <= ____state_0_init[4];
      ____state_0[5] <= ____state_0_init[5];
      ____state_0[6] <= ____state_0_init[6];
      ____state_0[7] <= ____state_0_init[7];
      ____state_2 <= 3'h0;
      ____state_3 <= 1'h0;
      ____state_1 <= 19'h0_0000;
      __moving_average__input_consumer_reg <= 16'h0000;
      __moving_average__input_consumer_valid_reg <= 1'h0;
      __moving_average__output_producer_reg <= 16'h0000;
      __moving_average__output_producer_valid_reg <= 1'h0;
    end else begin
      ____state_0[0] <= pipeline_enable ? buffer[0] : ____state_0[0];
      ____state_0[1] <= pipeline_enable ? buffer[1] : ____state_0[1];
      ____state_0[2] <= pipeline_enable ? buffer[2] : ____state_0[2];
      ____state_0[3] <= pipeline_enable ? buffer[3] : ____state_0[3];
      ____state_0[4] <= pipeline_enable ? buffer[4] : ____state_0[4];
      ____state_0[5] <= pipeline_enable ? buffer[5] : ____state_0[5];
      ____state_0[6] <= pipeline_enable ? buffer[6] : ____state_0[6];
      ____state_0[7] <= pipeline_enable ? buffer[7] : ____state_0[7];
      ____state_2 <= pipeline_enable ? index : ____state_2;
      ____state_3 <= pipeline_enable ? filled : ____state_3;
      ____state_1 <= pipeline_enable ? accumulator : ____state_1;
      __moving_average__input_consumer_reg <= moving_average__input_consumer_load_en ? moving_average__input_consumer : __moving_average__input_consumer_reg;
      __moving_average__input_consumer_valid_reg <= moving_average__input_consumer_valid_load_en ? moving_average__input_consumer_vld : __moving_average__input_consumer_valid_reg;
      __moving_average__output_producer_reg <= moving_average__output_producer_load_en ? __moving_average__output_producer_buf : __moving_average__output_producer_reg;
      __moving_average__output_producer_valid_reg <= moving_average__output_producer_valid_load_en ? __moving_average__output_producer_vld_buf : __moving_average__output_producer_valid_reg;
    end
  end
  assign moving_average__output_producer = __moving_average__output_producer_reg;
  assign moving_average__output_producer_vld = __moving_average__output_producer_valid_reg;
  assign moving_average__input_consumer_rdy = moving_average__input_consumer_load_en;
endmodule
