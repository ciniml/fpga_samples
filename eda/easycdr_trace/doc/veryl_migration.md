# トレース RTL の Veryl 化 検討メモ（2026-09-17）

対象: トップレベル（`eda/*/src/*/top.v`）以外の、`eda/easycdr_trace/src/common/*.v` と
`src/tangprimer25k/trace_*.v`。**2026-09-25 に全段階完了、すべて `rtl/trace/*.veryl` に移行済み**（以下は当時の見積りと結果）。8b10b エンコーダ/デコーダ（`rtl/displayport`）はすでに Veryl、
`rtl/uart` は多数のプロジェクトで共有される手書き SV（iverilog テスト付き）なので対象外。
参照する Veryl プロジェクトの流儀は `rtl/manchester`（`clock_type = posedge`、`reset_type = sync_high`、
`omit_project_prefix`、テスト本体は `test/*_body.sv` を `RUN` でゲート）。

## 1. モジュール別の見積り

| モジュール | 行 | Veryl で工夫が要る点 | 工数 | 順 |
|---|---|---|---|---|
| tx_link_core.v | 66 | 非同期 L リセット、displayport エンコーダへの依存（path dependency か `$sv::`） | 1 h | 1 |
| trace_link_tx.v | 148 | `cur[sb_idx*8 +: 8]` の実行時パート選択 → バイト配列 `logic<N, 8>`、`always @(*) case` → `always_comb`、`WIDTH[7:0]` → `as u8`、`DESC_INTERVAL-1` 比較のキャスト | 2.5 h | 2 |
| trace_cdc.v（4 モジュール） | 125 | 全部 2 クロック → `'s`/`'d` 注釈と `unsafe(cdc)`、`trace_reset_sync` の `negedge arstn` は `reset_async_low` ポート型、generate-for の chunk 定数 | 3 h | 3 |
| trace_afifo.v | 103 | 2 クロック gray ポインタ、文字列パラメータ `RAM_STYLE` で 2 重宣言 → `bit` パラメータ + `#[sv("syn_ramstyle=...")]`。Gowin が `(* *)` 形式を認識するか要確認（GW5A は分散 RAM 無し） | 2.5 h | 4 |
| trace_frontend.v | 176 | generate-if 3 つ（SYNC_STAGES / HAS_PERIODIC / HAS_TRIGGER）と分岐内の reg、`{WIDTH{1'b0}}` → `{1'b0 repeat WIDTH}`、`<=` 比較 → `<:` | 3 h | 5 |
| easycdr_trace_tx.v（ラッパ） | 172 | 2 クロック、派生リセット `rstn & srstn` → `let x: '_ reset`、下降パート選択 `[CFG_W-2 -: WIDTH]` → 定数 `[hi:lo]`、**非同期 L リセットのポートを top.v が使う**ので `reset_async_low` で極性維持 | 3 h | 6 |
| trace_rx_decoder.v | 122 | 単一クロックだが非同期 H リセット、`ts_acc[idx*8 +: 8] <=` → バイト配列、連結 LHS の分割 | 2 h | 7 |
| trace_link_diag.v | 103 | 2 クロック（トグルハンドシェイク + タイムアウト）、`function` | 2 h | 8 |
| trace_sym_inject.v | 80 | 2 クロック、メモリの CDC（書込 clk_sys / 読出 txclk）→ 読出側を `unsafe(cdc)` | 1.5 h | 9 |
| trace_capture.v | 426 | 2 クロック、2^ADDR_BITS×12 のリング（BSRAM 推論 + メモリ CDC）、**文字リテラル `"S"` の case** → `const CMD_S: u8 = 8'h53`、3 段ネスト FSM、`trig_mask[arg_idx*8 +: 8]` → バイト配列、`post_count[ADDR_BITS:8]` の部分幅 | 6〜8 h | 10（最後） |

合計 27〜30 h + Veryl 側ユニットテスト 8 h 程度（uart を除く）。

共通の注意: 送信側は `posedge clk or negedge rstn`（非同期 L）、25K 受信側は `posedge rst`（非同期 H）で
統一されていない。プロジェクト既定の `sync_high` にすると全ポートの極性と同期性が変わり `top.v` と
`e2e_ctrl_tb.sv` の配線を直す必要があるので、**ポートごとに `reset_async_low` / `reset_async_high` を
明示**して現在のインターフェースを保つ（displayport の `reset_sync_low` と同じやり方）。

## 2. ビルドとテストの取り込み

- Veryl は `.veryl` の隣に `.sv` を生成する（`.gitignore` で `*.sv` を除外、`test/*.sv` は残す）。
  `eda/easycdr_trace/Makefile` の SRCS と `project.tcl` の `add_file` を `rtl/trace/*.sv` に向ける。
  `veryl build` を先に走らせる規則を Makefile に足す（現状 manchester は手動）。
- `test/Makefile`（Verilator `--binary --timing`、`-Wno-MULTITOP` 済み）は `.v` の代わりに `rtl/trace/<name>.sv`
  を列挙するだけ。モジュール名とポート名、リセット極性を保てば `e2e_ctrl_tb.sv` は無変更。
- Gowin は `sysv2017` で manchester の出力を受けているので、同じ扱いで通る。

## 3. Verilog のまま残すもの

- `top.v` 群（要件どおり。`ifdef` とデバイスプリミティブの塊）。
- ~~`trace_afifo.v`~~ 済: Veryl の `#[sv("syn_ramstyle = \"block_ram\"")]` は `(* syn_ramstyle = "block_ram" *)` になり、
  Gowin は認識する（Nano9K で RAM16SDP 9 個、25K で SDPB に推論、Verilog 版と同じ）。
- ~~`trace_reset_sync`~~ 済: `arstn: input reset_async_low` + `if_reset { r = 0 } else { r = {r[0], 1'b1} }` で同じ回路。
- `rtl/uart`: 共有資産で iverilog テストが壊れる（生成 SV の `input var logic`）。

## 4. 提案する配置と進め方

```
rtl/trace/            Veryl プロジェクト（rtl/manchester と同じ構成）
  Veryl.toml          name="trace"、posedge / sync_high、omit_project_prefix、[dependencies] displayport
  *.veryl             tx_link_core, trace_link_tx, trace_frontend, trace_cdc, trace_afifo, easycdr_trace_tx,
                      trace_rx_decoder, trace_link_diag, trace_sym_inject, trace_capture
  tb_*.veryl + test/*_body.sv   RUN ゲート、失敗は $fatal
```

各ステップで `veryl build` → `make -C eda/easycdr_trace/test test`（3 条件）→ Nano9K 合成 → LUT/FF/BSRAM を
現行と比較、してからコミットする。

1. **済 (2026-09-17)** `rtl/trace` を作り tx_link_core を移した。8b10b は `$sv::displayport_encoder_8b10b`
   で参照（displayport を path dependency にすると femtorv 等を含む大きなプロジェクトごと依存ビルドになるため）。
   リセットは `reset_async_low` ポートで従来の `negedge rstn` を維持。`veryl test`（`test/tx_link_core_body.sv`、
   FRAME_LEN 16/8: コンマ位置・o_ready・バイト順・充填）。`eda/easycdr_trace/Makefile` と `test/Makefile` に
   `veryl build` 規則を追加（生成 .sv は非追跡）。E2E 3 条件 PASS、Nano9K 合成は LUT/FF とも従来と同じ。
2. **済 (2026-09-25)** trace_link_tx（`cur: logic<REC_BYTES, 8>` で `cur[sb_idx]`、`WIDTH[7:0]` は param の
   ビット選択がそのまま通る、`TS_LAST as 8` で幅キャスト）、trace_frontend（`if COND :label { }` の generate-if、
   `logic<SYNC_STAGES, WIDTH>` のシフト列、`for i in 1..N`（型注釈不可））。E2E 3 条件 PASS、Nano9K 4 変種とも
   合成 OK で demo は LUT 988 / FF 778（Verilog 版と同一）。実機確認は 25K 未接続のため未実施。
3. **済 (2026-09-25)** trace_cdc + trace_afifo + ラッパ。送信側は全部 Veryl になり `src/common/` は削除。
   - 2 クロックモジュールはポートと変数に `'src`/`'dst`（`'s`/`'d` は識別子 s/d と衝突する）や `'w`/`'r`、
     ラッパは `'s`/`'l` のドメイン注釈を付け、消費側 always_ff を `unsafe (cdc) { }` で包む。ラッパの
     `rstn & srstn` は `unsafe (cdc) { assign arstn = (...) as reset_async_low; }`。
   - 下降パート選択 `[CFG_W-2 -: WIDTH]` は `const P_xx_HI/LO` を置いて `[HI:LO]` に。
   - クリーン合成（build/ 削除後）: Nano9K demo LUT 987 / FF 778 / RAM16 9（Verilog 版と同一）、w32 1006/899、
     pulse 450/307、742M5 964/778、25K 2943/2757/16 SDPB。全部 TNS 0。
   - **注意**: 段階 1〜2 の合成結果として書いた数値は、Makefile の `veryl build` 規則が include より前に
     あって default goal を奪い、ビットストリームが再生成されていなかった（古い成果物を読んでいた）。
     段階 1 で書き込んだ実機も Verilog 版のビットストリーム。Veryl 版の実機確認はこの段階でまとめて行う
     予定だったが、25K 未接続 + Nano9K の JTAG が開けず未実施。
4. **済 (2026-09-25)** 受信側 decoder → diag → sym_inject。`rst: input reset_async_high` で 25K 側の極性を維持。
   バイト単位の蓄積 `ts_acc[idx*8 +: 8]` は `logic<MAX_TB, 8>` の `ts_acc[idx]`、デスクリプタの連結 LHS は
   個別代入に分解。diag の `function` は Veryl の `function inc(...) -> logic<16>`。2 クロックは `'p`/`'h`、`'t`/`'h`。
   E2E 3 条件 PASS、25K クリーン合成 LUT 2958 / FF 2757 / SDPB 16、TNS 0。
5. **済 (2026-09-25)** trace_capture。文字リテラル `"S"` は `const CMD_S: logic<8> = 8'h53` 等、`trig_mask[arg_idx*8 +: 8]`
   は `logic<MAX_DB, 8>` の `trig_mask[arg_idx]`、リング/マップの RAM は pclk 書込 always_ff と clk_sys 読出 always_ff
   （`unsafe (cdc)`）に分離、トリガ比較 (pclk × clk_sys の準静的レジスタ) も `unsafe (cdc) { assign }`。
   E2E 3 条件 PASS、25K クリーン合成 LUT 2947 / FF 2759 / SDPB 16 (buffer / mapbuf とも BSRAM 抽出)、742M5 変種も TNS 0。
   **ここで top.v 以外は全部 Veryl。** 25K 実機は未確認。
6. afifo（同一クロック / 比率クロック）とトリガ FSM の `veryl test` を追加。

Veryl 0.20 の既知の罠（記憶メモより）: `param`/`const`、`if c ? a : b`、`>:`/`<:`、`{x repeat N}`、
キャストは名前付き定数へのみ、`for i in 0..N`、複数変数宣言不可、予約語 `clock/reset/edge/buf/step/signed`、
`initial` と `always_ff` の同一変数禁止、`embed` の匿名衝突、`unsafe(cdc)` は消費側 always_ff を包む、
`RUN` 既定 0 と `$fatal`。
