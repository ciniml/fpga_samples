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

## 重要な制限事項（実機 DP モニタは動かない）

このデザインは **構造的統合の検証用** であり、現状そのままでは実 DP
モニタは画を出しません。理由:

* `serializer_10to1` がシミュレーション用ビヘイビアモデルで、`clock_dvi`
  あたり 1 bit しか出さない。実 RBR は 1.62 Gbps が必要 → Gowin OSER10
  プリミティブのラッパで置き換えが必要。
* メインリンクの bit clock (1.62 GHz) を生成する PLL 設定が未対応。
* 電圧スイング/プリエンファシスの実 PHY 制御が未実装。

検証可能なのは:

* AUX CH の電気特性（DP モニタ → AUX 解析器 や Pmod ドングル）
* HPD 検出と DPCD 読出しシーケンス
* Gowin EDA でのフル合成・配置配線が通るか
* `lane0_bit` がトグルしているか（オシロで観測）

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
| `src/tangprimer25k/top.sv` | トップモジュール。`displayport_dp_source_top` を中心に PLL/リセット/TPG/AXI-Stream/LVDS パッドを束ねる |
| `src/tangprimer25k/tpg_to_axis.sv` | `test_pattern_generator` の `video_de + RGB` を AXI-Stream 24bpp に変換 |
| `src/tangprimer25k/reset_seq.sv` | PLL ロック後の同期解除リセット |
| `src/tangprimer25k/pins.cst.template` | ボード固有ピン (clock, reset_button, uart_tx, etc.) |
| `src/tangprimer25k/timing.sdc` | クロック制約 |
| `src/tangprimer25k/ip/gowin_pll/` | クロック PLL (50 → clock_dvi / clock_dvi_ser) |
| `src/tangprimer25k/ip/gowin_pll_27/` | 27 MHz クロック生成 |
| `project.tcl` | 全 RTL ファイルを Gowin EDA に登録 |

## 次のステップ（実機動作のために）

1. **OSER10 ラッパで `serializer_10to1` を置き換え** — `clock_dvi` を 162 MHz、
   `clock_dvi_ser` を 1.62 GHz に PLL を再構成。10-bit エンコーダ出力を OSER10 へ。
2. **電圧スイング/プリエンファシス** — Gowin LVDS の DRIVE/SLEW 設定を CPU から
   切替できるよう wiring。
3. **実 DP モニタとリンクトレーニング** — DPCD レスポンスを観測し、ADJUST_REQUEST
   ループの実機調整。
4. **マルチレーン対応** — `main_link_tx` を 2/4 lane に拡張、`pixel_steering`
   (DP 1.2 §2.2.1 Tab 2-2) 実装、レーン間 align。

## Tang Nano 9K ターゲット

Tang Nano 9K向けのDVIテストパターンジェネレータデザインは過去にあった
`dvi_out_tpg` を引き継ぐ予定。現状は Tang Primer 25K 専用。
