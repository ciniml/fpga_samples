# chromatic_blink — ModRetro Chromatic テンプレート

Chromatic の FPGA デザインの雛形。基板の安全に関わるピンをすべて決まった状態にしたうえで、
状態 LED (RGB) を点滅させる。ボード定義と書き込み・復旧手順は [`../targets/chromatic/README.md`](../targets/chromatic/README.md)。

| 操作 | LED |
|---|---|
| 何も押さない | 緑が 1 Hz で点滅 |
| A / B / Start | 赤 / 青 / 緑 |
| Select | 白 |
| 十字キー 上 / 下 / 左 / 右 | シアン / マゼンタ / 黄 / 青 |
| Menu | 白の速い点滅 |

LED は電源スイッチ OFF (USB 給電だけ) のときは消える (`FPGA_LED_EN = ~POWER_ON_FPGA`)。

## ビルドと書き込み

```sh
make                 # 合成〜ビットストリーム (build/chromatic/impl/pnr/chromatic_blink.fs)
make chromatic-detect
make run             # SRAM に一時書き込み (電源 OFF → ON で公式イメージに戻る)
# フラッシュに残す場合 (先に make chromatic-backup で公式イメージを保存)
make deploy CONFIRM_FLASH=yes
```

`gw_sh` が PATH に無いときは `~/gowin/1.9.12.03/IDE/bin/gw_sh` を使う (`GW_SH=...` で変更可)。
ヘッドレス環境では `DISPLAY= QT_QPA_PLATFORM=offscreen make`。

## 構成

| ファイル | 内容 |
|---|---|
| `src/chromatic/top.sv` | ボードのピン一式と安全な既定値 (新しいデザインはここから始める) |
| `../../rtl/chromatic/cart_power.veryl` | `CartPower`: カート電源とシフタの順序制御 (新旧基板の判別つき)。このデザインでは電源を要求しない |
| `../../rtl/chromatic/chromatic_blink.veryl` | `ChromaticBlink`: ボタンのデバウンスと LED |
| `project.tcl` | `chromatic_cst` で top のポートだけを残した cst を作り、ビルドする |

このデザインの動作中、ESP32 はリセットのまま (メニューは出ない)。カートは挿していてもいなくてもよい
(電源は入れない)。

## 実機記録

- 2026-11-14: ビルドのみ確認 (Gowin 1.9.12.03、全ピンが意図どおりに配置されることを pin レポートで確認)。実機は未確認
- 2026-11-15: 実機で動作確認 (`make run`、SRAM)。無操作で緑 1 Hz 点滅、全ボタンの色が表どおり、電源 OFF → ON で公式イメージに戻る
