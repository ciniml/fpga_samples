# Pmod USB 2.0 HS デバイス基板 — 設計検討

`rtl/usb` の PHY コア (UTMI/ULPI、HS/FS/LS) を Tang Primer 25K / Tang Nano 9K の
Pmod で実機評価するための基板案。Gowin USB 2.0 SoftPHY IP の **Dual LVDS モード**
(IPUG781 §3.2 図 3-3) と **TN710 (Gowin USB 2.0 SoftPHY Device Peripheral Circuit Design
Application Note) の USB2.0-RC 回路**をベースに、Pmod 2 ポート分の I/O に収めた。コネクタは USB Type-C レセプタクル (USB 2.0 専用、SS レーンなし)。

状態: **机上検討** (回路図/基板は未作成)。

## 1. 要求と方針

| 項目 | 内容 |
|---|---|
| 速度 | HS 480Mbps (目標) / FS 12Mbps (必ず動かす) / LS は非対象 |
| 役割 | デバイス (UFP) のみ。ホスト/OTG なし。VBUS は電源に使わない |
| 回路 | **Gowin TN710 の USB2.0-RC 回路をそのまま採用** (R1〜R9, C1 の定数はデバイスファミリ別) |
| FPGA 側 I/F | `rtl/usb/usb_phy.veryl` (`UsbPhy`) のシリアル側: `i_rx_dd` (差動レシーバ)、`i_rx_dp/dn` (単端コンパレータ)、`o_tx_dp/dn`, `o_tx_oe`, `o_pullup_dp_en`, `o_term_dp/dn_en`。ラッパは `rtl/usb/gowin/usb_phy_gowin.v` |
| Pmod | 2 ポート占有 (既存 `Pmod_DisplayPort` と同じ `Conn_Pmod_Spec_B_Thin` ×2 横並び)。3.3V バンク |
| コネクタ | Molex 105450-0101 (USB2.0 専用 16pin Type-C、`ExtEasyCDR` と同じ) |

TN710 の必要 I/O は 11 本 (差動対 4 + 単端 3)。1 Pmod (8 I/O、差動対 4) には
収まらないため 2 ポートにする。VBUS 検出を 1 本追加して 12 本。

## 2. 回路 (TN710 USB2.0-RC 準拠)

### 2.1 ブロック図

```
 Type-C (USB2.0 only)                USB2.0-RC (Pmod 基板)                  FPGA (Pmod 経由)
 VBUS (A4,A9,B4,B9) ──┬─ 100k/22k ─── VBUS_DET ───────────────────────── LVCMOS33 in
                      └─ 1uF
 CC1 ── 5.1k ── GND, CC2 ── 5.1k ── GND   (UFP: Rd)

 D+ (A6,B6) ─┬─ ESD ─┬───────────────────────── R4 0Ω ── USB_RX_D+  ┐ TRUE LVDS 入力対 (HS データ)
 D- (A7,B7) ─┼─ ESD ─┼───────────────────────── R5 0Ω ── USB_RX_D-  ┘
   90Ω 差動   │       ├── R6 ── USB_TX_D+                            ┐ LVCMOS33D 出力対 (直列 R6/R7)
              │       ├── R7 ── USB_TX_D-                            ┘
              │       ├── R1 1.5k ── USB_PULLUP_EN                     LVCMOS33 out (D+ のみ)
              │       ├── R2 ── USB_TERM_RXDP                          LVCMOS33 out (L 駆動 = 45Ω 終端)
              │       ├── R3 ── USB_TERM_RXDN                          LVCMOS33 out
              │       ├────────── USB_RXDP_D+ ┐ LVDS25 入力対 (単端 D+ コンパレータ)
              │       │   VREF ── USB_RXDP_D- ┘
              │       └────────── USB_RXDN_D+ ┐ LVDS25 入力対 (単端 D- コンパレータ)
              │           VREF ── USB_RXDN_D- ┘
 VREF = 3.3V × R9/(R8+R9) ≈ 130mV  (R8 1.8k, R9 75Ω, C1 1uF)
```

### 2.2 定数 (TN710 表)

| 部品 | LittleBee (Tang Nano 9K) | Arora (Primer 20K) | Arora-V (Tang Primer 25K) | 役割 |
|---|---|---|---|---|
| R1 | 1.5k | 1.5k | 1.5k | D+ プルアップ |
| R2, R3 | 0Ω | 0Ω | 36Ω | HS 終端 (ピン出力インピーダンス + R = 45Ω) |
| R4, R5 | 0Ω | 0Ω | 0Ω | 差動 RX 直結 |
| R6, R7 | 42Ω | 42Ω | 100Ω | TX 直列 (HS 400mV 振幅はピン DRIVE 設定と合わせて決まる) |
| R8 / R9 | 1.8k / 75Ω | 1.8k / 56Ω | 1.8k / 75Ω | VREF (≈130mV / ≈100mV / ≈130mV) |
| C1 | 1uF | 1uF | 1uF | VREF バイパス |

抵抗 1%・容量 20%、0402。**RC 部品は FPGA 側に寄せて配置** (TN710: "as close to FPGA as possible") —
Pmod 基板ではヘッダ直近に置く。

### 2.3 動作の割り当て (RTL 側)

- **HS データ**: 差動レシーバ `USB_RX_D+/-` → `i_rx_dd`。HS アイドル (SE0) は単端コンパレータ両方 L で検出 (スケルチ代用)
- **FS / チャープ / LineState**: 単端コンパレータ `USB_RXDP/RXDN` → `i_rx_dp/dn`。閾値 130mV は HS 0/400mV・チャープ 0/800mV・FS 0/3.3V のいずれにも有効
- **TX**: 1 対で FS/HS 共用。HS 振幅 400mV は「3.3V 出力 → (ピン出力インピーダンス + R6) → 22.5Ω」で作るため、
  IPUG781 の DRIVE 指定 (GW1N: DRIVE=8、GW2A: DRIVE=4、Arora-V: DRIVE=8) を守る。FS では同じ経路で 3.3V レベルを出す
- **チャープ K**: `OpMode=RAW` で TX 対から K (D- H / D+ L) を出す。FS プルアップは有効のまま
- **終端**: `o_term_dp/dn_en` = 1 のときピンを L 駆動 (それ以外は Z)。`o_pullup_dp_en` は H/Z

これらは `rtl/usb/gowin/usb_phy_gowin.v` (TLVDS_IBUF ×3 + IDES8 ×3 + OSER8 ×2 + TBUF ×2) で実装済み (未検証)。
差動 TX は TN710 では LVCMOS33D の 1 対だが、FS の SE0 (両線 L) を出す必要があるため
本ラッパでは 2 本の単端トライステートパッドとして扱う (レベルは同じ)。

### 2.4 保護・その他

- ESD: TPD2E001DRLR (TN710 リファレンス) または USBLC6-2SC6。線路容量 ~1pF 級
- Type-C: CC1/CC2 に 5.1kΩ (Rd)。これがないとホストが VBUS を出さず列挙されない
- VBUS: 100k/22k で 5V → 0.9V に落とし LVCMOS33 入力へ (接続検出、任意)。VBUS は Pmod に供給しない

## 3. Pmod ピン割り当て

TN710 の制約:
- 差動信号 (`USB_RX_D+/-`, `USB_RXDP`, `USB_RXDN`, `USB_TX_D+/-`) は **TRUE LVDS ピン**に置く
- LittleBee/Arora では `USB_RX_D+/-` の **隣接する下位番号の差動対が存在し未使用**であること (例: IOB13A/B を使うなら IOB12A/B を空ける)
- Arora-V 以外は全信号を同一バンクに置く

Pmod の上下段 (1/7, 2/8, 3/9, 4/10) は差動対として使える実績あり
(25K pmod2 の G11/G10、Nano 9K pmod0 の 26/25 (IOB8 真性ペア) を `easycdr_trace` で 1Gbps に使用)。

| Pmod A | 信号 | 種別 | Pmod B | 信号 | 種別 |
|---|---|---|---|---|---|
| 1 / 7 | USB_RX_D+ / D- | TRUE LVDS in | 1 / 7 | USB_TX_D+ / D- | LVCMOS33(D) out, R6/R7 |
| 2 / 8 | USB_RXDP_D+ (D+) / D- (VREF) | LVDS25 in | 2 | USB_PULLUP_EN | LVCMOS33 out, R1 |
| 3 / 9 | USB_RXDN_D+ (D-) / D- (VREF) | LVDS25 in | 3 | VBUS_DET | LVCMOS33 in |
| 4 / 10 | USB_TERM_RXDP / RXDN | LVCMOS33 out, R2/R3 | 4, 8, 9, 10 | (予備) | |
| 5,11 / 6,12 | GND / 3.3V | | 5,11 / 6,12 | GND / 3.3V | |

FPGA ピン (targets/*/pmod_ports.csv より):

| 信号 | Tang Primer 25K (A=pmod2, B=pmod1) | Tang Nano 9K (A=pmod0, B=pmod1) |
|---|---|---|
| USB_RX_D+ / D- | G11 / G10 | 28 / 27 (※1) |
| USB_RXDP_D+ / D- | D11 / D10 | 26 / 25 (IOB8 真性ペア) |
| USB_RXDN_D+ / D- | B11 / B10 | 39 / 36 (※1) |
| USB_TERM_RXDP / RXDN | C11 / C10 | 37 / 38 |
| USB_TX_D+ / D- | A11 / A10 | 42 / 41 (※1) |
| USB_PULLUP_EN | E11 | 35 |
| VBUS_DET | K11 | 34 |

※1 Nano 9K は 26/25 以外のペアが TRUE LVDS か未確認。また「隣接下位番号ペアを空ける」
制約を Pmod 配線で満たせるかは Nano 9K 回路図 (IOB 番号) で確認が必要。満たせない場合は
`USB_RX_D+/-` を 26/25 に移し、単端側を他ペアに振り替える。25K (Arora-V) にはこの制約がない。

### 3.1 Tang Primer 20K (GW2A-18, Arora) を加える場合

- 定数は LittleBee と **R9 のみ**異なる (56Ω → VREF ≈ 100mV)。R2/R3 = 0Ω、R6/R7 = 42Ω は共通。
  R9 を 0Ω ジャンパで 75Ω/56Ω 切替にすれば LittleBee/Arora は同一実装、Arora-V は R2/R3/R6/R7 も差し替え
- IO 制約: TX `DRIVE=4` (IPUG781 GW2A)、終端 `DRIVE=16`。ピン配置制約 (隣接下位番号ペア未使用・同一バンク) は
  LittleBee と同じ。GW2A-18 は **C8 なので C7 以上の条件を満たす** (Nano 9K の C6 と違い公式条件内)
- Pmod (dock 側 4 ポート、`targets/tangprimer20k/pmod_ports.csv`): pmod0 = P6/R8/P8/T9 + T6/T7/T8/P9 など。
  上下段が TRUE LVDS 対になっているかは PG256 ピン表で**未確認** (`easycdr_trace` の 20K 移植も未実施で実績なし)。
  対になっていなければ差動 4 対を確保できる Pmod の組を選び直す必要がある

## 4. FPGA 側の制約とラッパ

`rtl/usb/gowin/usb_phy_gowin.v` を使う。制約例 (25K, Arora-V。IPUG781 §3.2 の属性に準拠):

```
IO_LOC  "usb_rx_dp_i"  G11;  IO_LOC "usb_rx_dn_i"  G10;   // TRUE LVDS 対
IO_PORT "usb_rx_dp_i"  IO_TYPE=LVDS25 PULL_MODE=NONE DIFF_RESISTOR=OFF;
IO_LOC  "usb_rxdp_p_i" D11;  IO_LOC "usb_rxdp_n_i" D10;
IO_PORT "usb_rxdp_p_i" IO_TYPE=LVDS25 PULL_MODE=NONE DIFF_RESISTOR=OFF;
IO_LOC  "usb_rxdn_p_i" B11;  IO_LOC "usb_rxdn_n_i" B10;
IO_PORT "usb_rxdn_p_i" IO_TYPE=LVDS25 PULL_MODE=NONE DIFF_RESISTOR=OFF;
IO_LOC  "usb_tx_dp_o"  A11;  IO_LOC "usb_tx_dn_o"  A10;
IO_PORT "usb_tx_dp_o"  IO_TYPE=LVCMOS33 DRIVE=8 PULL_MODE=NONE;    // GW1N: DRIVE=8, GW2A: DRIVE=4
IO_PORT "usb_tx_dn_o"  IO_TYPE=LVCMOS33 DRIVE=8 PULL_MODE=NONE;
IO_LOC  "usb_term_dp_o" C11; IO_LOC "usb_term_dn_o" C10;
IO_PORT "usb_term_dp_o" IO_TYPE=LVCMOS33 DRIVE=8 PULL_MODE=NONE;   // GW1N/GW2A: DRIVE=16 (R2/R3=0Ω)
IO_PORT "usb_term_dn_o" IO_TYPE=LVCMOS33 DRIVE=8 PULL_MODE=NONE;
IO_LOC  "usb_pullup_en_o" E11;
IO_PORT "usb_pullup_en_o" IO_TYPE=LVCMOS33 DRIVE=8 PULL_MODE=NONE;
```

- クロック: 60MHz PCLK + 240MHz FCLK (DDR) を同一 PLL から。`easycdr_trace` の PLL ラッパを流用できる
- HS RX の位相合わせ: 1 サンプル/ビットのため、`usb_rx_d` の IDES8 前段に IODELAY を入れ、
  SOF の受信成否 (125us 毎) を指標に掃引する簡易キャリブレーションをブリングアップ時に追加する
- Tang Primer 20K (GW2A、Arora) でも同じ基板が使える (R2/R3 0Ω、R6/R7 42Ω、R9 56Ω の LittleBee/Arora 定数で実装)

## 5. レイアウト指針

- TN710 は 6 層 (S/G/S/P+G/G/S) を推奨するが、小型 Pmod 基板では 4 層 (S/G/P/S) とし、
  D+/D- は L1 のみで L2 GND を連続参照させる。外形は Pmod 2 ポート幅 (`Pmod_DisplayPort` と同寸法)
- 単端 50Ω / 差動 90Ω、差動ペアの等長 ±10mil、層替え時は GND ビアを 2〜4 個添える (TN710 §Signal Routing)
- 配置は TN710 に従い「コネクタ → ESD (コネクタ直近) → 90Ω 差動 → USB2.0-RC (FPGA 直近)」。
  Pmod 基板では RC 群をヘッダ直近に集め、D+/D- ジャンクションから各 R・RX 対へのスタブを 3mm 以内に
- USB_RX_D+/- (差動 RX) と USB_TX_D+/- はジャンクションから対として引く。単端コンパレータ入力も対 (P=線路, N=VREF) として引く
- ヘッダ〜FPGA の未整合区間 (~30〜40mm、~250ps) が HS のスタブになる。HS の立ち上がり 500ps に対し
  無視できないので、HS 品質はこの区間に依存する (本基板の最大リスク。TN710 の前提は FPGA 直近実装)
- VREF (R8/R9/C1) は 1 組を両コンパレータで共用、N 側ピン直近に 0.1uF を追加
- Pmod の GND ピン (5,11) を両ポートとも使う。3.3V は 3 端子レギュレータ不要
  (Pmod VCC 直結)、0.1uF ×4 + 10uF

## 6. BOM (主要部品)

| 部品 | 値 / 型番 | 数 | 備考 |
|---|---|---|---|
| USB-C レセプタクル | Molex 105450-0101 | 1 | `ExtEasyCDR` と同じ、USB2.0 専用 |
| ESD | TPD2E001DRLR (TN710) / USBLC6-2SC6 | 1 | 低容量 |
| R (CC Rd) | 5.1kΩ 1% 0402 | 2 | |
| R1 (D+ プルアップ) | 1.5kΩ 1% 0402 | 1 | |
| R2, R3 (HS 終端) | 0Ω (LittleBee/Arora) / 36Ω (Arora-V) 0402 | 2 | 対象ボードで選択 |
| R4, R5 (差動 RX) | 0Ω 0402 | 2 | |
| R6, R7 (TX 直列) | 42Ω (LittleBee/Arora) / 100Ω (Arora-V) 1% 0402 | 2 | 対象ボードで選択 |
| R8 / R9 (VREF) | 1.8kΩ / 75Ω (Arora は 56Ω) 1% 0402 | 1+1 | |
| C1 (VREF) | 1uF 0402 | 1 | |
| R (VBUS 分圧) | 100kΩ / 22kΩ 0402 | 1+1 | |
| C | 0.1uF 0402 ×6, 1uF 0603 ×1, 10uF 0603 ×1 | | |
| Pmod ヘッダ | `local:Conn_Pmod_Spec_B_Thin` (2×6) | 2 | 既存基板と共通 |

## 7. ブリングアップ手順

1. FS のみ: `UsbDevice` の `HS_CAPABLE=0` で合成。TX_HS/TERM は未使用。
   Linux ホストで `lsusb -v`、`dmesg` で列挙確認 → pyusb でバルクエコー
2. チャープ: `HS_CAPABLE=1` にし、ホストが HS ハブ/ルートポートならチャープ K-J 交換後に
   HS へ移行するはず。`o_high_speed` を LED に出す
3. HS データ: SOF (125us 毎) の受信で RX 位相を掃引・確定 → GET_DESCRIPTOR → バルク
4. 失敗時の切り分け: FS 用に `eda/easycdr_trace` のキャプチャ手法 (BSRAM にサンプル列
   を貯めて UART で吐く) を IDES8 出力に流用できる

## 8. Tang Nano 9K について

- GW1NR-9 (C6/I5)。Gowin 純正 SoftPHY IP は C7/I6 以上を要求するため公式には対象外だが、
  本コアは 60MHz ロジック + IDES8/OSER8 (480Mbps) なので、この基板で **999Mbps 送信を
  実機で通した実績 (`easycdr_trace`)** から HS のシリアライザ/デシリアライザ速度自体は
  足りる見込み。C6 での 480Mbps IDES8 のセットアップ余裕は要実測
- FS は問題なし (Pmod 直結、LVCMOS33)
- Pmod0/1 が隣接しているので同じ 2 ポート基板を挿せる。LVDS 入力ペアの割当は §3 の要確認事項

## 9. 代替案

- **FS 専用ミニ基板 (1 Pmod, 3 I/O)**: D+/D- を 27Ω 直列で双方向ピンに直結、D+ 1.5k
  プルアップ制御の 3 本のみ。RX は同じ双方向ピンの入力を使う。HS の評価はできないが
  半日で作れるので先行して作る価値がある
- **25K/9K 兼用**: R2/R3/R6/R7/R9 だけがファミリ依存なので、同一基板で実装抵抗を変える (または 0Ω ジャンパで
  切替) ことで Tang Primer 25K (Arora-V) と Tang Nano 9K / Primer 20K (LittleBee/Arora) を 1 種類の基板で賄える
- **市販 ULPI PHY (USB3300/USB3320) 基板を Pmod 化**: `UlpiLink` + `UsbDevice` を
  そのまま使え、アナログ部の不確実性を消せる。60MHz ULPI (12 本) は Pmod 2 ポートに
  収まる。自作 PHY の評価にはならないが、デバイスコアと ULPI Link 側の実機検証には最短
