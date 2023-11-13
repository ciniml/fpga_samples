`default_nettype none
`timescale 1ns/1ps

module test_moving_average ();

// FIFOの入出力データ型
typedef logic [15:0] data_t;

// テスト対象の信号
logic   clock;      // クロック入力
logic   reset;      // Active Highの同期リセット入力
logic   in_valid;   // 入力VALID
logic   in_ready;   // 入力READY
data_t  in_data;    // 入力データ
logic   out_valid;  // 出力VALID
logic   out_ready;  // 出力READY
data_t  out_data;   // 出力データ

// クロック生成 (10ns周期)
initial begin
        clock = 0;
end 
always #(5) begin
    clock = ~clock;
end

// テスト対象のインスタンス化
moving_average dut (
  .clk  (clock),
  .reset(reset),
  .moving_average__input_consumer      (in_data),
  .moving_average__input_consumer_vld  (in_valid),
  .moving_average__output_producer_rdy (out_ready),
  .moving_average__output_producer     (out_data),
  .moving_average__output_producer_vld (out_valid),
  .moving_average__input_consumer_rdy  (in_ready)
);

/**
 * @summary テスト対象に指定したデータを入力する。
 * @param[in] data 入力するデータ
 * @param[in] valid_deassert_factor VALIDをデアサートする確率。intの範囲 (0~2^32-1) 大きいほどデアサートしやすくなる。
 **/
task automatic put_input_data(input data_t data, input int valid_deassert_factor);
    in_data <= data;
    in_valid <= 0;
    while($urandom() <= valid_deassert_factor) @(posedge clock);
    in_valid <= 1;
    do @(posedge clock); while(in_ready == 0);
    in_valid <= 0;
endtask

/**
 * @summary テスト対象の出力データを受け取る。
 * @param[out] data テスト対象から出力されたデータ
 * @param[in] ready_deassert_factor READYをデアサートする確率。intの範囲 (0~2^32-1) 大きいほどデアサートしやすくなる。
 **/
task automatic get_output_data(output data_t data, input int ready_deassert_factor);
    bit ready_value;
    do begin
        ready_value = $urandom() >= ready_deassert_factor;
        out_ready <= ready_value;
        @(posedge clock);
    end while( !ready_value );
    while(out_valid == 0) @(posedge clock);
    data = out_data;
    out_ready <= ready_value;
endtask

initial begin
    $dumpfile("test_moving_average.vcd"); // VCDファイルを出力する
    $dumpvars(0);                         // 全変数をVCDに出力する
    
    // テスト対象の入力信号を初期化
    in_valid <= 0;
    in_data <= 0;
    out_ready <= 0;

    // リセットをアサートして戻す
    reset <= 1;
    repeat(2) @(posedge clock);
    reset <= 0;
    repeat(2) @(posedge clock);

    fork
        fork
            begin
                // 0~255までの値をテスト対象に入力
                for(int i = 0; i < 255; i++) begin
                    put_input_data(i[$bits(data_t)-1:0], 32'ha0000000);
                end
            end
            begin
                // 256回テスト対象からデータを受け取る
                for(int i = 0; i < 255; i++) begin
                    data_t actual_data;
                    get_output_data(actual_data, 32'ha0000000);
                    // 期待値チェック
                    if( actual_data !== i[$bits(data_t)-1:0] ) $error("#%02d data mismatch. expected: %02x, actual: %02x", i, i, actual_data);
                end
            end
        join
        begin
            // タイムアウト検出。2560サイクル以内でテストが完了することを期待する。
            static int limit = 256*10;
            for(int cycles = 0; cycles < limit; cycles++ ) @(posedge clock);
            $error("Error: simulation timed out after %d cycles.", limit);
        end
    join_any
    disable fork;
    $finish;
end

endmodule

`default_nettype wire