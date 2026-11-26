# cart_emu — FPGA カートアダプタ上の MBC5 カート (Tang Primer 25K、L4)

`gb_fpga_cart_de0` に挿した Tang Primer 25K を MBC5 カート (ROM 64 KiB、RAM 8 KiB) として動かし、本体の公式ファームに
起動させて、本物の CPU のタイミングでアダプタを確かめる (アダプタ試験の L4)。L0〜L2 は [`../cart_target`](../cart_target/)。
ピン・PLL・クロック制約は `cart_target` のものをそのまま使う。ホストは [`../../util/cart_emu`](../../util/cart_emu/)。

```sh
GW_SH=~/gowin/1.9.12.03/IDE/bin/gw_sh make && make run      # TP25K の SRAM へ
cd ../../util/cart_emu && cargo build --release
./target/release/cart_emu rom --logo-from <手持ちのカートのダンプ> -o l4_1x.gb   # --double で CGB 倍速版
./target/release/cart_emu load l4_1x.gb
./target/release/cart_emu clear                             # 読み込み中に暴走した本体のサイクルを消す
openFPGALoader --cable gwu2x -r                             # Chromatic をフラッシュの公式ファームで起動し直す (書き込みなし)
./target/release/cart_emu watch --rom l4_1x.gb --every 60
./target/release/cart_emu trace | less                      # 起動時の最初の 2048 サイクル
```

- `CartEmu` (`rtl/chromatic/cart_emu.veryl`): ROM/RAM は BSRAM (RAM はホストが動作中に読むための複製付き)、
  /RST Low で MBC レジスタを初期化、トレースは /RST の立ち上がりかブート ROM の最初の読み出し (0x0104) で開始
- 読み出しの数え方: 本体は読み出しの間 /RD を Low のままにするので、アドレスが 60 ns 以上安定した区間を 1 回とする。
  /CS はアドレスより大きく遅れて下がるので、区間中に一度でも Low なら RAM の読み出し。書き込みの直前の区間も読み出しに数える
- 試験 ROM (`util/cart_emu/src/rom.rs`、SM83 を手で組み立て): ROM バンク 0/1/2/3/0x100/0x102 の和を 0x4000-0x7FFF 経由で求めて
  イメージと比べ、0xA100-0xBFFF に書いたパターンを読み戻すのを繰り返す。結果はカート RAM (0xA000〜) に置き、背景を緑 (合格) /
  赤 (失敗) にする。ロゴ 48 バイトは手持ちのダンプから取る (リポジトリには入れない)

## 結果 (2026-11-15、Chromatic 新基板の公式ファーム、JP2 開放)

| 項目 | 結果 |
|---|---|
| 起動 | 公式ファームがロゴ (0x0104-0x0133) とヘッダを読み、0x0100 から実行。起動時 A=0x11 (CGB) |
| 等速 | PHI 1.049 MHz。5 分間で 278 周 (ROM 読み出し約 3.1 億回、RAM 読み出し 190 万回、MBC 書き込み 3105 回) 全合格 |
| 倍速 | KEY1=0xFE、PHI 2.097 MHz。5 分間で 486 周 (ROM 読み出し約 6.2 億回、RAM 読み出し 375 万回) 全合格 |
| RAM | ホストから読んだ 0xA100-0xBFFF が CPU の書いたパターンと一致 (等速・倍速とも) |
| 定常状態の数 | 1 周あたり MBC 書き込み 13 回・RAM 書き込み 12〜13 回・RAM 読み出し 7936 回で ROM の通り。RAM 無効中のアクセス 0 |

- 公式ファームはブート ROM のロゴ読み出しを 182 µs 間隔で行い、0x0143 (CGB フラグ) を何度か読んでから 0x0100 へ飛ぶ
- `openFPGALoader -r` での再起動ではカートの /RST は下がらなかった (トレースは 0x0104 の読み出しで始まる)
