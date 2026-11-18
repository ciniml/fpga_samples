# cart_game — FPGA カートアダプタ上のゲームカート (Tang Primer 25K)

`gb_fpga_cart_de0` に挿した Tang Primer 25K を、実際のゲームが動くカートにする。
- ROM バンク 0 (16 KiB) とカート RAM (最大 32 KiB) は BSRAM
- 切り替えバンク (0x4000-0x7FFF) は、アドレスが変わるたびにコア基板の SPI フラッシュから読む
- 対応マッパーは MBC1 / MBC3 (時計レジスタは 0 を返す) / MBC5、ROM は 4 MiB まで

ホストは [`../../util/cart_emu`](../../util/cart_emu/) の `game` サブコマンド。ピンは `cart_target` と同じで、フラッシュのピンを足している
(CS E6、CCLK E7、IO0-3 D6/E5/D5/E4、`use_mspi_as_gpio`)。

```sh
GW_SH=~/gowin/1.9.12.03/IDE/bin/gw_sh make && make run                          # TP25K の SRAM へ
cd ../../util/cart_emu && cargo build --release
./target/release/cart_emu game write game.gbc                                   # フラッシュ 0x400000 へ (違う 64 KiB ブロックだけ)
./target/release/cart_emu game start game.gbc --cont [--sav game.sav]           # マッパー設定、バンク 0・RAM 読み込み、較正、応答開始 (セーブを入れるとき)
openFPGALoader --cable gwu2x -r                                                 # Chromatic を公式ファームで起動し直す
./target/release/cart_emu game status | watch                                   # 遅れた読み出しの数、最も遅い読み出し
./target/release/cart_emu game save game.gbc -o game.sav                        # 電源を切る前にセーブを取り出す (BSRAM なので消える)
./target/release/cart_emu game stop                                             # フラッシュを単線モードに戻す
```

## USB 2.0 HS (Pmod USB HS Single)
UART と同じコマンド列を USB でも受け付ける。Pmod USB HS Single ([`../pmod_usb_hs/hw/Pmod_USB_HS_Single`](../pmod_usb_hs/))
を Dock の `USB_PMOD` (既定 `pmod1`) に挿し、`cart_emu` に `--usb` を付ける (`--tty` の代わり)。
- PHY は `eda/usb_device` の `USB_SL=1` と同じ (`usb_phy_gowin_sl`、PLL も共用)。コアは `rtl/usb` の `UsbDevice` で、EP1 を
  バイト列にする設定 (`EP1_STREAM`、短いパケットは 20 µs 途切れたら送る)
- 60 MHz の USB 側と 100 MHz の GameCart の間は `rtl/chromatic/byte_afifo.veryl` (レジスタで 16 段の非同期 FIFO) を往復 1 本ずつ
- `game` の各コマンドは単線モードに切り替えた直後に ID を 1 回空読みする。連続読み出しモードのまま FPGA の
  ロジックがリセットされると、最初の単線コマンドはモードを抜けるだけで FF を読むため (実機で一度発生)
- 返事は、最後にコマンドのバイトが来た側 (UART か USB) へ返す。両方から同時に送らないこと
- VID:PID は他の試作と同じ 1209:0001。ベンダリクエスト 0x01 の上位 2 バイトが "GC" のものを `cart_emu` が選ぶ
- 別のスロットなら `make USB_PMOD=pmod2` (ビルドディレクトリは `build/tangprimer25k_pmod2`)

実機 (2026-11-16、pmod1): HS (480M) で列挙。
- ワリオランド2 (2 MiB) の `game write` は消去 16 ブロック・8192 ページ・照合込みで 7.4 秒 (UART では 4 MiB で約 7 分)
- そのまま `--usb game start` で起動し、倍速で遅れ 0、最も遅い読み出し 190 ns
- トレース 16 KiB を 300 回読んで全部一致 (UART で読んだものとも一致)、32 KiB のセーブ取り出しは 0.06 秒

```sh
./target/release/cart_emu --usb game write game.gbc
./target/release/cart_emu --usb game start game.gbc --cont --sav game.sav
```

## 自動起動 (ホストなし)
リセット後、`GameCart` (`AUTO_BOOT=1`) が `game start --cont` と同じことを自分でする。セーブは入れない (RAM は FF)。
1. JEDEC ID を単線で 2 回読む (1 回目は、ロジックだけリセットされたときに残っている連続読み出しモードを抜けるため)。2 回目が `EF/0B xx 17` でなければ止まる
2. 0x400000 からバンク 0 (16 KiB) を単線で BSRAM に読む。ヘッダのカートタイプ (0147h)・ROM サイズ (0148h)・RAM サイズ (0149h) でマッパーとマスクを決め、
   ヘッダチェックサム (014Dh) が合わない、または対応外のマッパーなら応答しない (空のフラッシュでも同じ)
3. RAM を FF で埋め、SPI-Quad 連続読み出しモードにして、取り込みタイミング 0〜3 のそれぞれでバンク 0 全体を 4 本で読み、BSRAM と比べる。
   合格したものの真ん中 (`cart_emu` と同じ選び方) を使う
4. 次の /RST の立ち上がりでトレースを始めるようにして応答を始める

- シミュレーション (`rtl/chromatic/test`, `make boot`、フラッシュのモデルは出力遅延 7 ns) では 13 ms。タイミング 1, 2 が合格して 2 を選んだ。
  連続読み出しモードのままのリセット後の再起動、空のフラッシュで応答しないことも確かめた
- `game status` の `boot from the flash` に結果が出る。ホストからの `game start` (セーブを入れるとき) はこれまでどおり使える
- 実機 (2026-11-19): フラッシュから起動した FPGA が自分で始め (取り込みタイミング 2、ホストの較正と同じ)、スターオーシャン (4 MiB、MBC5) が本体で起動。
  ROMX 512 万回で遅れ 0、最も遅い読み出し 190 ns。連続読み出しモードのままのロジックのリセット (SRAM ロード) からも起動した
- 本体と同時に電源が入る場合、FPGA のフラッシュからのコンフィグ (約 0.9 MiB) と自動起動が本体の最初の読み出しに間に合うかは未確認

## 時間の予算
- 本体 (公式ファーム) がデータを取り込むまでの時間を `eda/cart_emu` の応答遅延で測った。
  同期後のアドレスから、等速は 500 ns まで合格 (600 ns で停止)、倍速は 230 ns まで合格 (240 ns で停止)
- フラッシュ (このボードは XTX `0B 40 17`、XT25F64B と思われる) は QPI (38h) に入らない (読むと 0xCC 一定)。
  そこで SPI-Quad (EBh、コマンドは単線、アドレスとデータは 4 本) を SCLK 100 MHz (200 MHz で生成) で使う
  - EBh 付き: 22 SCLK。最も遅い読み出し 270 ns で、等速なら十分だが倍速には足りない
  - 連続読み出しモード (M = A0h、`--cont`): 2 回目以降はアドレス 6 + M 2 + ダミー 4 + データ 2 = 14 SCLK。最も遅い読み出し 190 ns
- アドレスが変わったら読み出しを中断して読み直す。連続読み出しモードでアドレスの途中で中断しても、モードはそのまま保たれた
- データの取り込みは、SCLK の立ち下がりから何サンプル目 (5 ns 単位) で拾うかを較正する (`game start` が単線で読んだ値と比べる)。
  このボードでは 1 と 2 が合格で、2 を使う
- フラッシュの揮発ステータスレジスタに QE を立てる (50h → 31h 02h)。不揮発ビットには書かない
- 抜けるときは M = 0 で 1 回読む。初期化の最初には、全線 High で 16 クロックのモードリセットを送る。
  連続読み出しモードのまま FPGA をフラッシュから再コンフィグすると起動に失敗する恐れがあるので、`game stop` で抜けておくか電源を入れ直す

## 安全策
- ホストの単線 SPI (`F` コマンド) は FPGA が中身を見て通す。通すのは読み出し・ID・ステータスの読み出し・WREN/WRDI・リセット、
  それに 0x400000 以上へのページプログラムとセクタ/ブロック消去だけ。ステータスレジスタへの書き込みとチップ消去は通さない
  (先頭のビットストリームは消せない)
- 書き込み前の 0x400000-0x7FFFFF はすべて FF だった (バックアップは `~/chromatic-backups/tp25k_flash_4M-8M.bin`)
- ビットストリームをフラッシュに置くときは `openFPGALoader --board tangprimer25k --write-flash --unprotect-flash --verify build/tangprimer25k/impl/pnr/cart_game.fs`
  (使うのは先頭の約 0.9 MiB で、0x400000 以降の ROM は消えない)。電源投入後は下の自動起動でそのまま遊べる。
  2026-11-19 に書き込み、フラッシュから起動して USB で応答することを確認。元の先頭 4 MiB は `~/chromatic-backups/tp25k_flash_0-4M_20261119.bin`
  (戻すときは `openFPGALoader --board tangprimer25k --write-flash --unprotect-flash` にこのファイルを `.bin` として渡す)

## 結果 (2026-11-15)
| ゲーム | マッパー | 速度 | 結果 |
|---|---|---|---|
| ツインビーだ!! (128 KiB) | MBC1 | 等速 | 起動。ROMX 33 万回で遅れ 0、最も遅い読み出し 270 ns (EBh 付き) |
| ポケットモンスター 緑 (512 KiB、RAM 32 KiB) | MBC1 | 等速 | セーブを入れて起動。RAM の読み書きあり (バンク 0 の先頭 704 バイトは画像展開に使われる) |
| ゼルダの伝説 ふしぎの木の実 大地の章 (1 MiB、RAM 8 KiB) | MBC5 | 倍速 | 連続読み出しモードで、ROMX 1385 万回 (約 80 秒) で遅れ 0、最も遅い読み出し 190 ns。EBh 付きでは間に合わない |

- PHI は CPU が HALT している間止まるらしく、計測値は 0.1〜2.1 MHz で揺れる (Twinbee では 1.049 MHz のまま)
- 読み出しの数え方は `cart_emu` と同じ。「遅れ」は、アドレスの安定から 22 クロック (220 ns) 以内にデータが来なかった
  切り替えバンクの読み出しの数 (`game late N` で変更)
