# rtl/ddr2 — DDR2 SDRAM コントローラ (x16 1 個、Gowin IP 不使用)

DK_LED-RXCARD_GW3A-LV20UG324S (Arora III GW3A-20) の DDR2 (U46 W9725G6KB25I、
256 Mbit x16 = 32 MB) を、Gowin の暗号化 IP を使わず GW3A の公開 IOLOGIC
プリミティブ (OSER8 / IDES8 / IOBUF) で駆動する。riscv-veryl の DDR3
コントローラ (`Ddr3Ctrl` / `Ddr3PhyGw2a`、`rtl/ddr3` にコピーあり) と同じ
「スロットベクタ」方式の PHY 境界で、読出はサンプル履歴 + 自動キャリブレーション。

| ファイル | 内容 |
|---|---|
| `ddr2_ctrl.veryl` | `Ddr2Ctrl` — 初期化 (JEDEC、DLL リセット / OCD)、リフレッシュ、開いた行 1 本のコマンド FSM、書込パイプライン、読出キャプチャ + キャリブレーション |
| `ddr2_phy_gw3a.veryl` | `Ddr2PhyGw3a` — GW3A 用 PHY (OSER8 / IDES8 / IOBUF)。Gowin 合成専用 |
| `test/ddr2_model.sv` | Verilator 用 DDR2 振る舞いモデル (スロット単位、初期化・タイミング・DQS チェック付き) |
| `test/tb_ddr2.sv`, `test/Makefile` | 単体テスト (`make [CL=3..6]`) |

## DDR3 版との違い

* **DLL on**: DDR2 は通常動作で DLL off が使えないので CK ≥ 125 MHz (tCK ≤ 8 ns)。
  既定は pclk 83.3 MHz / CK 166.7 MHz (333 MT/s)、CL 4、WL = CL − 1 = 3、BL8、AL 0。
* **初期化**: CKE Low 200 µs → CKE High + 400 ns → PREA → EMR2 → EMR3 → EMR1 (DLL on)
  → MR (DLL リセット) → PREA → REF × 2 → MR → (DLL リセットから 200 CK) → EMR1 OCD
  デフォルト → OCD 終了 → キャリブレーション。RESET# / ZQ は無い。
* **開いた行 1 本**: 開いている行への要求は RD / WR を直接 2 pclk (= BL8 の 4 CK)
  毎に連続発行できる。行が違えば PREA → ACT。順次アクセスはバス幅いっぱい
  (シミュレーションで書込 615 MB/s、ピーク 667 MB/s の 92%) で流れる。
* **DM なし**: DK_LED-RXCARD は LDM / UDM が FPGA に繋がっていない
  ので、書込は常に 16 バイト (1 バースト) 単位。
* **ユーザポートは pclk ドメイン**: 内部にクロック乗換えはない (DDR3 版は CPU
  クロックとの CDC 込み)。

## ユーザポート (pclk)

* `i_req_valid` / `o_req_ready` / `i_req_we` / `i_req_addr` (バーストアドレス
  = バイトアドレス / 16) / `i_req_wdata` (128 bit、ビート b = バイト 2b, 2b+1)。
  `o_req_ready` は内部の要求レジスタが空のとき 1 (受付は最大 2 サイクルに 1 回)。
* `o_rd_valid` / `o_rd_data`: 読出データ。要求順、コマンドから固定時間後。
  背圧はない。
* アドレスマップ: col = addr[5:0]·8、bank = addr[7:6]、row = addr[20:8]
  (1 KB ページが 4 バンクを順に回る)。
* `o_init_done`、`o_cal_ok` / `o_cal_fail`、`o_rd_sel` / `o_rd_sel_odd` /
  `o_rd_lat` (キャリブレーション結果、状態表示用)。

## 書込タイミング

WR コマンドが PHY ポートに出る pclk を P とすると、P のスロット 2 で
サンプルされ、WL CK 後のスロット T0 = 2 + 4·WL に最初の DQS 立上り。DQS は
T0 − 2 から Low (プリアンブル)、ビート b は T0 + 2b のエッジを中心に 2 スロット、
ポストアンブルは T0 + 14, 15。連続書込では次のバーストのプリアンブルが前の
ポストアンブルに重なる。両者のパディングスロット (ビート 0 の前、ビート 7 の後) は
相手の実ビートに譲る。

## 読出キャプチャ / キャリブレーション

DDR3 版と同じ。DQS は使わず、DQ の 64 スロット履歴から RD_LAT − 1 サイクル後に
`RD_SEL + 2b` (偶数ビート) / `RD_SEL_ODD + 2(b−1)` (奇数ビート) を拾う。初期化の
最後にデバイス最終バーストへ固定パターンを書いて読み戻し、RD_LAT を
`CAL_LAT_MIN` から増やしながら全候補を比較して一致区間の中央を採る (偶奇別)。
失敗すると `o_cal_fail` を立てて既定値で動く。

## シミュレーション

```
cd test
make            # CL=4 (既定)、make CL=3 / CL=5 も可
```

モデルの読出遅延 0..7 スロット (と奇数ビートのずれ) 毎にリセットして、
初期化 + キャリブレーション → 4096 バーストの順次書込 → 順次読出 → ランダムな
読み書き 6000 回 (行ヒット / ミス、読み書きの切り替え、リフレッシュ跨ぎ) →
モデル内部のバイト配置を確認する。モデルはプロトコル違反を `$error` で止める
(`C_RCD` や `T0` を壊すと検出されることを確認済み)。

結果 (CL 4): 全遅延でキャリブレーション成功 (RD_LAT 8 / RD_SEL 42..47、遅延
6, 7 は RD_LAT 9)、不一致 0、モデルエラー 0、リフレッシュ約 104 回 / 実行。
CL 3 / 5 も PASS。

注意: モデルの出力ポートのカウンタは、テストベンチの `--timing` プロセスから
読むと古い値が見えることがある (Verilator)。そのためモデル自身が `report`
入力で集計を表示し、エラーがあれば `MODEL FAIL` を出す。Makefile はそれも見る。
