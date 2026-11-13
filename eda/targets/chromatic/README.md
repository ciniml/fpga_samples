# ModRetro Chromatic ターゲット

ModRetro Chromatic (携帯型 GB/GBC 互換機) の FPGA を、fpga_samples の他のターゲットと同じ
`make` / `make run` / `make deploy` で扱うための定義です。

| 項目 | 内容 |
|---|---|
| FPGA | Gowin GW5A-25A、`GW5A-EV25UG256CC1/I0` (UBGA256)、device version A |
| ツール | Gowin 1.9.12.03 (公式デザイン v18.14 と同じ)。`gw_sh` が PATH に無ければ `~/gowin/1.9.12.03/IDE/bin/gw_sh` を使う |
| クロック | `CLK_FPGA` M2 = 33.554432 MHz (2^25 Hz、LVCMOS18)、`CLK_24MHz` D12、`CLK_27MHz` T2 |
| JTAG | USB-C の先のハブにある Gowin GWU2X 互換ブリッジ (33aa:0120)。`openFPGALoader --cable gwu2x` |
| MCU | ESP32 (メニュー/OSD/設定保存)。USB には直結しておらず、FPGA の UART/QSPI にだけつながる |
| USB | USB-C の D+/D- は FPGA の I/O (Gowin USB 2.0 SoftPHY の "single LVDS" 配線)。公式ファームの USB VID:PID は 374e:0101 |

## ファイル

| ファイル | 内容 |
|---|---|
| `target.mk` | デバイス、ケーブル、`make deploy` の安全策 |
| `rules.mk` | `chromatic-detect` / `chromatic-backup` / `chromatic-restore` / `chromatic-flash-check` |
| `chromatic.cst` | 全ピンの定義 (下記の出典参照) |
| `chromatic_cst.tcl` | `chromatic_cst <top> <out.cst>`: top のポートだけを残した cst を作る (Gowin は未定義ポートの制約をエラー CT1135 にする) |
| `chromatic_flash.sh` | フラッシュのバックアップ・リストア・書き込み前チェック |

## 書き込み

**電源スイッチを ON にして** USB-C で接続する (OFF だと JTAG から FPGA が見えない)。

| 操作 | コマンド | 元に戻す方法 |
|---|---|---|
| 接続確認 | `make chromatic-detect` | ― |
| SRAM に一時書き込み | `make run` (`openFPGALoader --cable gwu2x --write-sram`) | 電源スイッチを OFF → ON。フラッシュの公式イメージが起動する |
| フラッシュのバックアップ | `make chromatic-backup` | ― |
| フラッシュに書き込み | `make deploy CONFIRM_FLASH=yes` | 下記「公式ファームに戻す」 |

- 実験は必ず `make run` (SRAM) で行う。電源を切れば元に戻る
- `make deploy` は次を満たさないと書き込まない (`chromatic-flash-check`):
  `CONFIRM_FLASH=yes`、`~/chromatic-backups/chromatic_flash_*.bin` がある、ビットストリームの品番が一致する、FPGA を検出できる
- `make chromatic-backup` はフラッシュ先頭 1 MiB (`CHROMATIC_FLASH_DUMP_SIZE`、公式イメージは約 0xE0000 B) を
  2 回読み、一致したときだけ保存する。**最初の 1 回 (公式イメージ) は必ず残しておくこと**

### 公式ファームに戻す

1. バックアップから: `make chromatic-restore BACKUP=~/chromatic-backups/chromatic_flash_<日時>.bin CONFIRM_FLASH=yes`
   (`openFPGALoader --cable gwu2x --write-flash --file-type bin --verify --reset <file>`)
2. バックアップが無い / 壊れた場合: ModRetro 公式アップデータ (MRUpdater、https://modretro.com/pages/downloads) で
   最新の公式 FPGA イメージを書き込む

GW5A の JTAG はフラッシュの内容に関係なく使えるので、書き込みに失敗してもやり直せる。
ESP32 のフラッシュはこのターゲットのどの操作でも触らない。

## カスタムデザインの約束事

未使用ピンはデバイスの既定で「弱プルアップ付き入力」になる。次のピン (`chromatic.cst` で `[S]`) は
必ずポートとして宣言して状態を決めること (`eda/chromatic_blink/src/chromatic/top.sv` が雛形)。

| ピン | 値 | 理由 |
|---|---|---|
| `CART_PWR_EN` / `CART_CTRL_OE` | 0 (使うときは `CartPower` で順序制御) | カート電源とシフタ |
| `CART_A/D/CLK/RD/WR/CS/RST/DATA_DIR_E` | 新基板で電源 OFF 中は Low | 電源の無いカートへ信号線から電流を流さない |
| `ESP32_EN` / `ESP32_IO0` | 0 / 1 | ESP32 をリセットのまま止める (公式デザインは 1/1 で起動させる) |
| `AUD_RESET`、`LCD_PWM`、`LCD_RESET`、`IR_LED` | 0 | コーデック、バックライト、IR LED を止める |
| `CHG_EN_FPGA`、`SDIO_LS` | 1 | 公式デザインと同じ (充電有効) |
| `POWER_DOWN_IO` | Hi-Z | 公式デザインと同じ |
| `usb_*` | 入力 / Hi-Z、`usb_pullup_en_o` = 0 | 未宣言だと弱プルアップで D+/D- が持ち上がる |
| `LINK_*_DIR_LV` | 0 | リンクポートのシフタをコネクタ → FPGA 向きに |

- `VERSION_DET` (M8): 新基板は Low。High の旧基板ではカート電源がスイッチ連動で FPGA から切れない
  (`rtl/chromatic/cart_power.veryl` の `o_legacy`)
- `POWER_ON_FPGA` (N8) = 1 は「スイッチ OFF で USB 給電中」。この間カートを動かさないこと
- 充電器 (BQ24296) は I2C を触らなければ既定値で動く

## ピン定義の出典とライセンス

`chromatic.cst` のボール割り当て・I/O 規格・プル設定は
[ModRetro/oss-chromatic-console-fpga](https://github.com/ModRetro/oss-chromatic-console-fpga) v18.14
(commit a01aa37) の `esp32t/src/board/evt1_x2/evt1_x2.cst` (GPL-3.0) から取った。
v18.5 (ModRetro/chromatic_fpga) の cst には `CART_PWR_EN` / `CART_CTRL_OE` / `VERSION_DET` / `CHG_EN_FPGA` などが無く、
新しい基板ではカートに電源が入らないため、v18.14 を出典にしている。

持ってきたのは基板の物理的な事実 (どのボールにどの信号がつながっているか) だけで、ファイルは独自に書き起こした
(並び・グループ・コメントは独自。ネット名は照合しやすいよう公式と同じ)。公式の RTL・LCD 初期化データ等は
一切流用していない。ほかのファイルと同じく BSL-1.0 で配布するが、ピン配置の情報としての出典は上記である。
