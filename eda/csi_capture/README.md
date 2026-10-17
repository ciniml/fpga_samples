# csi_capture — Raspberry Pi カメラ (MIPI CSI-2) を Pmod 1 個で受ける (Tang Primer 25K)

Pmod DVI と同じ発想で、Raspberry Pi Camera v2 (IMX219, 15 ピン FFC, 2 レーン) を
FPGA の汎用 LVDS 入力だけで受ける。D-PHY のハード IP も LP 受信器も使わない
**ソフト D-PHY**。受信コアは `rtl/csi2` (Veryl)。

```
 カメラ ──FFC──► 変換基板 ──Pmod(pmod0: H5 系, バンク 1)──► 25K
   CLK/D0/D1: LVDS25 + 内蔵 100Ω 終端 (常時 ON) ─► OSIDES32 ×3 (500 MHz 4 相 = 4 Gsps)
        ─► Csi2Rx (クロックエッジでサンプル → SoT → 2 レーン結合 → ECC/CRC)
        ─► csi_stats (カウンタ / パケットログ / 生サンプルキャプチャ)
   SCL/SDA: I2C 100 kHz ─► 起動 20 ms 後に IMX219 を自動初期化
   USB-UART 115200 ─► host/csictl.py
```

状態: **シミュレーションと合成まで** (2026-10-10)。変換基板が未製作のため実機未確認。

## 変換基板 (Pmod 12 ピン → 15 ピン 1 mm ピッチ FFC)

KiCad プロジェクト: [`hw/Pmod_RPiCamera`](hw/Pmod_RPiCamera/README.md) (25.4 × 24.13 mm, 2 層)。
FFC 側は Raspberry Pi 4 の公式回路図 (raspberry-pi-4-reduced-schematics.pdf, J3 CAMERA) で確認。

| Pmod ピン | 信号 | FFC ピン | 25K (pmod0) |
|---|---|---|---|
| 1 / 7 | SCL / SDA | 13 / 14 | F5 / G5 |
| 2 / 8 | CLK P / N | 9 / 8 | G7 / G8 |
| 3 / 9 | D1 P / N | 6 / 5 | H8 / H7 |
| 4 / 10 | D0 P / N | 3 / 2 | H5 / J5 |
| 5, 11 | GND | 1, 4, 7, 10 | |
| 6, 12 | 3.3 V | 15 (ポリスイッチ 0.5 A 経由) | |
| — | CAM_GPIO (電源/XCLR 有効) | 11 | 10k で 3.3 V にプルアップ |
| — | CAM_CLK (LED) | 12 | 未接続 |

Pmod 上の並び (CLK, D1, D0) は FFC 上の並びに合わせてあり、基板上で差動対が交差しない。
クロックレーンもデータと同じくオーバーサンプルするだけなので、どのピンでもよい。

- 3 対は差動 100Ω (DP 基板と同じ 0.1661/0.127 mm)、F.Cu のみ・ビアなし、B.Cu は全面 GND。
  直列抵抗・AC 結合・バイアス抵抗は**入れない** (D-PHY HS は DC バランスがなく、LP は 1.2V の DC 信号)。
  Pmod DVI 基板はバイアス抵抗があるので流用不可
- 終端は FPGA 内蔵 (DIFF_RESISTOR=ON)。バンク 1 (このスロット) は全対で内蔵終端が使える唯一の Pmod バンク
- I2C は 2.2k で 3.3V にプルアップ (カメラ基板側でレベル変換済み、FFC 側は 3.3V)
- P/N を逆に配線してもデータレーンは `trim ... INV` で、クロックレーンは極性不問で吸収できる

### 電気的な前提と最大のリスク

- HS は SLVS-200 (コモンモード ~200 mV、片側振幅 ~200 mV)。GW5A の LVDS25 入力の
  入力コモンモード下限にこれが入るかは**データシートで未確認**。最初の実機確認項目
- LP-11 (両線 1.2V) は終端に電流が流れない。LP-01/LP-00 は SoT 前の 100 ns 程度だけで、
  終端で潰れてもセンサは監視しない

## 受信方式 (要点)

- IMX219 は**非連続クロック** (ライン間もクロックレーンが LP)。PLL でのクロック再生は不可
- 自走 500 MHz 4 相でクロックレーンも含め全レーンをオーバーサンプル (4 Gsps)。
  クロックの遷移 = データの中央 (DDR) なので、遷移と同じ時刻のデータサンプルを取る
- 詳細とシミュレーション結果は `rtl/csi2/README.md`

## センサ設定 (imx219_init_rom.sv)

Mode A: 640x480 RAW10、中央 1280x960 の 2x2 アナログビニング、2 レーン × **456 Mbps**、約 60 fps。
Linux imx219 ドライバの設定から出力 PLL だけ半分 (PLL_OP_MPY 114 → 57) にしたもの。
IMX219 の出力 PLL の範囲は 432〜916 MHz なので、456 Mbps がほぼ下限。
912 Mbps (Linux と同じ) へは `csictl.py rate 912`。

## ビルド

```
make GW_SH=~/gowin/1.9.12/IDE/bin/gw_sh DISPLAY= QT_QPA_PLATFORM=offscreen
make run   # SRAM, make deploy で Flash
```

`rtl/csi2` の Veryl は Makefile が `veryl build` する。500 MHz 4 相 PLL は
`eda/easycdr_bert/src/tangprimer25k/pll_rx_500m_4ph` を共用。

リソース (GW5A-25): LUT+ALU 約 4.3k (19%)、FF 3.4k、BSRAM 10、OSIDES32 3、PLLA 1。ワードクロック 125 MHz に対し Fmax 127 MHz (余裕は小さい)。

## 立ち上げ手順 (host/csictl.py)

```
csictl.py ping                 # 'p' が返れば UART OK
csictl.py id                   # 0x0219 なら I2C / カメラ電源 OK
csictl.py stats                # 1 秒ごと: レーンのビットレート, fps, 行数, CRC/ECC 誤り
csictl.py capture -m clock     # クロックレーンが動いた瞬間の生サンプル 8 us + ソフト復号
csictl.py log --at-fs          # FS からのパケット列 (FS, EMB, RAW10 x 480, FE)
csictl.py tp 2                 # カラーバー (CRC が通るかの確認用)
csictl.py scan                 # サンプル位置 0..15 で CRC 誤りを数える (アイの幅)
csictl.py trim 8 8             # レーン別サンプル位置 (8 = クロック遷移と同時刻)
```

見るべき順番:
1. `stats` の `lane ... Mb/s` が ~456 か (クロックレーンの遷移が見えている = 電気的に受かっている)
2. `sync` が増えるか (SoT が見えている)
3. `CRC err` が 0 か、`lines` が 480、fps が ~60 か
4. 化ける場合は `capture` の生波形と `scan` でサンプル位置・極性・レーン入れ替わりを確認

LED: B2 = CRC 正常なロングパケット受信中、C2 = 誤り発生 / PLL 未ロック。
スコープ用: pmod2 下段 (G10 クロック活動, D10 RX 中, B10 フレーム中, C10 誤り)。

## テスト

- `rtl/csi2`: `veryl test` (D-PHY モデルで 456/912 Mbps、非連続/連続クロック、LP ノイズ、ppm、ジッタ、スキュー)
- `test/run_ctrl.sh`: csi_ctrl + I2C マスタ + 初期化 ROM を CCI スレーブモデルで (自動初期化で全レジスタ書込、
  P/W/R/D/S コマンド)

## 次の段階 (未実装)

- RAW10 → 2x2 デベイヤ → 320x240 RGB332 フレームバッファ → DVI 出力 (pmod1 に TX 用 Pmod)
- 実機でのコモンモード確認、レート上げ (912 Mbps)、OV5647 (v1.3) 対応
