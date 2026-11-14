# chromatic_cart_dump — Chromatic に挿したカートリッジの ROM を読み出す

ModRetro Chromatic の FPGA をカートリッジリーダーにするデザイン。FPGA が USB デバイス (full speed) になり、
ホストの `util/chromatic_cart_dump` (Rust) からのコマンドで、カートバスの 1 バイト読み出しと
MBC レジスタへの書き込みを行う。ヘッダの解析・MBC の判定・バンク切り替え・チェックサムの検証・保存はホスト側で行う。
ボード定義と書き込み・復旧手順は [`../targets/chromatic/README.md`](../targets/chromatic/README.md)。

```
USB-C ─ hub ─┬─ GWU2X (JTAG: make run / deploy)
             └─ FPGA SoftPHY pins ─ UsbPhy/UsbDevice (FS, EP1 byte stream, rtl/usb)
                                       │  60 MHz (CLK_24MHz → PLLA)
                                    CartCmd ─ CartBus ─ cartridge slot (rtl/chromatic)
                                       └─ CartPower (CART_PWR_EN / CART_CTRL_OE)
ESP32: held in reset (its firmware is not touched)
```

## 使い方

```sh
make                                  # build/chromatic/impl/pnr/chromatic_cart_dump.fs
make run                              # SRAM に一時書き込み (電源 OFF → ON で公式イメージに戻る)
cd ../../util/chromatic_cart_dump && cargo build --release
./target/release/chromatic_cart_dump status
./target/release/chromatic_cart_dump header
./target/release/chromatic_cart_dump dump --verify          # <タイトル>.gb / .gbc に保存
```

- 電源スイッチ ON、カートを挿してから `make run`。抜き差ししてもよい (抜くと電源要求は取り消され、次のコマンドで再投入)
- `dump` のオプション: `-o <file>`、`--verify` (2 回読んで比較)、`--mapper <mbc1|mbc2|mbc3|mbc5|mbc7|camera|huc1|huc3|none>`、
  `--banks <n>`、`--mbc1m`、`--force` (ヘッダチェックサム不一致でも続行 / 非対応マッパーはバンク 0-1 のみ)、`--keep-power`
- Linux では 1209:0001 へのアクセス権が要る。例: `SUBSYSTEM=="usb", ATTR{idVendor}=="1209", ATTR{idProduct}=="0001", MODE="0666"`
  (rtl/usb 系デザインと共通。GWU2X 33aa:0120 は openFPGALoader の udev ルールに含まれる)
- 速度はカートバスで決まる: 1 バイト = 1 バスサイクル (1 µs、GB の等速と同じ)。1 MiB で約 1 秒強 + USB のオーバーヘッド

## カートを壊さないための制限 (FPGA 側で強制)

`rtl/chromatic/cart_bus.veryl` がホストの指示に関係なく守る:

| 制限 | 内容 |
|---|---|
| /CS を出さない | カート RAM (0xA000-0xBFFF) は読みも書きもしない。セーブデータに一切アクセスしない |
| 書き込みは許可リストのみ | `0x0000 ← 0x00` (RAM/RTC 無効化)、`0x2000`、`0x2100` (MBC2)、`0x3000` (MBC5 bit 8)、`0x4000`、`0x6000`。それ以外は拒否してバスに出さない |
| RAM 有効化は不可 | 0x0000 には 0x00 しか書けない |
| フラッシュのコマンドは不可 | AMD 系のアンロック (0x0555/0x0AAA/0x2AAA/0x5555 への AA/55) のアドレスに書けない |
| 電源 OFF 中は全線 Low | 新基板では電源の切れたスロットに信号線から電流を流さない (`CartPower`) |

- 0x4000 への書き込みは MBC1 の上位ビット、MBC5 では RAM バンク (0 = ランブル OFF)。ホストツールは RAM バンクには 0 しか書かない
- 0x6000 は MBC1 の banking mode にだけ使う (MBC3 では RTC ラッチになるので書かない)

## 対応マッパー (ホストツール)

| マッパー | バンク切り替え |
|---|---|
| ROM only | なし |
| MBC1 | 0x2000 (下位 5 bit)、0x4000 (上位 2 bit)。0x20/0x40/0x60 は mode 1 で 0x0000 側に出して読む |
| MBC1M (マルチカート) | 1 MiB の MBC1 で、mode 1 / 上位 = 1 の 0x0104 にバンク 0 と同じロゴがあれば自動判別 (`--mbc1m` で強制) |
| MBC2 | 0x2100 (4 bit) |
| MBC3 / MBC30、MBC7、HuC1、HuC3、Pocket Camera | 0x2000 |
| MBC5 | 0x2000 (下位 8 bit)、0x3000 (bit 8) |
| MMM01、MBC6、TAMA5 | 非対応 (`--force` でバンク 0-1 のみ) |

検証:
1. 読み出し前: ヘッダを 3 回読んで一致すること、ヘッダチェックサム (0x14D)
2. 読み出し後: ダンプ内のヘッダが最初の読み出しと一致すること、グローバルチェックサム (0x14E-0x14F、不一致は警告のみ。正規品にも誤った値のものがある)、`--verify`
3. CRC32 / SHA-1 を表示 (既知のダンプ一覧と照合できる)

## プロトコル (EP1 OUT → IN、rtl/chromatic/cart_cmd.veryl)

| コマンド | 応答 |
|---|---|
| `'S'` | 8 バイト `'C' 'R' PROTO flags rst reject_cnt err 0` |
| `'P' on` | `'P' flags` (スロット電源の要求) |
| `'R' addr16 len16` | len バイト (len 0 = 65536) |
| `'W' addr16 data` | `'W' result` (0 完了 / 1 拒否 / 2 未準備) |

vendor request 0x01 (IN, 4 バイト) は `"GBCR"` を返す。ホストツールは 1209:0001 のうちこれを返すデバイスだけを使う。

## シミュレーション

```sh
cd ../../rtl/chromatic/test
make unit          # SV の単体テスト (状態、電源順序、MBC5 バンク、許可リスト外の書き込みがバスに出ないこと、抜去)
./run_e2e.sh       # ホストツール ⇔ Verilator モデル (stdin/stdout) で各マッパーのダンプをモデルの ROM とバイト比較
```

カートモデル (`gb_cart_model.sv`) は、/CS、許可リスト外の書き込み、RAM 有効化、データの衝突、電源 OFF 中の Low を監視する。

## 実機記録

- 2026-11-14: ビルド (Gowin 1.9.12.03、LUT 16%、clk60 Fmax 64.2 MHz / 60 MHz)、`make unit` と `run_e2e.sh` が全 PASS
  (ROM only 32 KiB、MBC1 512 KiB / 1 MiB / 2 MiB、MBC1M 1 MiB、MBC2 256 KiB、MBC3 2 MiB、MBC5 4 MiB、ヘッダ不正の拒否)。実機は未確認
- 2026-11-15 実機: `make run` (SRAM) だけで 1209:0001 が列挙した (フラッシュ起動は不要)。`CART_DET` = 1 が挿入、
  `VERSION_DET` = 0 で新基板と判定。MR.TETRIS (MBC5、256 KiB) を `dump --verify` で読み出し、2 回一致・ヘッダ/グローバル
  チェックサム OK、CRC32 a1378c6b、SHA-1 641bbad5bb19973a4a0935f0d422941e34d1b9b6、約 630 KiB/s (2 回読みで 0.9 s)
- 公式フラッシュのバックアップ (`make chromatic-backup`) も実機で取得: W25Q32、使用領域 0xDF754 バイト。
  フラッシュの読み出し時に openFPGALoader が SRAM を消すので、その後は画面が消えたままになる (電源 OFF → ON で戻る)
