# Pmod 10BASE-T1S 直結 PHY 基板 — 実現性の検討

外付けの PHY チップ (LAN8670、NCN26000 など) を使わずに、GOWIN FPGA (Tang Primer 25K / Tang Nano 9K) の
ロジックで 10BASE-T1S (IEEE 802.3cg、Clause 147 / 148) の PCS・PMA・PLCA を実装し、Pmod 基板には
汎用部品 (抵抗、コンデンサ、コモンモードチョーク、アナログスイッチ、ESD) だけを載せる案の検討。

状態: **机上検討のみ** (2026-11-20)。回路・RTL・基板は未着手。数値の根拠は `tools/calc.py`。

## 0. 結論 (要約)

| 項目 | 判定 | 要点 |
|---|---|---|
| 送信振幅 1 Vpp ±20% | ◎ | LVCMOS33 2 本 + 直列抵抗 (片側 約 140 Ω) で 0.90〜1.08 Vpp (VCCIO ±5%、ピン抵抗 15〜30 Ω) |
| 送信停止 (high-Z) | ○ | FPGA のトライステートだけでも可。立ち上がりを規格どおりに鈍らせる RC を隠すため、**アナログスイッチ (TMUX1511) で切り離す** |
| 立ち上がり 7.5〜15 ns (OA) | ○ | スイッチの FPGA 側に C (220 pF) を置けば約 10 ns。スイッチなしだと 1〜2 ns (機能は動くが EMC 上は規格外) |
| 休止中のインピーダンス (10 kΩ‖25 pF 以上) | ○ (要実測) | 推定: 差動 18 kΩ / 18 pF で 0.3〜40 MHz とも下限の約 1.4 倍。FPGA のピン容量は推定値 |
| 受信 (0 V 判定 + エネルギー検出) | ◎ | LVDS 入力 2 組を比較器として使い、±th のヒステリシス比較器を作る (100BASE-TX 基板と同じ手法) |
| CDR / DME 復号 | ◎ | 12.5 MBd は遅い。200 MS/s (IDDR) で「区間 40 ns / 80 ns」を判定するだけ。PLL も SERDES も不要。Nano 9K でも可 |
| PCS (4B/5B、スクランブラ)、PLCA | ◎ | 状態機械のみ。MAC も FPGA 内なので、PLCA を MAC に直接組み込める |
| EMC 適合、8 ノード 25 m | △ | 測定していないので保証しない。まず 2〜3 ノード・10 m 程度を目標にし、容量と波形を測ってから広げる |
| PoDL | × | 対象外 (マルチドロップの PoDL は 802.3cg に無い。802.3da-2026 で追加) |

**実現できる見込みは高い。** 100BASE-TX 直結 PHY (`eda/pmod_100base_tx`、2026-11-15 に実機で 100M 全二重リンク・誤り 0) と比べると、
信号は 1/10 の速さで、2 値で、DC バランスがとれている (DME)。いちばんの難所は受信ではなく、**送信の「振幅・立ち上がり・high-Z」を
同時に満たすこと**と、**休止中にバスへ載せる容量を 25 pF 以内に抑えること**。前者はアナログスイッチ 1 個で解決できる。

いちばんのリスクは、ループバックでは見つからない**相互接続上の約束事** (5B の送出ビット順、スクランブラのタップとビット順、
SYNC/SSD の数、PLCA のタイミング)。本書の PCS の記述は 802.3cg のドラフトと OPEN Alliance の試験仕様から組み立てたもので、
**最終版の規格本文 (IEEE 802.3-2022 Clause 147/148) では未確認**。実機の初手は「市販 PHY の送信を受信だけで復号する」(§7.2)。

## 1. 10BASE-T1S の物理層の要件

### 1.1 全体

| 項目 | 内容 | 出典 |
|---|---|---|
| 伝送路 | 非シールドより対線 1 対 (UTP)。マルチドロップ (半二重、混在セグメント) と、オプションのポイントツーポイント (全二重/半二重) | [D0.3] 147.1、[OA-PMD] |
| 到達距離 | マルチドロップ: 25 m 以上、8 ノード以上 (OA の試験用チャネル例は 8 ノード・スタブ 0.1 m)。ポイントツーポイント: 15 m 以上、インライン コネクタ 4 個まで | [D0.3]、[OA-SYS] 7.3 |
| 符号化 | 4B/5B → DME (Differential Manchester Encoding、2 値) | [D0.3] 147.1 |
| ボーレート | 12.5 MBd (5B 符号のビットレート)。1 ビット 80 ns、半ビット 40 ns。MII は 10 Mb/s (ニブル 2.5 MHz) | [D0.3]、[OA-PMD] 4.4.1 |
| クロック偏差 | ±100 ppm (25 MHz の発振器、経年・温度込み) | [OA-SYS] 5.4.5 |
| PLCA | Clause 148。ラウンドロビンの送信機会で衝突をなくす。OA の車載向け仕様は「全ノード PLCA」のネットワークだけを対象とする | [OA-SYS] 5.2 |
| PoDL | 802.3cg はポイントツーポイントだけ。マルチドロップの給電は規格外 (各社独自) → 802.3da-2026 で追加 | [MCHP-PoDL]、[802.3da] |

### 1.2 DME

- 各ビットの境界で必ず極性が反転する (クロックの遷移)。ビットの中央でも反転すれば "1"、反転しなければ "0"
  ([D0.3] 147.4.2、図 "example DME encoding")。
- したがって遷移の間隔は 40 ns (短) か 80 ns (長) の 2 種類だけ。"1" が続くと 12.5 MHz、"0" が続くと 6.25 MHz の方形波になる。
- **極性に依存しない** (情報は遷移の有無)。線の P/N を逆につないでも動く。
- 休止中、マルチドロップでは送信を止めて high-Z、ポイントツーポイントでは 0 V を出す ([D2.0] 147.3.3.1 の注)。

### 1.3 PCS (4B/5B、スクランブラ)

| 記号 | 5B | 用途 |
|---|---|---|
| SYNC | J (11000) | 送信開始。TX_EN の立ち上がりで 2 個 |
| SSD | K (10001) | SYNC の後に 2 個。プリアンブルの先頭 16 ビットを置き換える |
| ESD | T (01101) | 送信終了 |
| ESDOK / ESDERR | R (00111) / H (00100) | ESD の後に送り、正常終了か送信エラーかを示す |
| BEACON | N (01000) | PLCA のコーディネータが送る (4 個以上) |
| COMMIT | J の連続 | PLCA の送信機会を確保する |

- 出典: 記号の割り当ては [D0.3] の表 (5B の値は 100BASE-X と同じ J/K/T/R/H)。SYNC/SSD の数は最終版で 3+1 から **2+2** に変わった
  ([D2.0] 147.3.3.1、[OA-PCS] 3.2.1 「two SYNC symbols … followed by two SSD symbols」)。
- データは**自己同期スクランブラ**を通してから 5B に変換する。生成多項式は **x¹⁷ + x¹⁴ + 1** (Scr[16] と Scr[13] の XOR、LSB から)
  ([D2.0] 147.3.2.5 と [Beruto-scr])。受信側は SSD の後の 9 シンボルで同期し、その間は MII に 0x5 を出してプリアンブルを作り直す ([D2.0] 147.3.3.1)。
  SYNC、SSD、ESD、ESDOK/ESDERR、BEACON はスクランブルしない。
- 5B は LSB から DME に載せる ([D0.3] 147.4.2 「tx_sym … LSB first」)。
- **要確認**: 表の "11000" がどちらの端から送られるか、スクランブラの最終版の式。これは [IEEE 802.3-2022](https://standards.ieee.org/) の
  Clause 147 (IEEE GET プログラムで無償) で確認し、さらに実機の受信 (§7.2) で確かめる。

### 1.4 送信 (PMA/PMD)

| 項目 | 規格 | 出典 |
|---|---|---|
| 出力電圧 | **1 Vpp ±20%** (0.8〜1.2 Vpp、50 Ω 負荷) | [OA-PMA] 5.1.1 (147.5.4.1)、[Teledyne]、[NCN26000] VOUTpp 800/1000/1200 mV |
| 出力ドループ | 30% 未満 | [OA-PMA] 5.1.2 (147.5.4.2) |
| ジッタ | TIE 2.5 ns p-p 未満 | [OA-PMA] 5.1.3 (147.5.4.3) |
| PSD | マスク (IEEE は 40 MHz まで、OA は 250 MHz まで拡張) | [OA-PMA] 5.1.4、[OA-SYS] 6.3.2.1 |
| 立ち上がり・立ち下がり | **7.5〜15 ns** (20〜80%、負荷 50 Ω‖15 pF)。IEEE ではなく OA の車載向け追加要件 | [OA-SYS] 6.3.2.2、[OA-PMA] 5.1.5 |
| 送信停止 | high-Z。送信をやめてから 40 ns 以内に駆動をやめる | [OA-PMD] 4.3.2 (147.4.2) |
| high-Z 時の MDI | **10 kΩ ‖ 25 pF より高いインピーダンス** (0.3〜40 MHz、式 147-8)。通常時・低電力時・**電源断時**のすべて | [OA-PMA] 5.3.1 (147.5.4.5、147.9.2) |
| 出力インピーダンス | 規格値は見当たらない。NCN26000 は差動 40〜60 Ω | [NCN26000] ROUT |

### 1.5 受信

| 項目 | 内容 | 出典 |
|---|---|---|
| データ判定 | 0 V を中心とする極性判定 (NCN26000 の受信しきい値は 0 mV、精度 ±30 mV) | [NCN26000]、[OA-PMD] 4.4.1 |
| エネルギー検出 (ED) | 窓比較器。OA PMD は窓幅 270〜330 mV (±150 mV)、デグリッチ 30 ns ±30%。NCN26000 の既定は 250 mV | [OA-PMD] 4.4.2 / 表 5、[NCN26000] |
| 受信タイミング対称性 | ±4 ns (PMD トランシーバの要件) | [OA-PMD] 表 10 |
| BER | 10⁻¹⁰ 未満 (ワーストケースのチャネル + 15 ns p-p のジッタ注入) | [OA-PMA] 5.2.1 (147.5.5.1) |
| アイマスク (MDI で) | 高さ ±30 mV、幅 25 ns 以上、ジッタ 15 ns 以下 | [OA-SYS] 9.1 |
| アイドル判定 | 300 mVpp (差動) を 300 ns より長く超えなければ無信号 | [OA-SYS] 9.2 |
| コモンモード | NCN26000 は ±20 V。OA は CMC と組み合わせた共振 (1〜5 MHz) で端子の同相電圧が MDI より大きくなる問題を指摘 | [NCN26000]、[OA-SYS] 6.3.2.3 |

### 1.6 結合と終端 (OA のバスインターフェース回路、図 4 / 表 1)

```
 MDI ─┬─ ESD1(任意) ─┬────────┬─ C1 100nF ─┤CMC├─ TRX_P
      │              R1        │                    (トランシーバ)
      │              ├── C3 ── PGND               
      │              R2   (R3 100k ‖ C3 4.7〜100nF)
      └──────────────┴────────┴─ C2 100nF ─┤CMC├─ TRX_N
```

| 部品 | 値 | 備考 |
|---|---|---|
| C1、C2 (DC 阻止) | 100 nF ±10%、50 V 以上 (48 V 系は 100 V) | |
| R1、R2 | ドロップノード: 1.5 kΩ ×2 (コモンモード終端、任意)。エンドノード: **50 Ω ×2 (差動終端 100 Ω)** | |
| R3、C3 | 100 kΩ (ハーネスの静電気逃がし)、4.7〜100 nF | |
| CMC | 例 200 µH (Murata DLW43MH201XK2L) | [NCN26000] 応用回路 |
| 容量 CMDI | ノードあたり 25 pF 以下 (トランシーバ 10 + CMC 10 + その他 5 が目安、8 ノード・25 m の場合) | |

出典: [OA-SYS] 5.3 表 1、6.4。市販の評価ボード EVB-LAN8670-USB-D はジャンパ J1・J2 の両方で 100 Ω のエンド終端を入れる ([EVB-8670])。

### 1.7 参考: OPEN Alliance の「PMD トランシーバ」

OA TC14 は PHY を**アナログ部 (PMD トランシーバ) とデジタル部 (ホストの MCU / スイッチ内)** に分ける 3 ピンのインターフェースを定めている ([OA-PMD])。
NXP TJA1410 / TJF1410 がこの方式の製品 ([NXP-TJA1410])。

- TX ピン: High-Z / 駆動の切り替えと、極性の反転 (立ち下がりごとに反転)
- RX ピン: 線間電圧の極性が変わるたびに Low パルス (RZI)
- ED ピン: 窓比較器 (±150 mV) の出力

**この Pmod 基板は、まさに「部品をばらして作った PMD トランシーバ」であり、FPGA は OA の言う「デジタル PHY を内蔵したホスト」に当たる。**
OA PMD の電気仕様 (§1.5 の窓幅、タイミング対称性 ±4 ns など) はディスクリートで狙う目標としてちょうどよい。

## 2. 送信

### 2.1 方式の比較

| 案 | 振幅 | high-Z | 立ち上がり | 部品 | 判定 |
|---|---|---|---|---|---|
| A. LVCMOS 2 本 + 直列抵抗 (トライステートで停止) | ◎ | ○ (FPGA の出力を Z に) | × 1〜2 ns (FPGA の出力のまま) | 抵抗のみ | 機能確認用 |
| **B. A + FPGA 側 RC + アナログスイッチ** | ◎ | ◎ (スイッチ断、電源断でも絶縁) | ◎ 約 10 ns | TMUX1511 1 個 | **採用** |
| C. RS-485 トランシーバ (THVD1450 等) | △ 出力が大きすぎて減衰が要る | ○ | △ 速すぎる/遅すぎる品しかない | | 不採用 |
| D. 複数ピンの抵抗 DAC で階段波 | ○ | ○ | △ 段差が残る | ピン数が足りない | 不採用 |

案 A で立ち上がりを鈍らせるには線路側に C を置くしかないが、休止中もその C がバスに見えて「25 pF 以下」を守れない
(線路側ノードのインピーダンスは片側 25 Ω なので、10 ns にするには 200 pF 以上が要る)。
案 B は**スイッチの FPGA 側に C を置き、休止中はスイッチで切り離す**ことで、この矛盾を解く。

### 2.2 回路 (案 B、片側)

```
 FPGA TX_P ─ R1 100Ω ─┬─ X_P ── [TMUX1511 SW1] ── R2 18Ω ─┬─ C 100nF ─┤CMC├─ BI_DA+
 (LVCMOS33, DRIVE=16)  C1 220pF                            │
                       GND                          100kΩ ─ VMID (休止中の DC を決める)
 FPGA TX_N ─ (同じ構成, SW2) ─────────────────────────────── BI_DA−
 FPGA TX_EN ─ SEL1, SEL2 (10kΩ で GND へ: FPGA のコンフィグ中のプルアップでスイッチが入らないように)
```

- **振幅**: 差動の開放電圧は 3.3 V (P=H,N=L ↔ P=L,N=H)、片側の直列抵抗 Rt = Rpin + R1 + Ron + R2 ≈ 140 Ω、負荷は 50 Ω (両端の 100 Ω 終端の並列)。
  `Vpp = 2 × 3.3 × 50 / (50 + 2Rt)` → **1.00 Vpp** (Rpin 20 Ω)。Rpin 15〜30 Ω、VCCIO ±5% で 0.90〜1.08 Vpp (規格 0.8〜1.2)。
  USB HS / 100BASE-TX の経験では DRIVE 設定で振幅が変わるので、R1 は実測で合わせる。
- **出力インピーダンス**: 差動 約 280 Ω (NCN26000 は 50 Ω)。規格値は無く、マルチドロップでは途中のノードが受ける反射はどのみち整合しない
  (他のノードは high-Z) ので問題は小さいと見る。DC 阻止 C (100 nF) と 330 Ω の時定数は 33 µs で、最長 80 ns の区間のドループは無視できる。
- **立ち上がり**: X ノードから見た抵抗は (Rpin+R1) ‖ (Ron+R2+25 Ω) ≈ 33 Ω。C1 = 220 pF で τ = 7.2 ns、**20〜80% = 10 ns** (OA 7.5〜15 ns)。
  C1 = 150 / 330 pF で 6.8 / 15 ns。P と N は相補で同時に動くので、同相成分は R・C の偏差分だけ。
- **high-Z**: TMUX1511 (4 回路 SPST、Ron 2 Ω、COFF 最大 4 pF、**電源断時も 3.6 V まで絶縁**、制御は 1.8 V 系しきい値で内部プルダウン付き)。
  遷移時間 25〜55 ns ([TMUX1511] 5.7)。送信終了時は先に P=N (差動 0) にしてからスイッチを切るので、「40 ns 以内に駆動をやめる」は差動 0 の
  低インピーダンス期間がスイッチの遷移時間ぶん残る形になる (規格の文言に対しては要確認・実測)。
- **送信開始時の同相の段差**: スイッチを入れる瞬間、X の電位と線路側の DC (VMID) が違うと同相の段差が出る。
  FPGA で P=N を高速 (例 100 MHz) に 50% でトグルさせて X を約 1.65 V に保っておけば段差を小さくできる (案。実測で要否を判断)。
- **ジャバー**: TX_EN は FPGA 内のタイマで上限を設ける (OA PMD の jabber と同じ考え方)。
- スイッチを 0 Ω に置き換えれば (フットプリントを用意) 案 A になる。初版は両方を比べられるようにする。

## 3. 受信

### 3.1 比較器 2 個によるヒステリシス比較

100BASE-TX 基板 (`eda/pmod_100base_tx` §2.1, §3.2) と同じく、FPGA の LVDS 入力 2 組を比較器として使う。

- 比較器 H: `P = VB + v+`、`N = VTH + v−` → **H = 1 ⇔ v > +th** (th = VTH − VB)
- 比較器 L: `P = VTH + v+`、`N = VB + v−` → **L = 1 ⇔ v > −th**
- データ: H で 1 にセット、L=0 で 0 にリセットする SR ラッチ (FPGA 内) = **±th のヒステリシス比較器**。
  立ち上がりは +th、立ち下がりは −th で検出されるので、遅れは両方向で同じになり、DME のパルス幅は保たれる。
- エネルギー検出: `H | !L` (= |v| > th) をデグリッチしたもの。
- しきい値は PWM 1 本で ±th を対称に動かす (VTH は 2 つの比較器で共用)。
  `th = (D × 3.3 − VB) × 1k / 6.6k` → D = 0〜1 で −176〜+324 mV、10 bit で 0.49 mV/LSB (VB = 1.17 V)。th > 0 の範囲で使う。
- 比較器ごとの入力オフセットは個別には校正できない。オフセット 30 mV でも、受信端の傾き (約 60 mV/ns) では 0.5 ns の時間誤差で、
  半ビット 40 ns に対して無視できる。効くのはノイズ余裕だけ。
- 各タップは 0.1 µF + 20 kΩ のバイアス (HPF 80 Hz)。FPGA のピンとの間に 1 kΩ を直列に入れ、ピン容量を高域で見えにくくする (ESD の電流制限も兼ねる)。

### 3.2 しきい値・同相範囲・ノイズ

| 項目 | 狙い | 根拠 |
|---|---|---|
| 信号 | 送信端 ±0.5 V。25 m でも損失は小さい (12.5 MHz) が、混在セグメントでは反射でアイが縮む | アイマスク ±30 mV / 幅 25 ns [OA-SYS] 9.1 |
| データのしきい値 | ±30〜80 mV から始める (OA PMD の 0 V ±30 mV 判定に近づける) | [OA-PMD] |
| ED のしきい値 | 別の比較器は無いので、**DME として正しい遷移列か**で判定する (遷移間隔が 40/80 ns に乗っているか)。窓 ±150 mV の厳密な ED は持たない | §1.5 |
| 同相範囲 | FPGA の LVDS 入力の範囲 (VB 1.17 V 付近) は DC 阻止 C の後なので問題ない。線路側の大きな同相電圧 (グラウンド差) は C と CMC が受ける | |
| ノイズ | ヒステリシス ±th、DME の区間判定 (§4) の多数決、ED のデグリッチで対処。車載 EMC 級の耐性は狙わない | |

GW5A / GW1N の LVDS25 入力は 3.3 V バンクでも使える (100BASE-TX 基板は TP25K で、`eda/targets/tangnano9k_pmod` の検討では Nano 9K のバンク 1/2 で確認済み)。
LVDS 規格上の入力しきい値は ±100 mV だが、100BASE-TX 基板の実測では公称 +0.19 V 以上で受信できており、PWM で th を振って余裕を測れる。

### 3.3 CDR と DME の復号 (FPGA 内)

12.5 MBd の DME は自己同期で、遷移間隔は 40 / 80 ns の 2 種類しかない。PLL 型の CDR は不要で、**遷移間隔の分類**で足りる。

- サンプリング: 200 MS/s (TP25K は 100 MHz の IDDR、Nano 9K は 150 MHz の IDDR で 300 MS/s)。分解能 5 ns / 3.3 ns。
- 分類: 区間 < 60 ns → 短、60〜120 ns → 長、それ以上 → 無信号。15 ns p-p のジッタ (±7.5 ns) でも境界まで 12.5 ns の余裕がある。
- 復号: 長区間は必ずクロック遷移からクロック遷移まで ("0")。短区間 2 個 = "1"。最初の長区間でビット境界が決まる (SYNC = J に "0" が含まれる)。
- 周波数差 ±100 ppm は区間ごとに測り直すので吸収不要。
- 5B の境界: 無信号の後の SYNC (J) で合わせる。
- 遅延: 1〜2 ビット (100〜200 ns)。PLCA の応答時間の要件 (送信機会の開始から COMMIT まで 300〜800 ns、[OA-PLCA] TR3.x) に収まる見込み。

既存の `rtl/manchester` (別用途の Manchester 受信、区間判定式) と考え方は同じ。100BASE-TX の OsCdr は使わない (低レートで過剰)。

## 4. 結合・ESD・終端

| 部品 | 案 | 理由 |
|---|---|---|
| トランス | **使わない** | 10BASE-T1S は元々トランスレス (DC 阻止 C + CMC) の規格 |
| DC 阻止 C | 100 nF / 100 V X7R (0603) | OA 表 1 (48 V 系は 100 V) |
| CMC | TDK ACT1210L-201-2P-TL00 (200 µH、1210) | OA 準拠の車載用品で JLC 在庫あり。DLW43MH201XK2L は JLC 在庫 0 |
| ESD | TI TPD4E02B04 (双方向、0.25 pF) を**トランシーバ側 (C の内側)** に | 100BASE-TX 基板と同じ部品。線路側の同相電圧 (グラウンド差) が 3.6 V を超えても C が受ける |
| エンド終端 | 50 Ω ×2 + 中点 4.7〜100 nF → GND、**ジャンパ 1 個**で入/切 | EVB-LAN8670-USB-D と同様に選べるようにする |
| コモンモード終端 | 1.5 kΩ ×2 (DNP) | 任意 ([OA-SYS] 表 1)。入れると high-Z の要件も 2×RCMT 並列に緩む |
| 静電気逃がし | 100 kΩ + 4.7 nF → GND | OA 表 1 の R3 / C3 |
| コネクタ | 5.0 mm 2 ピンのねじ端子 (KF301-5.0-2P) + 2.54 mm のプローブ用ピン | EVB はねじ端子 (Würth 691214110002) |

PoDL・パッシブ給電のバスには**つながない** (シルクに明記)。C の耐圧で壊れはしないが、エンド終端・CM 終端に電流が流れる。

## 5. 規格への適合の限界と目標

| 項目 | 狙えるところ | 理由・やること |
|---|---|---|
| 送信電気特性 (振幅、ドループ、ジッタ、立ち上がり) | 適合を狙える | オシロで OA PMA 試験 5.1.x の手順を真似て測る (50 Ω 負荷)。テストモード 1〜3 を RTL に入れる |
| high-Z のインピーダンス | 適合を狙える (要実測) | 推定 18 pF / 18 kΩ (§6.3 の計算)。NanoVNA 等で 0.3〜40 MHz の |Z| を測る。電源断時はスイッチの絶縁と FPGA の保護ダイオード次第 |
| PSD (40 MHz / 250 MHz) | 不明 | RC 1 段の鈍らせ方で 40 MHz 以上がどこまで落ちるかは測るまで分からない |
| EMC (OA の EMC 仕様、IEC 62228 系) | 狙わない | 測定環境が無い。CMC と相補駆動で一般的な対策はする |
| ノード数 | まず 3 ノード、次に 8 | 容量 25 pF/ノードを守れれば 8 ノード・25 m の前提に乗る |
| ケーブル長 | まず P2P 1〜15 m、混在セグメント 10 m → 25 m | 受信は th を下げれば ±30 mV のアイまで追える計算。反射の大きい構成では th の掃引で余裕を測る |
| 衝突検出 (CSMA/CD) | 診断用のみ | OA は PLCA 前提。送信中も比較器は線を見ているので、送ったビットとの不一致で物理衝突は検出できる |
| 低電力・ウェイクアップ (OA TC10) | 対象外 | |

## 6. 結論: 回路案・部品・RTL

### 6.1 Pmod のピン割り当て (1 ポート、100BASE-TX 基板と同じ並び)

| Pmod | 信号 | 種類 |
|---|---|---|
| 1 / 7 | 比較器 H の P / N | LVDS25 入力 (真の差動対) |
| 2 / 8 | 比較器 L の P / N | LVDS25 入力 (真の差動対) |
| 3 | PWM_TH (しきい値) | LVCMOS33 出力 |
| 9 | TX_EN (TMUX1511 SEL1/SEL2) | LVCMOS33 出力、基板側 10 kΩ プルダウン |
| 4 / 10 | TX_P / TX_N | LVCMOS33 出力 DRIVE=16 |

TP25K の `pmod0` (J6、全ピン バンク 1)、Nano 9K の Rev.C ベース基板の `pmod0` で 1/7、2/8 が差動対になる (100BASE-TX と同じ条件)。
Rev.B ベース基板では P/N が逆になるので RTL で極性を反転する (`eda/targets/tangnano9k_pmod` の Rev.C 検討を参照)。

### 6.2 部品と JLC の入手性 (2026-11-20 に確認)

| 部品 | 品番 | LCSC | 在庫 | 単価 (1〜9) |
|---|---|---|---|---|
| アナログスイッチ | TI TMUX1511PWR (TSSOP-14) | C2866750 | 7,769 | $0.46 |
| CMC 200 µH | TDK ACT1210L-201-2P-TL00 | C131444 | 26,100 | $0.66 |
| (代替 CMC) | Murata DLW43MH201XK2L | C123086 | **0** | |
| ESD | TI TPD4E02B04DQAR | C106794 | 71,680 | (100BASE-TX 基板で採用済み) |
| ねじ端子 | KF301-5.0-2P | C474881 | 75,943 | Extended |
| 抵抗・コンデンサ | 0402/0603 の Basic 品 | | | 100BASE-TX 基板の選定を流用 |
| (比較用) PHY | Microchip LAN8670C2-E/LMX | C20901523 | 108 | $7.0 |
| (比較用) PMD | NXP TJA1410、onsemi NCN26000 | — | JLC の検索で見つからず | |

在庫は jlcsearch.tscircuit.com と wmsc.lcsc.com の照会。部品代は PHY チップ 1 個 ($7) に対し、アクティブ部品は TMUX1511 だけ (約 $0.5)。
基板はシングル Pmod 幅 (20.32 mm) に収まる見込み。

### 6.3 机上計算 (`tools/calc.py`)

```
送信:  Rpin=20Ω VCCIO=3.3V → 1.000 Vpp、t20-80 = 10.0 ns、Zout = 280 Ω
       Rpin 15〜30Ω × VCCIO ±5% → 0.896〜1.083 Vpp
休止中: 差動 18.2 kΩ、容量 8.2 pF (1 線 16.3 pF の半分) + CMC 10 pF = 18.1 pF
       0.3 MHz 15.4k (下限 9.0k)、12.5 MHz 701 (509)、40 MHz 219 (159) Ω → 全域 OK
受信:  th = −176〜+324 mV、0.49 mV/LSB
```

FPGA の LVDS 入力のピン容量 (5 pF/ピンと仮定) が最大の不確定要素。実測で 10 pF/ピンなら 1 線 26 pF・合計 23 pF で、上限ぎりぎりになる。
その場合は RX タップの直列抵抗を 1 kΩ → 2.2 kΩ に上げる (高域でピン容量を隠す)。

### 6.4 RTL の構成案 (Veryl、テストベンチは SV)

```
 rtl/t1s_phy/
   t1s_pma_tx.veryl    DME 符号化 (半ビット 40 ns = 100 MHz で 4 クロック / 150 MHz で 6)、TX_EN の前後処理、ジャバー、テストモード 1〜4
   t1s_pma_rx.veryl    IDDR サンプル → SR ヒステリシス → 遷移間隔の分類 → ビット列 + 無信号検出 + DME 妥当性 (CRS)
   t1s_pcs_tx.veryl    MII ニブル → スクランブラ (x^17+x^14+1) → 4B/5B、SYNC×2 SSD×2、ESD+ESDOK/ESDERR、BEACON/COMMIT
   t1s_pcs_rx.veryl    SYNC で 5B 整列、SSD×2、9 シンボルで逆スクランブラ同期 (0x5 でプリアンブル再生)、ESD 検出
   t1s_plca.veryl      Clause 148 の PLCA RS (コーディネータ / フォロワ、TO タイマ、BEACON、バースト)
   t1s_pwm.veryl       しきい値 PWM、しきい値の掃引 (アイスキャン)
 MAC: rtl/ethernet/mii_mac (SV) を 10 Mb/s の MII で使う。PLCA の論理衝突は MAC のバックオフに渡さず、
      送信待ちのフレームを送信機会まで保持する (MAC と PHY が同じ FPGA にあるので簡略化できる)
 eda/pmod_10base_t1s/  TP25K (50 MHz → PLL 100/200 MHz) と Nano 9K (27 MHz → 150 MHz = 27×50/9) のトップ、
                        UART の状態表示とコマンド、ethernet_icmp 相当の ping / UDP エコー
```

クロック: TP25K は 100 MHz (TX) + IDDR 100 MHz (RX 200 MS/s)。Nano 9K は rPLL 1 段で 150 MHz (FBDIV 50 / IDIV 9) が作れる。
ロジック量は 100BASE-TX PHY より小さい見込み (OsCdr もスクランブラ 11 ビットのワード処理も無い)。

## 7. 実機での相互接続試験の提案

### 7.1 用意するもの

- **Microchip EVB-LAN8670-USB-D** (EV62B92A。USB 2.0 → 10BASE-T1S の NIC、LAN9500A + LAN8670、ねじ端子、100 Ω 終端ジャンパ J1/J2)。
  旧品 EVB-LAN8670-USB (EV08L38A) は販売終了 ([EVB-8670])。Linux では smsc95xx + LAN867x の PHY ドライバで普通の NIC に見え、
  PLCA は **ethtool 6.7 以降**で設定する (`ethtool --set-plca-cfg <if> enable on node-id 0 node-cnt 8 to-tmr 32`)。
- より対線 (車載用 UTP か、CAT5 の 1 対)、1 m / 10 m / 25 m。
- Tang Primer 25K + 本基板、可能なら Tang Nano 9K + 本基板 (3 ノード目)。
- オシロ (差動プローブか 2ch の差分)、ロジアナ (SLogic16U3、比較器出力を 400 MS/s で取れる)。

### 7.2 手順

1. **単体 (EVB なし)**: 50 Ω 負荷で送信波形を測る (テストモード 1: "1" の連続で振幅、テストモード 3: 立ち上がり)。
   TX_EN を切った状態で |Z| を NanoVNA 等で測る (電源オン / FPGA 未コンフィグ / 電源断の 3 状態)。
2. **受信だけで EVB の送信を復号する (最重要)**: EVB をコーディネータ (node-id 0) にして BEACON を出させ、FPGA は送信しない。
   BEACON (N) が正しく 5B 整列で見えるかで、**5B のビット順と DME 復号**を確認する。次に PC から ping / ARP を出し、
   逆スクランブル後のフレームの FCS が合うかで**スクランブラの式・ビット順・SYNC/SSD の数**を確認する。
   この段階はループバックでは見つからない約束事 (§0 のリスク) をすべて相手の実装で確かめられる。ロジアナで比較器出力も同時に記録する。
3. **P2P で送信**: 2 ノード、両端に終端。EVB をコーディネータ、FPGA をフォロワ (node-id 1、node-cnt 2、to-tmr 32) にして、
   ping・UDP の連続送信で両方向の誤り (PC の `ip -s link` の rx_crc_errors、FPGA 側の FCS 誤り数) を数える。
   `ethtool --get-plca-status` でコーディネータが PLCA を維持できているか見る。
4. **FPGA をコーディネータに**: 逆の役割で BEACON 送信と送信機会の管理を確かめる (EVB はフォロワ)。
5. **混在セグメント**: 3 ノード (EVB + TP25K + Nano 9K)、10 m → 25 m、スタブ 10 cm 以下、両端だけ終端。
   しきい値 th を掃引して、誤りが出始める th の上下限 (ノイズ余裕) をノード位置ごとに記録する。
6. 余力があれば OA の PLCA 試験仕様 ([OA-PLCA]) の TR3.x (送信機会の応答時間 1060〜2360 ns + TO×100 ns×ID) をロジアナで測る。

### 7.3 代替の相手

- MikroElektronika「Two-Wire ETH Click」(LAN8651 MAC-PHY、SPI) + Raspberry Pi などでも相手になる。
- onsemi NCN26010 (MAC-PHY) の評価ボード。

## 8. 次の段階 (ユーザーの確認後)

1. 回路図と基板 (KiCad、シングル Pmod、JLC 実装)。スイッチの 0 Ω 迂回、CM 終端 DNP、エンド終端ジャンパ、プローブ用ピン。
2. RTL (`rtl/t1s_phy`) と SV テストベンチ: PCS の TX→RX、スクランブラの自己同期、PLCA の 2〜3 ノードのシミュレーション。
3. 規格本文 (802.3-2022 Clause 147/148) で §1.3 の要確認事項を確定。

## 出典

- [D0.3] IEEE P802.3cg D0.3 Clause 147 (2017-11): https://www.ieee802.org/3/cg/public/Nov2017/8023cg_D0p3_T1S_revB.PDF
- [D2.0] Beruto, Clause 147 D2.0 proposed text (2018-09): https://grouper.ieee.org/groups/802/3/cg/public/Sept2018/beruto_03_Cl_147_d2p0_proposed.pdf
- [Beruto-scr] Beruto, 3cg scrambler proposal: https://www.ieee802.org/3/cg/public/adhoc/beruto_3cg_scrambler.pdf
- [OA-PMA] OPEN Alliance, 10BASE-T1S PMA Compliance Test Specification v1.0 (2025-04): https://opensig.org/wp-content/uploads/2025/05/10BASE-T1S-PMA-Compliance-Test-Specification-v1.0.pdf
- [OA-PCS] OPEN Alliance, 10BASE-T1S PCS Compliance Test Specification v1 (2025): https://opensig.org/wp-content/uploads/2025/08/10BASE-T1S-PCS-Compliance-Test-Specification_v1.pdf
- [OA-PLCA] OPEN Alliance, 10BASE-T1S PLCA Conformance Test Suite v1.3: https://opensig.org/wp-content/uploads/2024/01/OA_10BASE-T1S_PLCA-Conformance-Test-Suite_v1.3.pdf
- [OA-SYS] OPEN Alliance, IEEE 10BASE-T1S System Implementation Specification v1.0 (2023-02): https://opensig.org/wp-content/uploads/2023/12/20230215_10BASE-T1S_system_implementation_V1_0.pdf
- [OA-PMD] OPEN Alliance, 10BASE-T1S PMD Transceiver Interface v1.5 (2022-11): https://opensig.org/wp-content/uploads/2024/01/OPEN_Alliance_10BASE-T1S_PMD_Transceiver_Interface_1p5_Final.pdf
- [NCN26000] onsemi NCN26000 データシート: https://www.onsemi.com/download/data-sheet/pdf/ncn26000-d.pdf
- [LAN8670] Microchip LAN8670/1/2 データシート DS60001573: https://www.farnell.com/datasheets/3979468.pdf
- [EVB-8670] Microchip EVB-LAN8670-USB-D User's Guide: https://docs.rs-online.com/4382/A700000015982121.pdf 、製品ページ https://www.microchip.com/en-us/development-tool/EV08L38A
- [MCHP-PoDL] Microchip AN, LAN86xx Using Power over Data Line in 10BASE-T1S (60001848): https://ww1.microchip.com/downloads/aemDocuments/documents/AIS/ApplicationNotes/ApplicationNotes/LAN86xx-Using-Power-over-Data-Line-in-10BASE-T1S-Application-Note-60001848.pdf
- [802.3da] IEEE 802.3da-2026 (販売ページ): https://webstore.ansi.org/standards/ieee/ieee8023da2026
- [NXP-TJA1410] NXP TJA1410: https://www.nxp.com/products/interfaces/ethernet-/automotive-ethernet-phys/tja1410-10base-t1s-pmd-transceiver:TJA1410
- [Teledyne] Teledyne LeCroy QPHY-10Base-T1S マニュアル: https://cdn.teledynelecroy.com/files/manuals/qualiphy10base-t1s-manual.pdf
- [TMUX1511] TI TMUX1511 データシート: https://www.ti.com/lit/ds/symlink/tmux1511.pdf
- 本リポジトリ: `eda/pmod_100base_tx/README.md` (比較器 2 個の受信、LVCMOS の送信、部品選定)
