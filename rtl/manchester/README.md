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
| 0x00 | CTRL: bit0 RESET (自己クリア) / bit1 ENABLE / bit2 DESC_REQ (パルス) / bit3 ARM (パルス、TX 側トリガをアーム) / bit4 MAP_REQ (パルス、信号マップのテキストを送信) |
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

## リセット専用構成 (PulseResetTx / PulseResetRx)

レジスタが不要で「遠隔リセットだけ欲しい」ターゲット向けの最小構成。同じ AC 結合レーンを使う。

- 送信側: アイドル中は `IDLE_HALF` クロック毎に反転する方形波 (Manchester のアイドルと同じく
  AC 結合を中心に保つ)。`i_req` で `HALVES` 個の長いレベル (`HALF_CYCLES` クロック) を出し、
  方形波に戻る。`o_busy` 中に `o_txd` をマルチプレクスすれば ManchesterTx と同じ線を共有できる
  (25K は 'P' コマンドでこれを行う)
- 受信側: 「エッジで始まり `HALF_MIN`..`HALF_MAX` クロック続き、エッジで終わるレベル」を数え、
  `COUNT` 個連続で `o_reset` を `RESET_CYCLES` クロック保持 (バースト 1 回につき 1 回)。
  極性・コンパレータのアイドルオフセットに依存しない。Manchester のラン (最大 3 ハーフビット)、
  ノイズのチャタリング、単発ステップ (エッジ 1 個)、張り付き (エッジ無し) はすべて無視される
- **DC アイドルからのバーストは不可**: 長い静止レベルの後では AC 結合後の「戻り」エッジが振幅の
  HALF/τ (≈2 %) しか閾値から離れず、LVDS 受信器の閾値 (数十 mV) に埋もれる。シミュレーション
  (`pulse_ac_idle_high`) で 5 回中 1 回検出漏れとして再現し、アイドル方形波で解決した
- 既定値: 25K 側 50MHz で HALF_CYCLES=1000 (20µs) × 4、IDLE_HALF=25 (1MHz)。Nano9K 側 99.9MHz で
  HALF_MIN=1500 / HALF_MAX=3000 (15〜30µs)、COUNT=2

| モジュール | LUT | ALU | FF |
|---|---|---|---|
| PulseResetTx (25K, 1.9.12) | 20 | 9 | 16 |
| PulseResetRx (Nano9K, 1.9.12) | 36 | 11 | 26 |

Nano9K トレース送信側全体: Manchester 構成 LUT 535 / ALU 148 / FF 431 → リセット専用構成
LUT 232 / ALU 85 / FF 202 (`make CTRL_PULSE=1 TARGET=tangnano9k_pmod`)。制御チャネル 3 ブロックが
消える分に加え、レジスタ入力が定数化されてトレース TX 本体も LUT 281 → 93 / FF 210 → 138 に縮む
(トリガ・周期・無視マスクの論理が畳み込まれる)。**実機確認済み** (2026-09-13、25K 'P' → Nano9K タイムスタンプ再起動)。

## 受信器とフレーム構造の改良案 (未実装、2026-09-13 検討)

Manchester 構成の受信側 3 ブロックは LUT 143 / ALU 31 / FF 183 (Rx 53/7/42、CtrlFrameRx 53/24/48、
TraceCtrlRegs 37/0/93) で、符号化自体より**フレームとレジスタ**が大半。符号を変えても効果は薄い
(AC 結合で DC 成分を持つ NRZ/UART は使えず、DC バランス + 自己クロックの符号として Manchester は
最安の部類。パルス幅符号でも受信器はほぼ同規模、8b10b は大きくなる)。効くのは次の 2 つ:

1. **受信器を固定レートにする** (LUT 53 → 約 25、FF 42 → 約 20)。両側とも水晶なので周期計測
   (±10 % 許容) は不要。既知ボーレートで、ミッドビットエッジの方向でビットを決め、直前の採用エッジから
   0.75T 以内のエッジを境界エッジとして無視するだけの構造にする。SYNC は「1.5T 以上エッジ無し」で検出
2. **アドレス付き 4 バイトフレームをシフトチェーンにする** (Frame+Regs LUT 90 / ALU 24 / FF 141 →
   約 LUT 20 / ALU 8 / FF 110)。JTAG のスキャンチェーンのように全設定ビット (現在 93 bit) を 1 本の
   シフトレジスタとして先頭から流し、末尾の CRC-8 が一致したときだけシャドウへコミット。アドレス
   デコード、バイト組立、ADDR/DATA レジスタが消え、レジスタ本体はシフトレジスタが兼ねる。ARM /
   DESC_REQ のパルスはコミット時のビット立ち上がりから作る。代償: 毎回全設定を送り直す
   (13 バイト、2 Mbps で約 80µs) こと、部分更新ができないこと
3. (小) CRC-8 をフレーム 2 回送信 + 一致比較に置き換える: ALU 約 10 / LUT 約 15 減。1 と 2 に比べ効果小

1 + 2 で受信側 LUT 143 → 約 45、ALU 31 → 約 10、FF 183 → 約 130 (FF はレジスタ本体が残るので
それ以上は機能を削るしかない: PERIOD 24 bit、POST 16 bit、TRIG_MASK/VALUE)。
さらに最小がリセット専用構成 (上記 PulseResetRx)。

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
| `pulse_direct` / `_inverted` / `_ac_idle_low` / `_ac_idle_high` | リセットバースト 5 回 → 5 回検出 (保持幅 64)、単発ステップ・Manchester 通信・チャタリングは無視、Manchester アイドル直後のバースト。AC 結合 (τ=1ms) + コンパレータオフセット両極性のモデル |

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
