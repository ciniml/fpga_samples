# gb_camera — ポケットカメラ風カート (Tang Primer 25K + Pcam 5C)

`gb_fpga_cart_de0` に挿した Tang Primer 25K を、Game Boy Camera と同じ仕組みのカメラ付きカートにする。
カメラは Digilent Pcam 5C (OV5640、MIPI CSI-2) を Pmod_RPiCamera で pmod0 に挿す。
- カートの部分は [`../cart_game`](../cart_game/) (GameCart) にマッパー 6 (カートタイプ FCh) を足したもの
- カメラの受信は [`../csi_capture`](../csi_capture/) と同じ (ソフト D-PHY 2 レーン、720p30 RAW10)
- GB 側のソフトは [`gb/`](gb/) (GBDK、CGB 専用のファインダー)

```
pmod0: Pcam 5C ─► csi_phy_gw5a ─► Csi2Rx ─► IspRaw10Unpack ─► IspGbScale ──► フレーム 128x112 (BSRAM)
                                                              [pclk 125 MHz]          │
GB バス ◄── GameCart (マッパー 6) ◄── GbCamera: レジスタ 0xA000、撮影 → RAM バンク 0 の 0xA100 ◄┘
                                                              [clk 100 MHz]
csi_ctrl: OV5640 の初期化 (起動の約 20 ms 後に自動)、UART のコマンド          [clk_in 50 MHz]
```

## ビルドと書き込み
```sh
GW_SH=~/gowin/1.9.12.03/IDE/bin/gw_sh DISPLAY= QT_QPA_PLATFORM=offscreen make   # build/tangprimer25k/impl/pnr/gb_camera.fs
make run                                                       # TP25K の SRAM へ
make -C gb                                                     # gb/build/gbcam.gbc
cd ../../util/cart_emu && cargo build --release
./target/release/cart_emu --usb game write ../../eda/gb_camera/gb/build/gbcam.gbc   # フラッシュ 0x400000 へ
./target/release/cart_emu --usb game start ../../eda/gb_camera/gb/build/gbcam.gbc --cont
openFPGALoader --cable gwu2x -r                                # Chromatic を公式ファームで起動し直す
./target/release/cart_emu --usb game cam-status                # フレーム数、撮影数、レジスタ
./target/release/cart_emu --usb game cam-frame -o frame.pgm    # カメラのフレーム (128x112、8 ビット)
```
- 挿す場所: カメラ (Pmod_RPiCamera) は **pmod0** (F5 がある側)、Pmod USB HS Single は **pmod2**。
  Pmod_RPiCamera は基板の幅が Pmod の規格より広く、隣の pmod1 にかかるため (`USB_PMOD`、既定 pmod2)
- `HOST_UART=0` (既定): Dock の USB-UART はカメラの `csi_ctrl` (115200、`../csi_capture/host/csictl.py`)。
  GameCart は Pmod USB HS Single だけで、`cart_emu --usb` を使う
- `make HOST_UART=1`: USB-UART を GameCart に回す (`cart_emu` を UART で使う。`csi_ctrl` にはホストがない)
- フラッシュにビットストリームと ROM を置けば、`cart_game` と同じく電源投入だけで起動する (AUTO_BOOT)

## カメラ (マッパー 6 と GbCamera)
Game Boy Camera と同じレジスタにした。SameBoy (`Core/camera.c`) のカメラのエミュレーションと同じ手順で処理する。
| アドレス | 内容 |
|---|---|
| 0000-1FFF | RAM 有効 (0Ah) |
| 2000-3FFF | ROM バンク (MBC5 と同じ 8 ビット) |
| 4000-5FFF | RAM バンク。bit 4 が 1 (10h-1Fh) で A000-BFFF がカメラのレジスタ |
| A000 | bit 0: 1 を書くと撮影、終わるまで 1 が読める (読めるのはこのレジスタだけ) |
| A001 | bit 4-0 ゲイン、bit 7-5 = 111 で輪郭強調 |
| A002-A003 | 露出 (0x1000 = 1 倍) |
| A004 | bit 6-4 輪郭強調の比 (0.5〜5)、bit 3 反転 |
| A006-A035 | ディザのしきい値 (4x4 画素 x 3 段) |

- 撮影の指示から次のフレームが揃うのを待ち (最大 1 フレーム = 33 ms)、画素ごとに
  `(v × ゲイン × 露出) >> 20` → (輪郭強調) → しきい値で 4 階調にし、RAM バンク 0 の A100-AEFF に 16x14 タイルで書く
- 処理は 1 画素 1 クロック (輪郭強調ありは 5 クロック): 143 µs (輪郭強調ありは 717 µs)
- 撮影中は RAM の読み出しが 0、書き込みは捨てる。RAM の読み出しは RAM 有効にしなくてもできる (SameBoy と同じ)
- RAM は 32 KiB (バンク 0-3)。Game Boy Camera の 128 KiB は block RAM に入らない
  (このため、Game Boy Camera の ROM や 128 KiB 前提のソフトは動かない)
- 露出はカメラ側の自動露出のままで、A002-A003 はデジタルの係数として掛ける。カメラの露出は変えない
- 1 フレーム待っても次のフレームが来ないとき (カメラがない、止まっている) は約 0.1 秒で今のフレームのまま処理する

### カメラの画像 (IspGbScale)
- 1280x720 RAW10 の中央 768x672 を 6x6 画素ずつ足して 128x112 にする (ベイヤーの色の重みはかけない。6x6 には R 9、G 18、B 9 が入る)
- 平均 → 黒レベル (既定 16) を引く → ゲイン (8.8、既定 1.0) → sRGB の曲線 (`IspGamma`)
- 設計レジスタ (`csictl.py` の 'X' / 'Y'): 0 黒レベル、1 ゲイン、2 {上下反転, 左右反転}、0x10 フレーム数 (読み出しのみ)
- 画角は 1280x720 の中央を切り抜くので、元の画角の 60% (横) x 93% (縦)

## 資源とタイミング
Gowin 1.9.12.03、既定の構成 (USB pmod2、HOST_UART=0)、2026-11-26:
| 資源 | 使用量 |
|---|---|
| ロジック | 11402 / 23040 (50%)、CLS 71% |
| BSRAM | 55 / 56 (GameCart の RAM と複製、バンク 0、フレームバッファ 8、USB など。トレースは外した) |
| PLLA | 4 / 6 (100/200 MHz、USB 2 個、カメラ 500 MHz 4 相) |
| PRIMARY クロック | 8 / 8 (clk_in、clk、clk2、pll_60m、os_f480、clk60、カメラの pclk、USB の pclk) |

| クロック | 目標 | Fmax |
|---|---|---|
| clk (GameCart、GbCamera) | 100 MHz | 100.4 MHz |
| clk2 (QspiRom) | 200 MHz | 201.2 MHz |
| pclk (カメラ) | 125 MHz | 127.7 MHz |
| clk60 (USB) | 60 MHz | 60.5 MHz |
| os_pclk (USB) | 120 MHz | 141.2 MHz |

- 余裕はどれも小さい。最初の版は累算器がフリップフロップになって pclk 108 MHz、clk 89 MHz だったので、
  累算器を BSRAM (1 クロックで読んで次で書く) にし、ゲインとしきい値の段を分けた
- BSRAM の残りは 1。PRIMARY クロックは使い切ったので、クロックを増やすなら USB をやめる (HOST_UART=1) しかない

## 試験
- `rtl/chromatic/test`: `make camera` (GbCamera の撮影 6 通りを `gb_camera_ref.py` とビット一致で照合)、
  `make boot_cam` (カメラ版カートの起動と、GB バスからの撮影: レジスタ、busy、撮影中の RAM、タイルの値)、
  `make boot` / `make unit` (既存。CAMERA=0 で変化なし)。Verilator 5.022 は内部エラーで落ちるので 5.054 を使う
  (`PATH=~/.local/opt/verilator-5.054/bin:$PATH`)
- `rtl/camera_isp/test/run_gb_scale.sh`: IspGbScale を合成した 1280x720 RAW10 で、`gb_scale_ref.py` とビット一致で照合
  (2 フレーム: 黒レベル・ゲイン・左右上下反転、1 語 2〜3 クロック)
- `gb/`: `make shot` で SameBoy (カメラがないとノイズ画像) の画面を撮る

## 実機の結果 (2026-11-26)
SRAM に書き込んだ `HOST_UART=0` 版と `HOST_UART=1` 版、ROM は `gb/build/gbcam.gbc` (フラッシュ 0x400000)。
- カメラ: csi_ctrl の ID 読み出しで 0x5640、128x112 のフレームが 29.7 fps で揃う (`camera_dvi` の 720p30 の初期化はジェンロックなしでも動いた)
- `cart_emu game cam-frame` で取り出したフレームに天井の照明が写る (平均 203)
- Chromatic (公式ファーム) で `gbcam.gbc` が起動し、ファインダーに画像が出る。撮影 9621 回でタイムアウト 0、
  撮影 1 回 9〜15 ms (フレーム待ちを含む)、ファインダーは毎秒 13〜16 枚。保存 (A) の RAM 書き込みも動く
- カートの読み出しは遅れ 0 (ROMX 3936 万回)
- cart_emu: Windows (USB) から `game status` が通る (エンドポイントの halt を開くときに解除する修正の後)。
  プローブサーバー (fpga-config の gowin-probe-server) の UART を疑似端末にして `--tty` で使えることも確かめた

## 未確認
- 画像の向き (左右・上下) が実物と合っているか。合わなければ設計レジスタ 2 (`HOST_UART=0` の版で `csictl.py` から) で直す
- 輪郭強調、反転、露出を大きく変えたときの見え方
