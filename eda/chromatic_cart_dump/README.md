# chromatic_cart_dump — Chromatic に挿したカートリッジの ROM とセーブデータを読み出す

ModRetro Chromatic の FPGA をカートリッジリーダーにするデザイン。FPGA が USB デバイス (full speed) になり、
ホストの `util/chromatic_cart_dump` (Rust) からのコマンドで、カートバスの 1 バイト読み出しと
MBC レジスタへの書き込みを行う。ヘッダの解析・MBC の判定・バンク切り替え・チェックサムの検証・保存はホスト側で行う。
セーブデータ (カート RAM) は読み出しのみで、書き戻しの機能はない。
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
./target/release/chromatic_cart_dump save                    # セーブデータ: 2 回読んで一致したら <タイトル>.sav に保存
```

- 電源スイッチ ON、カートを挿してから `make run`。抜き差ししてもよい (抜くと電源要求は取り消され、次のコマンドで再投入)
- `dump` のオプション: `-o <file>`、`--verify` (2 回読んで比較)、`--mapper <mbc1|mbc2|mbc3|mbc5|mbc7|camera|huc1|huc3|none>`、
  `--banks <n>`、`--mbc1m`、`--force` (ヘッダチェックサム不一致でも続行 / 非対応マッパーはバンク 0-1 のみ)、`--keep-power`
- Linux では 1209:0001 へのアクセス権が要る。例: `SUBSYSTEM=="usb", ATTR{idVendor}=="1209", ATTR{idProduct}=="0001", MODE="0666"`
  (rtl/usb 系デザインと共通。GWU2X 33aa:0120 は openFPGALoader の udev ルールに含まれる)
- `save` のオプション: `-o <file>`、`--mapper <mbc1|mbc2|mbc3|mbc5>`、`--force` (ヘッダチェックサム不一致でも続行)、`--keep-power`
- 速度はカートバスで決まる: 1 バイト = 1 バスサイクル (1 µs、GB の等速と同じ)。1 MiB で約 1 秒強 + USB のオーバーヘッド

## カートを壊さないための制限 (FPGA 側で強制)

`rtl/chromatic/cart_bus.veryl` がホストの指示に関係なく守る:

| 制限 | 内容 |
|---|---|
| 書き込みは許可リストのみ | `0x0000 ← 0x00` (RAM/RTC 無効化)、`0x0000 ← 0x0A` (RAM 有効化、RAM モード中のみ)、`0x2000`、`0x2100` (MBC2)、`0x3000` (MBC5 bit 8)、`0x4000 ← 0x00-0x0F`、`0x6000`。それ以外は拒否してバスに出さない |
| カート RAM には書けない | 0xA000-0xBFFF は許可リストにない。/CS は読み出しの /RD と一緒にだけ出し、/WR とは決して重ねない |
| /CS は RAM モード中の読み出しだけ | ホストが `'A' 1` で RAM モードにしたときだけ、0xA000-0xBFFF の読み出しで /CS を出す。RAM モードが切れたら進行中のサイクルでも /CS を即座に戻す |
| RAM は FPGA が自分で無効に戻す | RAM モードが切れると、他の要求より先に `0x0000 ← 0x00` を自分で出す。RAM モードが切れる条件: `'A' 0`、電源要求の取り消し、CART_DET が落ちる (デバウンスなし)、USB 切断 (configured が落ちる)、1 秒間コマンドなし |
| RAM 有効中は電源を切らない | 無効化が済むまでスロット電源を保持する (`'P' 0` やスイッチ OFF でも、無効化が先) |
| 特殊モードに入らない | 0x0000 には 0x00 / 0x0A しか書けないので HuC1/HuC3 の赤外線モードなどに入らない。0x4000 は 0x0F までなので Pocket Camera のレジスタ (0x10) や MBC7 の EEPROM 選択 (0x40) も出せない |
| フラッシュのコマンドは不可 | AMD 系のアンロック (0x0555/0x0AAA/0x2AAA/0x5555 への AA/55) のアドレスに書けない |
| 電源 OFF 中は全線 Low | 新基板では電源の切れたスロットに信号線から電流を流さない (`CartPower`) |

- 0x4000 への書き込みは MBC1 の上位ビット / RAM バンク、MBC3・MBC5 では RAM バンク
- 0x6000 は MBC1 の banking mode にだけ使う (MBC3 では RTC ラッチになるので書かない)
- 残るリスク: RAM を有効にしている間 (32 KiB で 2 回読み約 0.1 s) にカートを抜くと、カート側の電源断グリッチは防げない

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

セーブデータ (`save`):

| マッパー | RAM | 読み方 |
|---|---|---|
| MBC1 | 2 / 8 / 32 KiB | 32 KiB は mode 1 + 0x4000 で 4 バンク (512 KiB 超の ROM では 1 バンクのみ) |
| MBC2 | 512 × 4 bit (MBC 内蔵) | 下位 4 bit を読み、上位 4 bit は 1 にして保存 (バスに出ないので値が定まらない) |
| MBC3 / MBC30 | 8-64 KiB | 0x4000 ← 0-7 (RTC レジスタ 0x08-0x0C は選ばない) |
| MBC5 | 8-128 KiB | 0x4000 ← 0-15 (ランブル付きは bit 3 がモーターなので 8 バンクまで) |
| それ以外 (MBC7 の EEPROM、HuC1/HuC3、Pocket Camera、TAMA5 など) | — | 非対応 (拒否) |

手順: RAM モード → `0x0000 ← 0x0A` → バンクごとに 0xA000 から読む → `0x0000 ← 0x00` → RAM モード解除、を 2 回行い、
一致しなければエラー。全部 0xFF なら警告 (空、RAM なし、電池切れ)。

検証:
1. 読み出し前: ヘッダを 3 回読んで一致すること、ヘッダチェックサム (0x14D)
2. 読み出し後: ダンプ内のヘッダが最初の読み出しと一致すること、グローバルチェックサム (0x14E-0x14F、不一致は警告のみ。正規品にも誤った値のものがある)、`--verify`
3. CRC32 / SHA-1 を表示 (既知のダンプ一覧と照合できる)

## プロトコル (EP1 OUT → IN、rtl/chromatic/cart_cmd.veryl)

| コマンド | 応答 |
|---|---|
| `'S'` | 8 バイト `'C' 'R' PROTO flags rst reject_cnt err ram` (PROTO = 2、flags bit 7 = RAM モード、ram bit 0 = RAM 有効中) |
| `'P' on` | `'P' flags` (スロット電源の要求) |
| `'R' addr16 len16` | len バイト (len 0 = 65536) |
| `'W' addr16 data` | `'W' result` (0 完了 / 1 拒否 / 2 未準備) |
| `'A' on` | `'A' flags` (RAM モード。電源要求中のみ許可、bit 7 が結果) |

vendor request 0x01 (IN, 4 バイト) は `"GBCR"` を返す。ホストツールは 1209:0001 のうちこれを返すデバイスだけを使う。

## シミュレーション

```sh
cd ../../rtl/chromatic/test
make unit          # SV の単体テスト (状態、電源順序、MBC5 バンク、許可リスト外の書き込みがバスに出ないこと、
                   # RAM モード: 読み出し、モード外の有効化拒否、'A' 0 / ウォッチドッグ / USB 切断 / 抜去での自動無効化、抜去)
./run_e2e.sh       # ホストツール ⇔ Verilator モデル (stdin/stdout) で各マッパーのダンプとセーブを
                   # モデルの ROM / RAM とバイト比較
```

カートモデル (`gb_cart_model.sv`) は、許可リスト外の書き込み、/CS と /WR の重なり、/RD なしの /CS、0xA000-0xBFFF 以外での /CS、
RAM モード外の RAM 有効化、RAM 有効のままの電源断、データの衝突、電源 OFF 中の Low を監視する。

## 実機記録

- 2026-11-14: ビルド (Gowin 1.9.12.03、LUT 16%、clk60 Fmax 64.2 MHz / 60 MHz)、`make unit` と `run_e2e.sh` が全 PASS
  (ROM only 32 KiB、MBC1 512 KiB / 1 MiB / 2 MiB、MBC1M 1 MiB、MBC2 256 KiB、MBC3 2 MiB、MBC5 4 MiB、ヘッダ不正の拒否)。実機は未確認
- 2026-11-15 実機: `make run` (SRAM) だけで 1209:0001 が列挙した (フラッシュ起動は不要)。`CART_DET` = 1 が挿入、
  `VERSION_DET` = 0 で新基板と判定。MR.TETRIS (MBC5、256 KiB) を `dump --verify` で読み出し、2 回一致・ヘッダ/グローバル
  チェックサム OK、CRC32 a1378c6b、SHA-1 641bbad5bb19973a4a0935f0d422941e34d1b9b6、約 630 KiB/s (2 回読みで 0.9 s)
- 2026-11-15 実機: MINI4WD GB (MBC1、512 KiB、SGB) も `dump --verify` で 2 回一致・ヘッダ/グローバルチェックサム OK、CRC32 fc0c180b、SHA-1 a51dc3ea1961297a3056e0326c8a153f496dae8a
- 2026-11-15 実機: MINI4WD GB2 (MBC3、1 MiB、RTC なし) も `dump --verify` で 2 回一致・ヘッダ/グローバルチェックサム OK、CRC32 97ebd21d、SHA-1 ca662cb506b553f1730c29c088e597bace1e0052。カートの抜き差しはデザインを載せたままでよい
- 2026-11-15 実機: STAROCEANGBBO2J (MBC5、4 MiB / 256 バンク) も `dump --verify` で 2 回一致・ヘッダ/グローバルチェックサム OK、CRC32 8c7ddbda、SHA-1 3d07ae53ba21eda4923bf4da6c938e2a407c990c、2 回読みで 9.1 s。bank 8 bit 全域 (0x3000 の bit 8 は 8 MiB カートでないと使わないので未確認)
- 2026-11-15: セーブデータの読み出しを追加。`make unit`、`run_e2e.sh` 17 ケース全 PASS (セーブ: MBC1 8 / 32 KiB、MBC2、
  MBC3 32 / 64 KiB、MBC5 128 KiB、RAM なしと ROM only の拒否)。自動無効化を外した変異版では単体テストが 6 件失敗することも確認。
  ビルド: LUT 16%、clk60 Fmax 65.1 MHz。gw_sh が X に繋げないシェルでは `QT_QPA_PLATFORM=offscreen make`
- 2026-11-15 実機: MINI4WD GB2 (MBC3、RAM 32 KiB、電池あり) のセーブを `save` で読み出し、2 回一致 (2 回で 0.07 s)、
  CRC32 101e55b1、SHA-1 ff0bb1bfc446dcc835e70880b5caef4ef959ecc0。バンク 0 / 1 / 2 は互いに異なり、2 と 3 は同一
  (ゲーム側の予備コピーか、バンク選択の不具合かは未確定。1 ビットの固着なら 0 = 1 にもなるはずなので前者と見ている)
- 公式フラッシュのバックアップ (`make chromatic-backup`) も実機で取得: W25Q32、使用領域 0xDF754 バイト。
  フラッシュの読み出し時に openFPGALoader が SRAM を消すので、その後は画面が消えたままになる (電源 OFF → ON で戻る)
