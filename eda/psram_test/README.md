# psram_test — GowinPsram (HyperRAM) ブリングアップテスト on Tang Nano 9K

`rtl/gowin_psram` の HyperRAM コントローラ `GowinPsram` を Tang Nano 9K の
内蔵 PSRAM (Winbond W955D8MBYA, 2 ダイ × 4MiB のうちダイ 0) で動かす
テストプロジェクト。Gowin の暗号化 PSRAM IP は使わず、ODDR/IDDR
プリミティブだけで HyperBus を直接駆動する (シミュレーション可能)。

- クロック: 27MHz → rPLL → 81MHz (`clkout`) と +90° の `clkoutp` (CK 用)
- PSRAM ポート (`O_psram_*` / `IO_psram_*`) は Gowin ツールが内部配線に
  割り当てる "マジックポート" なので CST には書かない
- UART: 115200 8N1、ボードの USB シリアル (FPGA pin 17)
- LED (負論理): [5] ハートビート [4:3] バースト長 (0:16 1:32 2:64) [2] テスト実行中
  [1] 直前パスがエラーなし [0] コントローラ初期化完了

## テスト内容 (`PsramTest`, rtl/gowin_psram/psram_test.veryl)

バースト長 16 / 32 / 64 ワードについて順に、コントローラをリセット →
ID0 / CR0 をレジスタ読み出し → 1MiB をアドレス依存パターン (パス番号で
シード) でライト → リードバック検証、を繰り返し 1 行ずつ出力:

```
bl=016 id0=005f cr0=8fec err=00000000 first=000000 got=0000 exp=0000
bl=032 id0=005f cr0=8fec err=00000000 first=000000 got=0000 exp=0000
bl=064 id0=005f cr0=8fec err=00000000 first=000000 got=0000 exp=0000
```

- `id0`: ID レジスタ 0 (Tang Nano 9K のダイは 005f を返す。シムモデルは 0c81)
- `cr0`: 初期化で書き込んだ CR0 = `8fec` (レイテンシ 3、固定レイテンシ、
  ラップ長 128B。bit2 は書けず 1 に読み戻る)
- `err`: ミスマッチ数 + 届かなかったワード数
- `first/got/exp`: 最初の不一致アドレス (ワード) と値

## 実機結果 (2026-09-06)

上記 3 行が `err=00000000` で連続動作 (数十周確認)。ブリングアップで
判明したチップの挙動 (rtl/gowin_psram の設計メモにも記載):

- CK と DQ/CS# の ODDR レイテンシ差はプリミティブモデル通り (ck_delay=0)
- 固定レイテンシのデータ開始は CA の 3 クロック目から数えて 2×レイテンシ
  (モデルの当初の仮定より 2 CK 遅い)
- リニアバースト指定 (CA[45]=1) でも CR0 のバースト長で折り返す。128B
  設定にして「128B 境界をまたがない ≤64 ワードのバースト」で運用

## ビルドと書き込み

```console
$ make TARGET=tangnano9k GW_SH=~/gowin/1.9.10.03_edu/IDE/bin/gw_sh synthesis
$ make TARGET=tangnano9k run
$ picocom -b 115200 /dev/ttyUSB2      # FT2232 の 2 番目のポート (環境により番号は変わる)
```

リソース: Logic 14%、Fmax 81.6MHz @ 81MHz 制約 (タイミングクローズ済み)。
書き込みには 2 枚のボードを取り違えないよう `openFPGALoader --busdev-num`
で GW1NR-9 のケーブルを指定するのが安全 (`openFPGALoader --scan-usb` と
`--detect` で確認)。

## シミュレーション

`rtl/gowin_psram` で `make test` (Gowin IDE の `prim_sim.v` から
ODDR/IDDR モデルを抽出して `veryl test` を実行)。テストは
`gowin_psram` (コントローラ単体)、`*_ckd_fast/slow` (RAM の tCKD 端)、
`psram_test_driver` (このテストドライバを UART デコード付きで一周)。
