# DisplayPort 1.2 Source IP — Tang Primer 25K test pattern generator

## 概要

`rtl/displayport/` に実装した DisplayPort 1.2 Source IP を Tang Primer 25K
(Sipeed) と Pmod DisplayPort モジュールに統合し、内蔵テストパターン
ジェネレータの映像を AUX CH + メインリンクで出力するデザイン。

構成:

```
clock_27 ─┐
          │  ┌──────────────────────────────┐
          ├──► aux_ch_subsystem (FemtoRV32) │←─ AUX CH (TLVDS_IOBUF)
          │  │   ・DPCD / EDID 読出し       │←─ HPD
          │  │   ・リンクトレーニング SM    │
clock_dvi─┼──► main_link_tx                │
          │  │   scrambler → 8B/10B → ser  │→ ML lane 0 (TLVDS_OBUF)
          │  └──────────▲───────────────────┘
          │             │
          └──► test_pattern_generator (1280x720 7色バー)
                        │
               tpg_to_axis (DE-gated → AXI-Stream)
```

## 動作概要 (RBR 1.62 Gbps 対応)

* **シリアライザ**: Gowin OSER10 プリミティブを `oser10_lane.sv` でラップ。
  PCLK = 162 MHz バイトクロック、FCLK = 810 MHz、DDR で 1.62 Gbps を出力。
* **DP IP**: `dp_source_top` は `CONTINUOUS_BYTE_TICK = 1` で動作し、毎
  PCLK サイクルに 1 シンボル出力。エンコーダの 10-bit シンボルを
  `o_lane0_symbol` として OSER10 に直結。
* **クロック**: 50 MHz ボードクロック → `gowin_pll_27` で 27 MHz →
  `gowin_pll` で `clock_byte` (162 MHz) と `clock_serial` (810 MHz) を生成。

検証ポイント:

* AUX CH 電気特性 + DPCD/EDID 読出し
* リンクトレーニング (CR → EQ → IDLE)
* オシロで lane 0 が 1.62 Gbps DDR を出しているか
* 実 DP モニタが画を出すか

## 重要な手動作業

`gowin_pll` の IP ファイルは現状 旧 DVI 用の周波数で生成されています。
**Gowin IP Core Generator** で開いて以下の値に再構成してください:

* CLKOUT0 = **162 MHz** (clock_byte, OSER10 PCLK)
* CLKOUT1 = **810 MHz** (clock_serial, OSER10 FCLK)
* 入力 = 27 MHz (CLKIN_FREQUENCY = 27 MHz)
* CLKFB_SEL = INTERNAL

`gowin_pll_27` は 50 MHz → 27 MHz のままで OK。

## 既知の制限

* 1 lane only。マルチレーン化は OSER10 を 4 個並べる + DP IP のレーン
  分配対応が必要。
* 電圧スイング/プリエンファシスの動的制御は未実装 (Gowin LVDS の DRIVE
  値で固定値のみ)。
* HBR/HBR2 (2.7/5.4 Gbps) は OSER10 単体では届かない (~1.25 Gbps 帯が
  限界)。GW5AT-25 のシリアル GTP/GTH ブロックが必要。

## 合成の準備

### Tang Primer 25K向け

Tang Primer 25K向けのデザインを試すには、Tang Primer 25K本体以外にSipeedのPmod DisplayPort モジュールが必要となる。Pmod DisplayPort モジュールは DE0 互換コネクタを手前に持ってきた状態 (Pmodコネクタを奥側にした状態) で一番右側のコネクタ (F5, G5のピンが含まれるコネクタ) に接続する。

`src/tangprimer25k/ip` 以下にある、 `gowin_pll` と `gowin_pll_27` を復元する。
IPの復元はGOWIN EDAのGUI上の `Tools -> IP Core Generator` メニューから IP Core Generatorを開き、画面上部のボタンを押して各IPのディレクトリ下にある *.ipc ファイルを選択する。
その後、値を変更せずにOKを押すと、対象のIPのHDLファイルが生成される。

### ファームウェアのビルド

DisplayPort IP の AUX CH に組み込まれている FemtoRV32 用ファーム
(リンクトレーニング SM + DPCD アクセス) を先にビルドする必要がある。
`top.sv` から `$readmemh` で参照する `bootrom-rs.hex` を生成:

```
$ cd ../../rtl/displayport/test/sw-rs
$ make
```

参照パスは現状 `top.sv` 内に絶対パスで埋め込んである
(`/home/kenta/repos/fpga_samples/...`)。他環境で使う場合は要書換。

### ビットストリーム生成

```
$ make TARGET=tangprimer25k
```

## 構成ファイル

| ファイル | 役割 |
|---------|------|
| `src/tangprimer25k/top.sv` | トップモジュール。`displayport_dp_source_top` を中心に PLL/リセット/TPG/AXI-Stream/OSER10/LVDS を束ねる |
| `src/tangprimer25k/oser10_lane.sv` | Gowin OSER10 ラッパ (10-bit @ PCLK → 1-bit @ 10×PCLK DDR) |
| `src/tangprimer25k/tpg_to_axis.sv` | `test_pattern_generator` の `video_de + RGB` を AXI-Stream 24bpp に変換 |
| `src/tangprimer25k/reset_seq.sv` | PLL ロック後の同期解除リセット |
| `src/tangprimer25k/pins.cst.template` | ボード固有ピン (clock, reset_button, uart_tx, etc.) |
| `src/tangprimer25k/timing.sdc` | クロック制約 (162 MHz / 810 MHz) |
| `src/tangprimer25k/ip/gowin_pll/` | DP クロック PLL (27 → 162 / 810 MHz) ※要再構成 |
| `src/tangprimer25k/ip/gowin_pll_27/` | 50 → 27 MHz クロック生成 |
| `project.tcl` | 全 RTL ファイルを Gowin EDA に登録 |

## 次のステップ（実機動作のために）

1. **PLL 再構成** — 上記 162 / 810 MHz の値で `gowin_pll.ipc` から再生成。
2. **電圧スイング/プリエンファシス** — Gowin LVDS の DRIVE/SLEW 設定を CPU から
   切替できるよう wiring。
3. **実 DP モニタとリンクトレーニング** — DPCD レスポンスを観測し、ADJUST_REQUEST
   ループの実機調整。
4. **マルチレーン対応** — `main_link_tx` を 2/4 lane に拡張、`pixel_steering`
   (DP 1.2 §2.2.1 Tab 2-2) 実装、レーン間 align。OSER10 をレーン数分複製。

## Tang Nano 9K ターゲット

Tang Nano 9K向けのDVIテストパターンジェネレータデザインは過去にあった
`dvi_out_tpg` を引き継ぐ予定。現状は Tang Primer 25K 専用。
