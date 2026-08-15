# EasyCDR 1.2Gbps ループバックサンプル (Tang Primer 25K)

Gowin EasyCDR IP (IDE 1.9.12同梱、BEYOND_1G/32bit構成) を使った
1.2Gbps PRBSループバックBERテストです。`gowin_easycdr_sample`
(1.0Gbps/16bit構成) の派生で、1Gbps超のクロッキング規則
(IPUG1040: HCLK=レート/4、動作周波数=レート/16) に従っています。

## 構成

| 項目 | 内容 |
|---|---|
| ラインレート | 1.2Gbps |
| RXクロック | 300MHz 4相 (PLL_T)、パラレル75MHz |
| TXクロック | 600MHz + 150MHz (専用PLL、OSER8 8:1) |
| 遅延タップ | DELAY_0..3 = 0/17/30/47 (IP GUIのR=1.2計算値) |
| パターン | PRBS9 (周期511bit、`prbs_top`) |

## 配線 (ExtEasyCDRモジュール + USB-Cケーブル)

ExtEasyCDR (Type-C Pmodモジュール、AC結合100nF + 10k/1.65Vバイアス内蔵)
2枚とフル機能パッシブType-Cケーブルでループバックします。

| 信号 | FPGAピン | 位置 |
|---|---|---|
| TX P/N | G7 / G8 | pmod0 ピン2/8 = モジュールのレーンL1 (USB-C RX2ピン) |
| RX P/N | G11 / G10 | pmod2 ピン1/7 = モジュールのレーンL0 (USB-C TX2ピン) |

TXをレーンL1から送るのは、標準Type-CケーブルのTX2↔RX2クロス結線に
より対向モジュールのレーンL0 (=RXピン) へ極性ストレートで届くためです。
ケーブルを反転挿しするとレーンが入れ替わり無信号になるので、向きを
マーキングして固定してください。

- RX終端: オンチップ100Ω差動 (IOT系ピンのみ有効。外付け終端は付けない)
- RX CTLE=HIGH / TX DRIVE=16mA (実機A/Bテストで確定した最良値)
- ジャンパ線直結の場合は TX=F5/G5 (pmod0 1/7)、RX=G11/G10 に戻す

## 観測

| ピン | 信号 | 正常時 |
|---|---|---|
| B2 | o_dat_lock | High (ケーブル抜去で~109µs後にLow、再接続で復帰) |
| C2 | o_dat_err | Low |
| E1 | dout_flag_xor | 13.628µs周期の方形波 (EC92マーカ検出) |
| H11 | reset_in | 押すとリセット (正論理) |

o_dat_lock はPRBSチェッカ出力をそのまま出さず、EC92マーカの
ウォッチドッグ (タイムアウト~109µs) でゲートしています。素のチェッカは
無信号時の全ゼロ系列 (LFSRの不動点) に偽ロックするためです。

## ビルド

```sh
QT_QPA_PLATFORM=offscreen make synthesis GW_SH=~/gowin/1.9.12/IDE/bin/gw_sh
make run     # openFPGALoaderでSRAM書き込み
```

## 注意点 (gowin_easycdr_sampleでの知見)

- 1.9.12コアは復元ビットを `dout_o` の bit0 から時間順に詰めます
  (旧1.9.9コアと逆順)。`top.v` で16bit半ワード毎にビット反転して
  PRBSチェッカに渡しています。
- Gowin付属のPLLAシミュレーションモデルは位相シフト未実装のため、
  post-PnRネットリストをそのままsimしても4相が同相になりCDRは
  動作しません (位相遅延のパッチが必要)。
- BEYOND_1G構成の `dout_en_o` は平均1/2デューティですが連続サイクルで
  アサートされるバースト性があります。32→16bitギアボックスは単純な
  2フェーズではなくFIFO (本デザインは8ワード) で受ける必要があります。
- 2ボード間リンクでは水晶周波数差によりFIFOが数ms周期で溢れて
  エラーバーストが出ます (16bit×75MHzの検査経路に帯域余裕がないため)。
  対策はインスペクタの150MHz化 (未実装)。
