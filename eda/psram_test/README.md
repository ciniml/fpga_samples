# psram_test — GowinPsram (HyperRAM) ブリングアップテスト on Tang Nano 9K

`rtl/gowin_psram` の HyperRAM コントローラ `GowinPsram` を Tang Nano 9K の
内蔵 PSRAM (Winbond W955D8MBYA, 2 ダイ × 4MiB のうちダイ 0) で動かす
テストプロジェクト。Gowin の暗号化 PSRAM IP は使わず、ODDR/IDDR
プリミティブだけで HyperBus を直接駆動する (シミュレーション可能)。

- クロック: 27MHz → rPLL → 81MHz (`clkout`) と +90° の `clkoutp` (CK 用)
- PSRAM ポート (`O_psram_*` / `IO_psram_*`) は Gowin ツールが内部配線に
  割り当てる "マジックポート" なので CST には書かない
- UART: 115200 8N1、ボードの USB シリアル (FPGA pin 17)
- LED (負論理): [5] ハートビート [4:3] ck_delay [2] テスト実行中
  [1] 直前パスがエラーなし [0] コントローラ初期化完了

## テスト内容 (`PsramTest`, rtl/gowin_psram/psram_test.veryl)

`ck_delay` = 0, 1, 2 について順に、コントローラをリセット → ID0 / CR0 を
レジスタ読み出し → 1MiB をアドレス依存パターン (パス番号でシード) で
128 ワードバーストのライト → リードバック検証、を繰り返し 1 行ずつ出力:

```
ckd=0 id0=0c81 cr0=8fef err=00000000 first=000000 got=0000 exp=0000
ckd=1 id0=.... cr0=.... err=........ first=...... got=.... exp=....
ckd=2 ...
```

- `id0`: Winbond の ID レジスタ 0 (W955D8MBYA の値が読めていれば CA
  位相が合っている。シムモデルでは 0c81)
- `cr0`: 初期化で書き込んだ CR0 = `8fef` (レイテンシ 3、固定レイテンシ)
- `err`: ミスマッチ数 + 届かなかったワード数
- `first/got/exp`: 最初の不一致アドレス (ワード) と値

Gowin プリミティブのシミュレーションモデル通りなら `ckd=0` だけが
`err=00000000` になる。実機で別の値だけが通る場合はそれが正しい
`i_ck_delay` (CK ODDR と DQ ODDR のレイテンシ差)。どれも通らなければ
PLL の位相 (`PSDA_SEL`) を変えて試す。

## ビルドと書き込み

```console
$ make TARGET=tangnano9k GW_SH=~/gowin/1.9.10.03_edu/IDE/bin/gw_sh synthesis
$ make TARGET=tangnano9k run
$ picocom -b 115200 /dev/ttyUSB1      # or any terminal
```

リソース: Logic 14%、Fmax 81.7MHz @ 81MHz 制約 (タイミングクローズ済み)。

## シミュレーション

`rtl/gowin_psram` で `make test` (Gowin IDE の `prim_sim.v` から
ODDR/IDDR モデルを抽出して `veryl test` を実行)。テストは
`gowin_psram` (コントローラ単体)、`*_ckd_fast/slow` (RAM の tCKD 端)、
`psram_test_driver` (このテストドライバを UART デコード付きで一周)。
