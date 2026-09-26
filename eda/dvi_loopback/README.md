# dvi_loopback — Tang Primer 25K DVI 1080p60 TX→RX ループバック

1 枚の Tang Primer 25K で DVI を送受信し、1920x1080p60 (ピクセルクロック 148.5MHz、
1.485Gbps/レーン) で `rtl/dvi_in` がビットパーフェクトに受けられるかを確かめる。

## 接続

Pmod を 2 枚使い、HDMI ケーブルでつなぐ。スロット名は `eda/targets/tangprimer25k/pmod_ports.csv` の番号
(ボードのシルクと食い違うことがあるので、FPGA ピン名で確認する)。

| 役割 | スロット | ピン (P 側、N は +6) | 備考 |
|---|---|---|---|
| RX | pmod0 | CLK=H5, D0=H8, D1=G7, D2=F5 | LVDS25 + 内蔵 100Ω 終端 (バンク 1) + CTLE。**FPGA 側にバイアス抵抗のある Pmod DVI** を挿す |
| TX (`TX_SLOT=PMOD1`、動作確認済み) | pmod1 | CLK=L5, D0=K11, D1=E11, D2=A11 | ELVDS_OBUF、LVPECL33E DRIVE=16。送信専用の Pmod HDMI (バイアス抵抗なし) で可 |
| TX (既定) | pmod2 | CLK=C11, D0=B11, D1=D11, D2=G11 | 同上 |
| dbg | TX に使っていない方 (pmod1 / pmod2) | pin1〜4 | [0] 不一致フレーム (約 110us パルス), [1] デコードエラー, [2] RX DE, [3] RX VSYNC |

送信専用の Pmod HDMI (バイアス抵抗なし) を RX 側に使うと、720p でもレーン 1/2 で孤立ビットが落ちる。

- LED: B2 = ワードロック、C2 = 直近約 0.1 秒に不一致フレームかデコードエラーあり
- UART: USB Debugger (FT2232 if01)、115200 8N1
- TX と RX は別の HCLK グループ (バンク 6/7 とバンク 1) なので、FCLK はそれぞれ独立

## 構成

```
50MHz ─ pll_27 ─ 27MHz ─ pll_tx_1080p ─ 148.5 / 742.5MHz
          loop_pattern → dvi_out → OSER10 x4 → ELVDS_OBUF → PMOD2 ──HDMI──┐
                 └ frame_sum (TX 基準)                                     │
PMOD0 → TLVDS_IBUF ─ CLK → pll_rx_1080p (148.5 → 148.5 / 742.5MHz)  ←──────┘
                    └ D0-2 → dvi_in_phy (IODELAY + IDES10 + dvi_in, dvi_capture と共用)
                                 → loop_check (frame_sum を TX 基準と比較、カウンタ)
                                 → loop_report (UART、50MHz ドメイン)
```

- PLL: DS1103 Table 3-36 の制約 (PFD ≤ 87.5MHz、VCO 700〜1400MHz) により、
  TX は 27MHz × 27.5 (分数 MDIV)、RX はケーブルクロック ÷2 × 10 で、どちらも VCO = 742.5MHz、ODIV1 = 1
- パターン (`loop_pattern.sv`) は座標だけで決まる静的画像。3 チャネルがすべてのバイト値を
  別々の並びで通るので、TMDS データシンボルと DC バランスの両分岐を使い、R/G を入れ替えると和が変わる
- `frame_sum`: 1 フレームのアクティブ画素について s1 += 画素、s2 += s1 と画素数を計算する。
  RX はフレームごとに TX の値と比べる。CRC32 は 148.5MHz で閉じなかったので加算型にした

## 実機結果 (2026-09-26、`TX_SLOT=PMOD1`)

| 構成 | 結果 |
|---|---|
| `RATE=720P CTLE=OFF` | ビットパーフェクト (B=0、E=0、N=000E1000) |
| 1080p `CTLE=HIGH` | ロックし N=001FA400。最良点 (O=5C 付近) でもデコードエラー約 0x12 / 250ms が残り、全フレームに誤りがある |
| 1080p `CTLE=MEDIUM` / `OFF` | 最良点で HIGH の約 60 倍 / さらに悪い |

- アイの周期は約 0x34 タップ (= 1 UI)。良い位相は O = 28, 5C, 90, C4, F4 付近
- 真の LVDS 出力 (`TLVDS_OBUF` / LVDS25) は Pmod 経由ではロックしなかった (振幅不足)
- TX の LVCMOS33D DRIVE=8 は 1.485Gbps で孤立ビットが落ちる。LVPECL33E DRIVE=16 と RX CTLE=HIGH は
  `eda/easycdr_bert` の 1.4875Gbps 測定の結果に合わせた

## 変種

| 変数 | 値 | 内容 |
|---|---|---|
| `RATE` | `720P` | 1280x720p60 (74.25MHz / 742.5Mbps)。ループバック自体の確認用 |
| `TX_SLOT` | `PMOD1` | TX を pmod1 に置き、dbg を pmod2 に移す |
| `CTLE` | `OFF` / `LOW` / `MEDIUM` / `HIGH` (既定) | RX イコライザ |
| `TX_IO` | `<IO_TYPE>_<DRIVE>` (既定 `LVPECL33E_16`) | TX パッド |
| `TX_CLK` | `ODDR` | クロックレーンを OSER10 でなく ODDR (ピクセルクロック) で出す |

ビルドディレクトリは `build/tangprimer25k_<変種>` に分かれる。

## ビルド・書込み

```sh
DISPLAY= QT_QPA_PLATFORM=offscreen make GW_SH=~/gowin/1.9.12/IDE/bin/gw_sh
make run OPENFPGA_LOADER_DEVICE_OVERRIDE="--busdev-num <bus:dev>"
make sim    # 論理ループバックのシミュレーション (Verilator、PHY はモデル化しない)
```

`rtl/dvi_in` と `rtl/dvi_out` の Veryl は Makefile が必要に応じて `veryl build` する。
合成結果 (Gowin 1.9.12): tx_pclk 180.6MHz、rx_pclk 179.8MHz (制約 148.5MHz)、LUT 10%。

## UART

1 秒ごとに累積カウンタを出す。

```
R L1 F00000E10 B00000000 E00000000 E0000000 E1000000 E2000000 U0001 N001FA400 O20 P1 C8D2F3A10
```

| 欄 | 意味 |
|---|---|
| L | ワードロック (1/0)。RX クロックが無い (スナップショットに応答しない) ときは X |
| F / B | TX と比較したフレーム数 / うち不一致 |
| E | デコードエラーのあったクロック数 |
| U | ワードロック喪失の回数 |
| N | 最後に比較したフレームのアクティブ画素数 (1080p は 001FA400 = 2073600) |
| O | IODELAY オフセット (DLYSTEP = 24 + O) |
| E0 / E1 / E2 | レーン別のデコードエラー (下位 24 bit) |
| P / C | RX 復元 PLL のロック / RX クロックの累積サイクル数 (行ごとの差分が周波数) |

コマンド (1 文字): `+` / `-` でオフセット ±4、`d` で既定値 (0x20)、`c` でカウンタクリア、
`s` でサンプリング位相スキャン、`w` で 3 レーンの生ワード (12 個ずつ、レーン 0 のコントロールシンボルから)。スキャンは O = 00, 04, … FC の各点で 60ms 待ってから
250ms (約 15 フレーム) 計測し、差分を `S` 行で出す。終わるとオフセットを元に戻す。

1.485Gbps の 1UI は約 48 タップ (約 14ps/タップ)。720p で求めた既定値 0x20 (実効 56) が
そのまま使えるとは限らないので、最初にスキャンしてアイの位置を確かめる。GW5A の IODELAY は
遅延を大きくするほど付加ジッタで悪化したので (dvi_capture での知見)、クリーンな区間が
複数あるときは最も小さい値を選ぶ。

## 判定の目安

- `N001FA400` かつ `B` が増えない: 画素・DE・レーン順すべて一致
- `F` が増えない: ロックはしているのに VSYNC が取れていない (レーン 0 と 2 の取り違えなど)
- `B` が毎フレーム増える: 系統的なずれ (R/G の取り違え、ビット順など)
- `E` だけが増える: ブランキング中のシンボル誤り (720p では無終端バンクの ISI がこの形で出た)
