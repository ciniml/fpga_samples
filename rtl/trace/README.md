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

生成された `.sv` は追跡しない (`.gitignore`)。`eda/easycdr_trace/Makefile` と `test/Makefile` が
`veryl build` を先に走らせる。

```
veryl build           # *.sv を生成
veryl test            # Verilator。本体は test/*_body.sv (RUN=0 既定、#[test] から RUN=1 で実体化)
```

テスト: `tx_link_core_f16` / `tx_link_core_f8` — 復号器 (`displayport_decoder_8b10b`) で戻し、
コンマの位置と `o_ready`、投入したバイトの順序、充填 K28.3 を確認する。
