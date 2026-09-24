# rtl/trace — EasyCDR トレースリンクの Veryl 実装

`eda/easycdr_trace` の非トップレベル RTL を Veryl に移していくプロジェクト
(計画と各モジュールの見積りは `eda/easycdr_trace/doc/veryl_migration.md`)。
流儀は `rtl/manchester` と同じ: `clock_type = posedge`、`reset_type = sync_high`、
`omit_project_prefix`。ただし既存の `top.v` / E2E テストと配線を変えないため、
ポートごとに `reset_async_low` などを明示して従来のリセット極性を保つ。

| モジュール | 生成 SV | 内容 |
|---|---|---|
| `easycdr_trace_tx_core` (`tx_link_core.veryl`) | `tx_link_core.sv` | K28.5 コンマ挿入 (FRAME_LEN 語毎)、K28.3 充填、8b10b。エンコーダは `$sv::displayport_encoder_8b10b` (rtl/displayport) |
| `trace_link_tx` | `trace_link_tx.sv` | レコード FIFO → `[K28.1][ts][data]` / `[K28.7][ts]` (tick) / K28.2 溢れ / K28.4 デスクリプタ / K28.6 信号マップ のバイト直列化 |
| `trace_frontend` | `trace_frontend.sv` | サンプルクロック側: 同期化、変化検出 + 無視マスク、タイムスタンプ、周期サンプル、TX トリガ、tick |
| `trace_sync_bit` / `trace_sync_pulse` / `trace_reset_sync` / `trace_cdc_bus` (`trace_cdc.veryl`) | `trace_cdc.sv` | CDC ヘルパ (同期化列、トグル式パルス転送、非同期アサート同期解除リセット、req/ack 付き準静的バス) |
| `trace_afifo` | `trace_afifo.sv` | グレイポインタ非同期 FIFO、同期読出プリフェッチ (FWFT)。`RAM_STYLE` "distributed"/"block" は `(* syn_ramstyle *)` 属性で切替 |
| `easycdr_trace_tx` | `easycdr_trace_tx.sv` | ラッパ: 制御の clk→sclk 転送 (cdc_bus + pulse)、frontend → afifo → link_tx、溢れ/デスクリプタ要求のハンドシェイク |
| `trace_rx_decoder` | `trace_rx_decoder.sv` | 受信側: {K, byte} 語列 → レコード (幅はデスクリプタから実行時決定)、デスクリプタ v1/v2 ラッチ、K28.6 信号マップ出力 |
| `trace_link_diag` | `trace_link_diag.sv` | 受信側: pclk のイベント計数 (コンマ/レコード/誤り/溢れ/デスクリプタ/データ) を clk_sys からスナップショット、タイムアウト付き |
| `trace_sym_inject` | `trace_sym_inject.sv` | 自己試験 TX 用: ホストが書いた生シンボル列で送信ストリームを置換 (1 回 / ループ) |
| `trace_capture` | `trace_capture.sv` | 受信側: 2^ADDR_BITS 語のリングバッファ (pclk) + トリガ/POST、ホストコマンド FSM (clk_sys: S T A D ? X F Z R J N L P) |

`eda/easycdr_trace` の旧 `src/common/*.v` (送信側) と `src/tangprimer25k/trace_*.v` (受信側) は全部ここに移した (top.v だけ Verilog)。生成された `.sv` は追跡しない (`.gitignore`)。`eda/easycdr_trace/Makefile` と `test/Makefile` が
`veryl build` を先に走らせる。

```
veryl build           # *.sv を生成
veryl test            # Verilator。本体は test/*_body.sv (RUN=0 既定、#[test] から RUN=1 で実体化)
```

テスト: `tx_link_core_f16` / `tx_link_core_f8` — 復号器 (`displayport_decoder_8b10b`) で戻し、
コンマの位置と `o_ready`、投入したバイトの順序、充填 K28.3 を確認する。
