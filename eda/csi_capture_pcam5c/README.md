# csi_capture_pcam5c — Digilent Pcam 5C (OV5640) を Pmod 1 個で受ける (Tang Primer 25K)

[`eda/csi_capture`](../csi_capture/README.md) (Raspberry Pi Camera v2 / IMX219) の Pcam 5C 版。
ソースは `eda/csi_capture/src/tangprimer25k` をそのまま使い、`CSI_SENSOR_OV5640` を定義してビルドする
(`src/tangprimer25k/csi_sensor.v`)。違いは csi_ctrl の設定だけ:

| | csi_capture (RPi Camera v2) | csi_capture_pcam5c (Pcam 5C) |
|---|---|---|
| センサ | IMX219 | OV5640 |
| I2C アドレス (7 bit) | 0x10 | 0x3C |
| 初期化 ROM | `imx219_init_rom.sv` | `ov5640_init_rom.sv` |
| 出力 | 640x480 RAW10 約 60 fps | 1280x720 RAW10 30 fps (ビニング) |
| レーン速度 | 456 Mbps (非連続クロック) | 280 Mbps (連続クロック、0x4800 = 0x14) |
| `csictl.py ping` | 0x01 | 0x51 |

状態: **実機で受信 OK** (2026-11-16)。

## 実機確認の結果 (2026-11-16、Tang Primer 25K + Pmod_RPiCamera rev A + Pcam 5C 付属ケーブル、pmod0)

| 項目 | 結果 |
|---|---|
| `ping` / `id` | 0x51 / 0x5640 (OV5640)。存在しないアドレスは NACK |
| 自動初期化 | NACK 0。0x3008 = 0x02 (動作中)、0x3808 = 0x05 (幅 1280) など ROM どおり |
| `stats` (720p、ROM の既定) | **280.0 Mb/s/レーン、30.0 fps、720 行、RAW10 WC 1600、CRC / ECC 誤り 0** |
| 連続 2 分 | ロングパケット約 260 万 (約 4.1 Gbit)、CRC / ECC 誤り 0 |
| `tp 1` (カラーバー) | CRC 誤り 0 |
| `log --at-fs` | FS → LS → RAW10 WC 1600 (CRC ok) → LE → ... |
| `scan` | サンプル位置 3〜13 (16 中 11、0.25 ns 刻み) で誤り 0。既定の 8 は中央 |
| 1080p30 (Digilent `cfg_1080p_30fps_336M_mipi_` をホストから書込み) | **672 Mb/s/レーン**、24 fps、1080 行、WC 2400。修正前: CRC 誤りが約 2 万行に 1 回 (画像の内容で出たり出なかったり)、誤りの数だけ 2 レーンの sync 数がずれる。原因はペイロード先頭での偽の再同期 (`rtl/csi2/README.md` の早期ロック)。**修正後: 3 分 (約 470 万行) で CRC 誤り 0、sync 数一致** |

デモ名の「60 fps」にはならない (PCLK 56 MHz、HTS 1896 × VTS 984 で 30 fps、レーン速度もそれに見合う 280 Mbps)。

最初のビルドでは I2C が全アドレス ACK・読み値 0x00 で動かなかった。原因は pins.cst の `OPEN_DRAIN=ON` で、
IOBUF (I = 0、OEN で開放) と併用すると SCL / SDA が常に Low になる。属性を外して解決 (`eda/csi_capture` も同じ pins.cst)。

## 初期化 ROM (`../csi_capture/src/tangprimer25k/ov5640_init_rom.sv`)

レジスタ値は Digilent の Zybo Z7 Pcam 5C デモ (github.com/Digilent/Zybo-Z7-SW、ブランチ 20/Pcam-5C/master の
`OV5640.h`、MIT ライセンス、ファイル冒頭に許諾文) から。デモの順序 (init → set_mode(720p60) → set_awb(advanced)) どおり:

1. 50 ms 待ち (PWUP 後 SCCB まで 50 ms 以上)
2. 0x3103 = 0x11 (クロックをパッドから)、0x3008 = 0x82 (ソフトウェアリセット)、100 ms 待ち
3. `cfg_init_` (2 レーン MIPI、PLL、アナログ設定。ソフトウェアパワーダウンのまま)
4. 0x3008 = 0x42、`cfg_720p_60fps_` (1280x720 RAW10、HTS 1896 / VTS 984)、`cfg_advanced_awb_`
5. 0x3008 = 0x02 (動作開始)

デモは PWUP を 100 ms 下げて電源を入れ直すが、変換基板は PWUP (FFC 11 番) を R3 で 3.3 V に吊っているので
できない。ソフトウェアリセットで代用している。レジスタは `csictl.py wr` で何でも書き換えられる。

## つなぎ方

- 変換基板 [Pmod_RPiCamera](../csi_capture/hw/Pmod_RPiCamera/README.md) を Dock の **pmod0 (J6)** に挿す
  (ピン割り当ては `eda/csi_capture` と同じ)。ジャンパ不要
- **Pcam 5C 付属の 10 cm ケーブル** (両端で接点の向きが逆) をそのまま使う。Pcam 側も変換基板の J2 も
  基板側に接点があるコネクタなので、ピン n ↔ ピン n になる。両端で接点の向きが同じケーブルは使わない
- Pcam 5C は Raspberry Pi カメラとピン互換 (Digilent の資料)。11 番 PWUP = 電源有効 (変換基板の R3 で常時 ON)、
  13 / 14 番 SCL / SDA (Zybo Z7 も 3.3 V で駆動、変換基板の 2.2 kΩ プルアップで可)、15 番 3.3 V

## ビルド

```
make GW_SH=~/gowin/1.9.12/IDE/bin/gw_sh DISPLAY= QT_QPA_PLATFORM=offscreen
make run      # SRAM (make deploy で Flash)
```

ホストは `eda/csi_capture/host/csictl.py` (ping の版数 0x51 で OV5640 と判断し、`id` / `tp` / `stream` を切り換える)。
csi_ctrl の試験は `eda/csi_capture/test/run_ctrl.sh` (IMX219 と OV5640 の両方)。

## 立ち上げ手順

通電前 (テスタ):
1. 変換基板単体で Pmod 6 番 (3.3 V) – 5 番 (GND) が短絡していないこと
2. Pcam 5C をケーブルでつないだ状態でも同じ箇所が短絡していないこと (短絡ならケーブルの向きが逆)

通電後:

| 手順 | 操作 | 合格 |
|---|---|---|
| 1 | 電源投入、`make run` | 電流が安定、F1 が切れない。FFC 11 番 (R3) が約 3.3 V (半分程度なら Pcam 側のプルダウンと競合: R3 を 1 kΩ 以下に) |
| 2 | `csictl.py ping` | `0x51 (OV5640 / Pcam 5C build)` |
| 3 | `csictl.py id` | `0x5640 (OV5640)` (I2C と Pcam の電源 OK) |
| 4 | `csictl.py stats` | `lane 280.0 Mb/s` (連続クロックなので常に見える)。`sync` が増える |
| 5 | `csictl.py tp 1` (8 色カラーバー) → `stats` | CRC err 0、lines 720、30 fps。LED B2 点灯、C2 消灯 |
| 6 | `csictl.py log --at-fs` | FS → RAW10 WC 1600 × 720 → FE (OV5640 は LS / LE のショートパケットも出す) |
| 7 | `csictl.py tp 0` で実画像に戻し数分 | CRC / ECC 誤り 0 のまま |
| 8 | 化ける場合 | `capture -m clock` (生サンプル)、`scan` (サンプル位置ごとの CRC 誤り)、`trim` (レーン別、`INV` で P/N 反転) |

`init` で初期化をやり直すと NACK 数が表示される (0 が正常)。最大のリスクは IMX219 と同じく、HS 信号の
コモンモード (約 200 mV) を GW5A の LVDS 入力が受けられるか。
