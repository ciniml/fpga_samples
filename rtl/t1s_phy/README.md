# t1s_phy — PHY チップなしの 10BASE-T1S PHY コア (Veryl)

IEEE 802.3cg 10BASE-T1S の PMA (DME) / PCS (4B/5B、スクランブラ) / PLCA を FPGA のロジックで実装するコア。
基板は `eda/pmod_10base_t1s/hw/Pmod_10BASE_T1S` (比較器 2 個 + LVCMOS 2 本 + アナログスイッチ)、検討は `eda/pmod_10base_t1s/README.md`。

```
 MAC (MII ニブル、o_tx_req)  → T1sPcsTx: J J H H・スクランブル (x^17+x^14+1)・4B/5B・T + R/K → T1sPmaTx: DME → TX_P / TX_N / TX_EN
 比較器 H/L (SPC サンプル/クロック) → T1sPmaRx: ヒステリシス・区間 40/80 ns の分類 → T1sPcsRx: 5B 整列・逆スクランブル → MII ニブル
 T1sPlca: 送信開始の合図 (o_tx_go)、コーディネータのときは BEACON (N × 4)
 T1sPhy: 上記 + しきい値 PWM
```

- クロックは 1 系統。`HALF` = 40 ns のクロック数 (100 MHz で 4、150 MHz で 6)。受信は `SPC` サンプル/クロック
  (TP25K は IDES4 で 400 MS/s = 4)。PLL 型の CDR は無い (DME の区間は 2 種類だけで、区間ごとに測り直す)
- MAC はフレームを持ったまま `i_pending` を上げ、`o_tx_go` で TX_EN と最初のプリアンブルニブルを出し、以後 `o_tx_req` ごとに次のニブル。
  PLCA の論理衝突を MAC に返す代わりに、送信機会まで待たせる (MAC と PHY が同じ FPGA にあるため)
- 受信器は自分の送信も聞くので、そのフレームは `o_rx_own` で区別する

## 規格との対応と未確認事項

| 項目 | 実装 | 出典 / 状態 |
|---|---|---|
| 5B 記号 | J 11000 (SYNC)、H 00100 (SSD)、T 01101 (ESD)、R 00111 (ESDOK)、K 10001 (ESDERR)、N 01000 (BEACON) | D2.0 表 147–1、OA Sleep/Wake-up 仕様の表の差分 |
| 開始・終了 | J J H H (プリアンブル先頭 4 ニブルの置き換え)、T + R/K、その後 SILENCE で送信停止 | D2.0 147.3.2、OA PCS 試験 3.2.1 |
| スクランブラ | 自己同期、sd = d ^ s[13] ^ s[16]、データだけ | D2.0 147.3.2.5 (最終版は未読) |
| **5B のビット順** | `i_left_first` で選択 (表記の左端から / 右端から)。受信は `i_auto` で両方を探し、`o_order` に一致した方を出す | **未確認**。実機の相手 (EVB-LAN8670-USB-D) で決める |
| 受信の再同期 | SSD の後 5 シンボルは 0x5 を出す (逆スクランブラの 17 ビットが埋まるまで) | OA PCS 試験 3.3.1 は「4 シンボル」。MAC は SFD で同期するので影響なし |
| PLCA | BEACON = N × 4、TO タイマ (ビット時間)、コミットなしでフレームを直接開始、バーストなし | Clause 148 本文は未読。D0.3 の概要と OA PLCA 試験仕様 |
| ESDJAB、ESDBRS、WUP/スリープ | 未実装 | |

整列の注意: 10 ビット (2 シンボル) の窓では H H (00100 00100) が N N の回転と同じで、BEACON をフレーム開始と誤認する。
フレーム開始は J H H、BEACON は N N N の 15 ビットで判定する。J J と N N N は逆のビット順の列の中にも回転として現れるので、
ビット順の自動判定には J H H だけを使う。無信号のあとはシフトレジスタを消す (古いビットが偽の一致を作る)。

## テスト

`veryl test` (Verilator、8 本)。本体 `test/t1s_link_body.sv`、バスモデル `test/t1s_bus.sv`
(駆動中のノードの出力の和 → 一次遅れ → 比較器、0.25 ns 刻み)、MAC モデル `test/t1s_mac_model.sv`。

| テスト | 内容 |
|---|---|
| t1s_csma_2 | PLCA なし、2 ノードが交互に 6 フレーム、±100 ppm |
| t1s_plca_3 | PLCA、3 ノードが同時に 6 フレームずつ、物理衝突 0 |
| t1s_plca_ppm_big | ±1000 ppm |
| t1s_plca_isi | 立ち上がり τ 12 ns、振幅 0.3 倍、しきい値 ±50 mV、雑音 ±40 mV |
| t1s_plca_rl | 5B を右端から送る |
| t1s_plca_auto / t1s_plca_auto_lr | 受信がビット順を自動判定 |
| t1s_plca_to24 | TO タイマ 24 ビット時間 |

`veryl test` は `$display` を出さないので、中身を見るときは `test/run.sh <テスト名>` (Verilator を直接、`veryl build` の後)。
