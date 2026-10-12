# SLogic16U3 ロジアナ ビルド済み位流

合成・配置配線済みで、タイミングを満たしたビルドです。フラッシュ用にしてあり、次の multiboot アドレスは
0x800000 (MODE を押すと DFU に戻る) です。書き込み手順は `../README.md` の「フラッシュへの書き込み」にあります。

| ファイル | 用途 |
|---|---|
| `slogic16u3_la.bin` | 公式 DFU ツールでフラッシュ 0x0 に書く |
| `slogic16u3_la.fs` | 同じ中身。JTAG の SRAM ロード (`gowin-prog sram`) 用で、DFU に入れなくなったときの復旧にも使う |
| `SHA256SUMS` | チェックサム |

## 出所

| 項目 | 内容 |
|---|---|
| ソース | コミット 672caf5 の rtl/la、rtl/usb3、eda/slogic16u3_la (位流を入れたコミットまで変更なし) |
| ビルド | `make PLACE_OPT=3 TAG=base` (Gowin EDA 1.9.12.03)。その後 `make PLACE_OPT=3 TAG=base dfu` (`host/mkdfu.py`) でヘッダの次 multiboot アドレスを 0x000000 → 0x800000 に書き換え |
| タイミング | pclk 125.129 MHz (制約 125)、sclk 104.262 MHz (制約 100)、TNS 0 |
| 資源 | ロジック 12124 / 15120 (81 %)、CLS 90 %、BSRAM 26 / 35 |
| USERCODE | 0x00004041 |
| USB | 1209:0001 "USB SS Sample" (USB 3.0、WinUSB 用 MS OS 2.0 記述子つき) |

2026-10-12 の実機確認:
- この `.bin` を公式 DFU ツールで 0x0 に書き、回読照合が通った。
- MODE でも挿し直しでもフラッシュから起動し、400 MB/s で取り込めた。
- MODE で DFU に戻った。

作り直すときは、タイミングが PnR 次第でぶれることに注意してください (`../README.md` の「ビルド」)。
