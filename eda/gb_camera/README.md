# gb_camera — ポケットカメラ風カート (Tang Primer 25K + Pcam 5C)

ModRetro Chromatic (公式ファームのまま) に挿す、Game Boy Camera と同じ仕組みのカメラ付きカート。
Tang Primer 25K がカートのバスに応答し、Digilent Pcam 5C (OV5640、MIPI CSI-2) の画像を Game Boy Camera のレジスタと RAM で見せる。
GB 側のソフト ([`gb/`](gb/)) は CGB 専用で、タイル行ごとに 4 パレットを HBlank で切り替えてフルカラーで表示する。

```
pmod0: Pcam 5C ─► csi_phy_gw5a ─► Csi2Rx ─► IspRaw10Unpack ─► IspGbScale ──► 128x112 輝度 + RGB565 (BSRAM)
                                                              [pclk 125 MHz]          │
GB バス ◄── GameCart (マッパー 6) ◄── GbCamera: レジスタ 0xA000、撮影 ──────────────────┘
               │                       ├─ 白黒: ゲイン・露出・輪郭強調・ディザ → RAM バンク 0 の 0xA100
               │                       └─ カラー: GbColorQuant (タイル行ごとに 4 パレット) → タイル・属性・パレット
               └─ 切り替えバンクは SPI フラッシュ (0x400000〜) から                    [clk 100 MHz]
csi_ctrl: OV5640 の初期化 (起動の約 20 ms 後に自動)、UART のコマンド                    [clk_in 50 MHz]
```
- カートの部分は [`../cart_game`](../cart_game/) (GameCart) にマッパー 6 (カートタイプ FCh) を足したもの
- カメラの受信は [`../csi_capture_pcam5c`](../csi_capture_pcam5c/) と同じ (ソフト D-PHY 2 レーン、1280x720 RAW10 30 fps)

## 必要なもの
| もの | 備考 |
|---|---|
| ModRetro Chromatic | 公式ファームのまま。改造しない |
| `gb_fpga_cart_de0` | Chromatic のカートスロットに挿し、Tang Primer 25K をつなぐ FPGA カートアダプタ (レベル変換付き)。Dock の 40 ピンヘッダ (J3) につなぐ |
| Sipeed Tang Primer 25K + Dock | GW5A-LV25MG121。ビットストリームと GB の ROM はコア基板の SPI フラッシュに置く |
| Digilent Pcam 5C | OV5640。15 ピン FFC |
| Pmod_RPiCamera | Pmod 1 個で 15 ピン FFC のカメラを受ける変換基板。[`../csi_capture/hw/Pmod_RPiCamera`](../csi_capture/hw/Pmod_RPiCamera/) |
| Pmod USB HS Single (任意) | `HOST_UART=0` の版で `cart_emu --usb` を使うとき。[`../pmod_usb_hs`](../pmod_usb_hs/) |

### 組み立て
- Pmod_RPiCamera を Dock の **pmod0** (F5 がある側) に挿し、Pcam 5C を FFC でつなぐ。
  Pmod_RPiCamera は基板の幅が Pmod の規格より広く、隣の pmod1 にかかるので、Pmod USB HS Single は **pmod2** に挿す (`USB_PMOD`、既定 pmod2)
- `gb_fpga_cart_de0` を Dock の J3 につなぎ、Chromatic に挿す
- TP25K は Dock の USB (FT2232、JTAG と USB-UART) から給電する

## 開発環境
| ツール | 版 | 用途 |
|---|---|---|
| Gowin FPGA Designer (`gw_sh`) | 1.9.12.03 | 論理合成・配置配線 (無償ライセンスが必要) |
| [Veryl](https://veryl-lang.org/) | 0.22.1 | `rtl/` の `.veryl` から SystemVerilog を生成 (`make` が呼ぶ) |
| openFPGALoader | 1.1.1 | TP25K の SRAM・フラッシュへの書き込み |
| [GBDK-2020](https://github.com/gbdk-2020/gbdk-2020) | 4.6.0 | GB の ROM。`GBDK_HOME` (既定 `~/opt/gbdev/gbdk/`) |
| Rust (cargo) | stable | ホストツール [`util/cart_emu`](../../util/cart_emu/) |
| Verilator | 5.054 | 試験のみ (5.022 は内部エラーで落ちる) |
| SameBoy | — | 任意。GB の ROM をエミュレータで動かす (`gb/` の `make run`、`SAMEBOY=`) |

## 作り方と書き込み
### 1. ビットストリーム
```sh
cd eda/gb_camera
GW_SH=~/gowin/1.9.12.03/IDE/bin/gw_sh DISPLAY= QT_QPA_PLATFORM=offscreen make HOST_UART=1
# → build/tangprimer25k_hostuart/impl/pnr/gb_camera.fs
```
- `HOST_UART=1`: Dock の USB-UART (`/dev/ttyUSB1`、1 Mbaud) を GameCart のホスト (`cart_emu`) に回す。Pmod USB HS Single は不要。
  **実機で動かしてフラッシュに書いたのはこちら**
- `HOST_UART=0` (既定): USB-UART はカメラの `csi_ctrl` (115200、`../csi_capture/host/csictl.py`) になり、
  GameCart のホストは Pmod USB HS Single (`cart_emu --usb`) だけになる。ビルド先は `build/tangprimer25k`
- 配置配線は `place_option 1` / `route_option 2` (project.tcl の既定、`PLACE_OPTION` / `ROUTE_OPTION` で変えられる)。
  Gowin の既定の配線ではタイミングが約 0.2 ns 足りない

### 2. GB の ROM
```sh
make -C gb            # gb/build/gbcam.gbc (CGB 専用、カートタイプ FCh、ROM 32 KiB、RAM 32 KiB)
```

### 3. TP25K に書く
まず SRAM に書いて ROM をフラッシュに置き、動いたらビットストリームもフラッシュに置く。
```sh
openFPGALoader -b tangprimer25k build/tangprimer25k_hostuart/impl/pnr/gb_camera.fs   # SRAM へ (電源を切ると消える)

cd ../../util/cart_emu && cargo build --release
./target/release/cart_emu game write ../../eda/gb_camera/gb/build/gbcam.gbc          # ROM をフラッシュ 0x400000 へ
./target/release/cart_emu game start ../../eda/gb_camera/gb/build/gbcam.gbc --cont   # 今すぐ応答を始める (フラッシュから起動したときは自動)

# ビットストリームをフラッシュへ (電源を入れるだけで起動するようになる)
openFPGALoader -b tangprimer25k --write-flash --unprotect-flash --verify \
    ../../eda/gb_camera/build/tangprimer25k_hostuart/impl/pnr/gb_camera.fs
```
- `HOST_UART=0` の版では `cart_emu` に `--usb` を付ける (`--tty` の代わり)。Windows でも `cart_emu.exe --usb` が使える
  (WinUSB、ドライバのインストールは不要)
- フラッシュから起動した FPGA は、`cart_game` と同じく 0x400000 の ROM のヘッダを読んで自分で応答を始める (AUTO_BOOT)。
  `cart_emu game status` に `boot from the flash: started by itself` と `camera` が出れば動いている
- フラッシュの先頭 (ビットストリーム) は `cart_emu` からは書けない (0x400000 より前への書き込みは GameCart が通さない)
- 元のフラッシュの中身を残したいときは、書く前に `cart_emu game flash-read -o backup.bin --offset 0 --len 0x100000` で読んでおく

### 4. Chromatic で起動
TP25K が動いている状態で Chromatic の電源を入れる (TP25K を先に)。Chromatic を挿したまま TP25K を書き直したときは、
Chromatic の電源を入れ直す (GWU2X 対応の openFPGALoader があれば `openFPGALoader --cable gwu2x -r` でもよい)。

## 遊び方 (gb/)
タイトル画面 (GB CAMERA) で SHOOT か VIEW を選ぶ (左右 / SELECT で選び、A / START で決定)。
| 画面 | ボタン | 動作 |
|---|---|---|
| SHOOT (ファインダー) | A | 撮影 (シャッター音とフラッシュ)。続けて A でアルバムに残す、B で捨てる |
| | START | セルフタイマー (3 秒。B で取り消し) |
| | SELECT | カラー / 白黒の切り替え |
| | 上下 | カラー: 明るさ (-4〜+4)、白黒: 露出 |
| | 左右 | 白黒: コントラスト (0〜15) |
| | B | タイトルへ |
| VIEW (アルバム) | 左右 | 写真を選ぶ |
| | A | 消す (続けて A で確定) |
| | B | タイトルへ |

- アルバムは 3 枚で、カート RAM のバンク 1〜3 に置く。カート RAM は BSRAM なので **TP25K の電源を切ると消える**
  (`cart_emu game save` / `game start --sav` で取り出し・書き戻しができるはずだが、カメラ版では未確認)
- 白黒のファインダーは毎秒 13〜16 枚。カラーは 1 枚の書き換えに 14 フレームかかる (後述)

## カメラ (マッパー 6 と GbCamera)
Game Boy Camera と同じレジスタにした。SameBoy (`Core/camera.c`) のカメラのエミュレーションと同じ手順で処理する
(SameBoy のコードは使っていない)。
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
| A036 | bit 0: カラー撮影 (この実装だけの拡張) |

- 撮影の指示から次のフレームが揃うのを待ち (最大 1 フレーム = 33 ms)、画素ごとに
  `(v × ゲイン × 露出) >> 20` → (輪郭強調) → しきい値で 4 階調にし、RAM バンク 0 の A100-AEFF に 16x14 タイルで書く
- 処理は 1 画素 1 クロック (輪郭強調ありは 5 クロック): 143 µs (輪郭強調ありは 717 µs)
- 撮影中は RAM の読み出しが 0、書き込みは捨てる。RAM の読み出しは RAM 有効にしなくてもできる (SameBoy と同じ)
- RAM は 32 KiB (バンク 0-3)。Game Boy Camera の 128 KiB は block RAM に入らない
  (このため、Game Boy Camera の ROM や 128 KiB 前提のソフトは動かない)
- 露出はカメラ側の自動露出のままで、A002-A003 はデジタルの係数として掛ける。カメラの露出は変えない
- 1 フレーム待っても次のフレームが来ないとき (カメラがない、止まっている) は約 0.1 秒で今のフレームのまま処理する

### カラー撮影 (GbColorQuant)
- A036 bit 0 を立てて撮影すると、色の量子化をする: タイル行ごとに 16 タイルの平均色を k-means で 4 群に分け、
  群ごとに輝度 4 段 (4x4 ベイヤーのディザ)、段ごとの平均色をパレットにする
- RAM バンク 0: 0xA100 タイル、0xAF00 BG 属性 (タイルごと、224 バイト)、0xB000 パレット (14 行 x 4 パレット x 4 色、RGB555 リトルエンディアン)
- 1 枚 1.4 ms。2 クロックに 1 回動く (中のレジスタ間は 2 サイクルのマルチサイクル制約、`timing.sdc`)
- GB 側 (`gb/src/screen.c`): 偶数行はパレット 0-3、奇数行は 4-7。タイル行の表示中に、その 8 本の走査線の HBlank (STAT 割り込み)
  で次の行の 4 パレットを空いている側に書く。新しい絵は VBlank ごとに 1 行ずつ (属性、DMA、パレット)
- 実機では VBlank に 2 行入れると中央付近のタイルが化けた (SameBoy では 2 行で画素単位一致、3 行で化け) ので 1 行にした。
  そのため 1 枚の書き換えに 14 フレームかかる

### カメラの画像 (IspGbScale)
- 1280x720 RAW10 (BGGR) の中央 768x672 を 6x6 画素ずつ、R / G / B を別に足して 128x112 にする
- 黒レベル (既定 16) を引く → ゲイン (8.8、既定 1.0) → 前のフレームのグレーワールドで白を合わせる → 8 区間の折れ線の sRGB 曲線
- 輝度 (8 ビット、白黒撮影用) と RGB565 (カラー撮影用) の 2 つをフレームバッファに書く
- 設計レジスタ (`HOST_UART=0` の版で `csictl.py` の 'X' / 'Y'): 0 黒レベル、1 ゲイン、2 {上下反転, 左右反転}、3 自動ホワイトバランス、
  4 / 5 白の係数 (R / B、自動でないとき)、0x10 フレーム数、0x11 / 0x12 使っている白の係数 (読み出しのみ)
- 画角は 1280x720 の中央を切り抜くので、元の画角の 60% (横) x 93% (縦)

### ホストから見る
```sh
./target/release/cart_emu game cam-status                                  # フレーム数、撮影数、レジスタ
./target/release/cart_emu game cam-frame -o frame.pgm [--rgb frame.bin]    # 128x112 の輝度 (PGM) と RGB565
```

## 資源とタイミング
Gowin 1.9.12.03、place_option 1 / route_option 2 (`HOST_UART=1` は 2026-11-26、`HOST_UART=0` は 2026-11-27):
| 資源 | HOST_UART=1 | HOST_UART=0 (USB pmod2) |
|---|---|---|
| ロジック | 15799 / 23040 (69%) | 16017 / 23040 (70%) |
| CLS | 92% | 92% |
| BSRAM | 54 / 56 | 54 / 56 |
| PLLA | 4 / 6 (100/200 MHz、USB 2 個、カメラ 500 MHz 4 相) | 同じ |
| PRIMARY クロック | 8 / 8 | 8 / 8 |

| クロック | 目標 | Fmax (HOST_UART=1) | Fmax (HOST_UART=0) |
|---|---|---|---|
| clk (GameCart、GbCamera) | 100 MHz | 100.0 MHz | 102.2 MHz |
| clk2 (QspiRom) | 200 MHz | 203.0 MHz | 213.9 MHz |
| pclk (カメラ) | 125 MHz | 125.6 MHz | 131.3 MHz |
| clk60 (USB) | 60 MHz | 60.5 MHz | 62.9 MHz |
| os_pclk (USB) | 120 MHz | — | 144.9 MHz |

- 余裕はどれも小さい。BSRAM の残りは 2、PRIMARY クロックは使い切った
- カート RAM の複製はやめた。ホストの RAM 読み出しは、本体のアドレスが 0xA000-0xBFFF にない間に本体側のポートで読む

## 試験
- `rtl/chromatic/test` (`PATH=~/.local/opt/verilator-5.054/bin:$PATH` などで Verilator 5.054 を使う):
  - `make camera`: GbCamera の撮影 6 通りとカラー撮影を `gb_camera_ref.py` / `gb_color_ref.py` とビット一致で照合
  - `make color`: GbColorQuant を `gb_color_ref.py` と照合 (`COLOR_IMAGES=` で写真も使える)
  - `make boot_cam`: カメラ版カートの起動と、GB バスからの撮影 (レジスタ、busy、撮影中の RAM、タイルの値)
  - `make boot` / `make unit`: 既存の試験 (CAMERA=0 で変化なし)
- `rtl/camera_isp/test/run_gb_scale.sh`: IspGbScale を合成した 1280x720 RAW10 で `gb_scale_ref.py` とビット一致で照合
  (2 フレーム。2 フレーム目は自動ホワイトバランスあり)
- `gb/`: `make shot` で SameBoy (カメラがないとノイズ画像) の画面を撮る。`make demo DEMO_IMAGE=photo.jpg` は、カメラなしで
  写真を `gb_color_ref.py` で量子化して埋め込んだ ROM

## 実機の結果 (2026-11-26)
- カメラ: csi_ctrl の ID 読み出しで 0x5640、128x112 のフレームが 29.7 fps で揃う
- Chromatic (公式ファーム) で `gbcam.gbc` が起動し、タイトル・撮影・アルバムが動く。カラーの色も出る。
  白黒の撮影 9621 回でタイムアウト 0、撮影 1 回 9〜15 ms (フレーム待ちを含む)
- カートの読み出しは遅れ 0 (ROMX 3936 万回)
- `HOST_UART=1` の版をフラッシュに書き、電源投入だけで起動することを確かめた (2026-11-27)
- cart_emu: Windows (USB) から `game status` が通る (エンドポイントの halt を開くときに解除する修正の後)

## 未確認・これから
- `HOST_UART=0` の版の、カラー対応後の実機での動作 (ビルドとタイミングは確認済み)
- 画像の向き (左右・上下) が実物と合っているか。合わなければ設計レジスタ 2 で直す
- 輪郭強調、反転、露出を大きく変えたときの見え方
- カラー表示の高速化 (HBlank DMA で見えない VRAM バンクに書き、VBlank で切り替える)
