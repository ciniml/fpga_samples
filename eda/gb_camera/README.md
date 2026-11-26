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
- `HOST_UART=0` (既定): Dock の USB-UART はカメラの `csi_ctrl` (115200、`../csi_capture/host/csictl.py`)。
  GameCart は Pmod USB HS Single (`USB_PMOD`、既定 pmod1) だけで、`cart_emu --usb` を使う
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
<!-- 段階 0 の結果をここに書く -->

## 試験
- `rtl/chromatic/test`: `make camera` (GbCamera の撮影 6 通りを `gb_camera_ref.py` とビット一致で照合)、
  `make boot_cam` (カメラ版カートの起動と、GB バスからの撮影: レジスタ、busy、撮影中の RAM、タイルの値)、
  `make boot` / `make unit` (既存。CAMERA=0 で変化なし)。Verilator 5.022 は内部エラーで落ちるので 5.054 を使う
  (`PATH=~/.local/opt/verilator-5.054/bin:$PATH`)
- `rtl/camera_isp/test/run_gb_scale.sh`: IspGbScale を合成した 1280x720 RAW10 で、`gb_scale_ref.py` とビット一致で照合
  (2 フレーム: 黒レベル・ゲイン・左右上下反転、1 語 2〜3 クロック)
- `gb/`: `make shot` で SameBoy (カメラがないとノイズ画像) の画面を撮る

## 未確認
- 実機 (カメラの受信、撮影、Chromatic での表示) はまだ
- OV5640 の 720p30 の初期化 (`ov5640_720p30_init_rom`) は `camera_dvi` 用で、ジェンロックなしで使うのは初めて
- 画像の向き (左右・上下) は実機で設計レジスタ 2 を合わせる
