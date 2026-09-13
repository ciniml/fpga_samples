# Manchester 低速制御リンク (Veryl)

AC 結合された差動ペア 1 本で、FPGA 内のバイトストリームを送受信する
ファミリ非依存コアのペアと、その上でトレース送信側を制御するフレーム層です。
EasyCDR トレースリンク (`eda/easycdr_trace`) の逆方向 (ホスト → トレース送信 FPGA)
チャネルとして設計しましたが、汎用の低速片方向リンクとして使えます。

```
 ホスト側 FPGA                                 トレース送信側 FPGA
 byte stream --> ManchesterTx --> (差動, AC結合) --> ManchesterRx --> CtrlFrameRx --> TraceCtrlRegs
```

## 符号 (ManchesterTx / ManchesterRx)

- 1 ビット = 2 ハーフビット (`BIT_CYCLES`/2 クロックずつ)。`1` = L→H、`0` = H→L
- アイドルは連続 `1` (ビットレートの方形波)。AC 結合でも DC に張り付かず、
  受信側は 4 ビット時間エッジが無ければ `o_link` を落とす
- 1 バイト = SYNC (H×3 + L×3 ハーフビット、データ/アイドルには現れない符号違反)
  + データ 8 ビット (LSB first) + 偶数パリティ = 12 ビット時間
- 受信はエッジ駆動: SYNC の立ち下がりを基準に、受理したミッドビット遷移から
  1.5 ハーフビット未満のエッジを境界エッジとして無視し、次のエッジ後のレベルをビット値とする。
  クロック復元不要、許容クロック偏差は約 ±25 %/ビット (SYNC→bit0 は ±12 %)。
  極性反転したリンクは SYNC 低区間チェックで全バイト拒否される (`o_err`)
- 最大ラン長 4 ハーフビット (パリティ 1 の後半 + SYNC 高区間) → AC 結合の
  時定数 (ExtEasyCDR: 100nF×10k ≈ 1ms) に対し 1〜5 Mbps で十分な余裕

## フレーム (CtrlFrameRx / TraceCtrlRegs)

固定 4 バイト: `[SOF 0xA5] [ADDR] [DATA] [CRC-8 poly 0x07, init 0, ADDR+DATA]`
= 1 レジスタへの 1 バイト書き込み。返信路は無いので read は無く、
CRC 不一致・回線エラー・(`GAP_TIMEOUT` > 0 なら) バイト間ギャップ超過で破棄 → ホストが再送。

| ADDR | レジスタ |
|---|---|
| 0x00 | CTRL: bit0 RESET (自己クリア) / bit1 ENABLE / bit2 DESC_REQ (パルス) / bit3 ARM (パルス、TX 側トリガをアーム) |
| 0x04.. | IGNORE_MASK (WIDTH ビット、LSB first、1 = 変化検出から除外) |
| 0x08 | MODE: bit0 PERIODIC (PERIOD 毎にレコード) / bit1 CHG_DIS (変化検出停止) |
| 0x09–0x0B | PERIOD (24bit、clk 単位) |
| 0x0C.. / 0x0C+MB.. | TRIG_MASK / TRIG_VALUE (ARM 後、(sig&MASK)==(VALUE&MASK) までレコード抑止) |
| 0x0C+2MB.. | POST (16bit: トリガ後に送るレコード数、0 = 無制限。到達後 (done) は再 ARM か RESET まで停止) |

TX 側状態はデスクリプタの flags (bit0 enable, bit1 armed, bit2 triggered, bit3 done, bit4 periodic)
に載り、25K のホストコマンド `F` で読める。

ホスト側 (ブラウザ) でのフレーム生成: `eda/easycdr_trace/host/web/index.html` の `ctrlFrame(addr, data)`。

## リソース (Gowin 1.9.12, GW1NR-9, BIT_CYCLES=50 = 100MHz/2Mbps, 実測)

| モジュール | LUT | ALU | FF |
|---|---|---|---|
| ManchesterTx | 36 | 5 | 11 |
| ManchesterRx | 55 | 7 | 42 |
| CtrlFrameRx (GAP_TIMEOUT=0 / 2000) | 46 / 54 | 8 / 18 | 32 / 43 |
| TraceCtrlRegs (WIDTH=16) | 15 | 0 | 23 |
| **受信側合計** (Rx+Frame+Regs) | **113 / 124** | 18 / 29 | 77 / 88 |

## テスト

```
veryl test            # Verilator。本体は test/*.sv (RUN=0 既定、#[test] から RUN=1 で実体化)
```

| テスト | 内容 |
|---|---|
| `manchester_same_clock` | 同一クロック、乱数 306 バイト+ランダムギャップ、リンク断/復帰、パリティ誤り注入、偽 SYNC 注入、最大ラン長 |
| `manchester_rx_fast/slow` (±1.5 %)、`_fast10/_slow10` (±10 %) | クロック偏差耐性 |
| `manchester_bit16` / `_bit100` | BIT_CYCLES 最小/低速構成 |
| `manchester_inverted` | 極性反転で 1 バイトも復号されないこと |
| `ctrl_frame_e2e` | 正常フレーム、CRC 誤り、ペイロード中の 0xA5、途中打ち切り→ギャップタイムアウト復帰、伝送中のバイト欠落、連続フレーム |

## 統合例

`eda/easycdr_trace` が実運用構成: 25K (`ManchesterTx` @50MHz/25=2Mbps, G7/G8) →
USB-C クロス → Nano9K (`TLVDS_IBUF` pin28/27 → `ManchesterRx` @99.9MHz/50 →
`CtrlFrameRx` → `TraceCtrlRegs` → `easycdr_trace_tx` の enable/mask/desc_req)。
E2E シミュレーションは `eda/easycdr_trace/test/e2e_ctrl_tb.sv`。**実機確認済み** (2026-09-13、
2 ボード: 25K pmod2 L1 = D10/D11 → USB-C → Nano9K pmod0 L0、CTRL_INVERT=1)。

## 注意

- `BIT_CYCLES` は受信側クロック基準で `送信側 BIT_CYCLES × f_rx/f_tx`。8 以上推奨
- 差動入出力バッファ (TLVDS_IBUF / ELVDS_OBUF 等) はユーザー側で接続。
  極性はツールのペア割当に依存するので、反転していたら `i_rxd` を `~` するか送信側で反転
- 識別子 `edge` / `buf` は SV 予約語なので Veryl でも使用不可
