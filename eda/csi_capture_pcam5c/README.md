# csi_capture_pcam5c — Digilent Pcam 5C (OV5640) を Pmod 1 個で受ける (Tang Primer 25K)

[`eda/csi_capture`](../csi_capture/README.md) (Raspberry Pi Camera v2 / IMX219) の Pcam 5C 版。
ソースは `eda/csi_capture/src/tangprimer25k` をそのまま使い、`CSI_SENSOR_OV5640` を定義してビルドする
(`src/tangprimer25k/csi_sensor.v`)。違いは csi_ctrl の設定だけ:

| | csi_capture (RPi Camera v2) | csi_capture_pcam5c (Pcam 5C) |
|---|---|---|
| センサ | IMX219 | OV5640 |
| I2C アドレス (7 bit) | 0x10 | 0x3C |
| 初期化 ROM | `imx219_init_rom.sv` | `ov5640_init_rom.sv` |
| 出力 | 640x480 RAW10 約 60 fps | 1280x720 RAW10 60 fps (ビニング) |
| レーン速度 | 456 Mbps (非連続クロック) | 約 560 Mbps の見込み (連続クロック、0x4800 = 0x14) |
| `csictl.py ping` | 0x01 | 0x51 |

状態: シミュレーション (csi_ctrl の初期化) と合成まで (2026-11-16)。実機未確認。

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
| 4 | `csictl.py stats` | `lane ... Mb/s` が数百 Mb/s (約 560 の見込み、連続クロックなので常に見える)。`sync` が増える |
| 5 | `csictl.py tp 1` (8 色カラーバー) → `stats` | CRC err 0、lines 720、約 60 fps。LED B2 点灯、C2 消灯 |
| 6 | `csictl.py log --at-fs` | FS → RAW10 WC 1600 × 720 → FE (OV5640 は LS / LE のショートパケットも出す) |
| 7 | `csictl.py tp 0` で実画像に戻し数分 | CRC / ECC 誤り 0 のまま |
| 8 | 化ける場合 | `capture -m clock` (生サンプル)、`scan` (サンプル位置ごとの CRC 誤り)、`trim` (レーン別、`INV` で P/N 反転) |

`init` で初期化をやり直すと NACK 数が表示される (0 が正常)。最大のリスクは IMX219 と同じく、HS 信号の
コモンモード (約 200 mV) を GW5A の LVDS 入力が受けられるか。
