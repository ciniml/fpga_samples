# ExtEasyCDR をベースに Pmod USB を設計するための情報

`eda/gowin_easycdr_sample/ExtEasyCDR.kicad_sch` (コミット 772dccb) を出発点に、
[README.md](README.md) の TN710 準拠回路へ改造するための引き継ぎ情報。

## 1. ExtEasyCDR の現状 (回路図から抽出)

### 1.1 リポジトリにあるもの / ないもの

| 項目 | 状態 |
|---|---|
| 回路図 `ExtEasyCDR.kicad_sch` | あり (KiCad 6 以降の S 式形式) |
| プロジェクト `.kicad_pro` / 基板 `.kicad_pcb` / ガーバー | **リポジトリになし**。この PC 内 (`~/repos` 配下、深さ 6 まで) にも見つからず → **基板レイアウトは新規作成** |
| フットプリントライブラリ `local` (`Conn_Pmod_Spec_B_Thin`, `logo`) | 回路図が参照しているが **この PC に未収録** (`~/repos/M5Stack_Reflow/Schematic/local.pretty` には Pmod フットプリントなし)。`Pmod_DisplayPort` も同じ `local` と `typec_board` (FUSB302B, HD3SS460) を参照 |
| 標準ライブラリ | `Connector:USB_C_Receptacle` (シンボル)、`Connector_USB:USB_C_Receptacle_Molex_105450-0101`、`Resistor_SMD:R_0402_1005Metric`、`Capacitor_SMD:C_0402_1005Metric`、`Connector_Generic:Conn_02x06_Top_Bottom` — KiCad 同梱で入手可 |

→ 最初に `local.pretty` (Pmod Spec-B 薄型ヘッダのフットプリント) を探すか作り直す必要がある。
Pmod Spec-B (Digilent Pmod Interface Spec 1.3.1) の 2×6 ピン 2.54mm、基板端からの寸法は仕様書どおり。

### 1.2 部品

| Ref | 部品 | 値 / フットプリント | 役割 |
|---|---|---|---|
| J1 | Conn_02x06_Top_Bottom | `local:Conn_Pmod_Spec_B_Thin` | Pmod (1 ポート) |
| J2 | USB_C_Receptacle | Molex 105450-0101 (USB2.0 専用 16pin。ただし KiCad シンボルはフル 24pin 版) | Type-C レセプタクル |
| C2〜C9 | 100n 0402 | 8 個 | 4 レーン × P/N の **AC 結合** |
| R3〜R10 | 10k 0402 | 8 個 | 各 Pmod 側ラインを VCM にバイアス |
| R1, R2, C1 | 10k/10k 分圧 + 100n | | VCM = 1.65V (LVDS 受信のコモンモード) |
| C3 (100n) | — | 電源パスコン (3V3) |

### 1.3 ネット (ピン ↔ 信号)

**J1 (KiCad の Conn_02x06_Top_Bottom 番号 = Pmod 仕様の番号と同じ)**

| J1 ピン | ネット | J1 ピン | ネット |
|---|---|---|---|
| 1 | PMOD_L0_P | 7 | PMOD_L0_N |
| 2 | PMOD_L1_P | 8 | PMOD_L1_N |
| 3 | PMOD_L2_P | 9 | PMOD_L2_N |
| 4 | PMOD_L3_P | 10 | PMOD_L3_N |
| 5 | GND | 11 | GND |
| 6 | +3V3 | 12 | +3V3 |

上下段 (1/7, 2/8, 3/9, 4/10) が差動対。`targets/*/pmod_ports.csv` の `pmodN_1..10` と同じ番号付け
(Nano 9K pmod0: 2/8 = FPGA 26/25 = IOB8 真性ペア、25K pmod2: 1/7 = G11/G10)。

**J2 (Type-C) の使用ピン**: SS レーンのみ。`ML3` ↔ RX1 (B10/B11)、`ML2` ↔ TX1 (A3/A2)、
`ML1` ↔ RX2 (A10/A11)、`ML0` ↔ TX2 (B3/B2)。GND (A1/A12/B1/B12) + SHIELD。
**D+/D− (A6/A7/B6/B7)、CC1/CC2、VBUS、SBU は未接続** (ExtEasyCDR は SS ペアをケーブル代わりに使う
「差動 4 レーン延長基板」で、USB としては機能しない)。

**信号経路**: `PMOD_Lx_P/N` ── 100n ── `MLx_P/N` ── Type-C。Pmod 側に 10k → VCM。

## 2. Pmod USB への改造内容

### 2.1 削除するもの

- AC 結合コンデンサ C2〜C9、バイアス R3〜R10、VCM 生成 R1/R2/C1 (USB は DC 結合)
- Type-C の SS レーン配線 (ML0〜ML3)。105450-0101 には SS ピンが物理的にないので、シンボルも
  `Connector:USB_C_Receptacle_USB2.0_16P` (KiCad 7/8 に収録) に差し替えると整合する

### 2.2 残すもの

- J1 のピン配置規約 (1/7, 2/8, 3/9, 4/10 = 差動対、5/11 GND、6/12 3V3) とフットプリント
- J2 のレセプタクル部品/フットプリント (Molex 105450-0101) と GND/SHIELD 処理
- 0402 の R/C、`Logo_Open_Hardware_Small`、PWR_FLAG の付け方

### 2.3 追加するもの (TN710 USB2.0-RC + Type-C 周辺)

| 追加 | 内容 |
|---|---|
| **2 つ目の Pmod ヘッダ J3** | `Pmod_DisplayPort` と同様に `Conn_02x06_Top_Bottom` を 2 個横並び (ピッチは Tang Nano 9K / Primer 25K の隣接 Pmod 間隔に合わせる: **要実測**、`Pmod_DisplayPort` の基板データが参照できればそれに合わせる) |
| D+/D− ネット | J2 の A6+B6 → `USB_DP`、A7+B7 → `USB_DN`。ESD (TPD2E001DRLR または USBLC6-2SC6) をレセプタクル直近に |
| CC | A5/B5 に各 5.1k → GND (UFP の Rd。**これがないとホストが VBUS を出さない**) |
| VBUS | A4/A9/B4/B9 を結線 → 100k/22k 分圧 → `VBUS_DET` (任意)。1uF。Pmod 3V3 には接続しない |
| TN710 R ネットワーク | R1 1.5k (PULLUP)、R2/R3 (TERM、0Ω or 36Ω)、R4/R5 0Ω (差動 RX)、R6/R7 (TX、42Ω or 100Ω)、R8/R9/C1 (VREF 1.8k/75Ω(56Ω)/1uF)。定数はファミリ別 ([README.md](README.md) §2.2)。ファミリ切替は R9 と R2/R3/R6/R7 を実装差し替え、または 0Ω ジャンパ |

### 2.4 新しいネット割り当て

| Pmod A (J1) | 信号 | Pmod B (J3) | 信号 |
|---|---|---|---|
| 1 / 7 | USB_RX_D+ / USB_RX_D− (差動 RX、R4/R5 経由) | 1 / 7 | USB_TX_D+ / USB_TX_D− (R6/R7 経由) |
| 2 / 8 | USB_RXDP_D+ (= D+) / USB_RXDP_D− (= VREF) | 2 | USB_PULLUP_EN (R1 経由 → D+) |
| 3 / 9 | USB_RXDN_D+ (= D−) / USB_RXDN_D− (= VREF) | 3 | VBUS_DET |
| 4 / 10 | USB_TERM_RXDP (R2 → D+) / USB_TERM_RXDN (R3 → D−) | 4, 8, 9, 10 | 予備 (LS 用 D− プルアップ等) |
| 5, 11 / 6, 12 | GND / 3V3 | 5, 11 / 6, 12 | GND / 3V3 |

ExtEasyCDR の `PMOD_L0..L3` ラベルを上表に置き換える。差動対 (RX、RXDP、RXDN、TX) は必ず上下段に置く。

## 3. レイアウトに持ち込む情報

- 外形: Pmod 2 ポート幅。`Pmod_DisplayPort` と同じ寸法にすれば既存の Pmod 板と互換。基板データがないため
  **Tang Nano 9K / Primer 25K の Pmod ヘッダ実寸 (隣接ポート中心間距離、基板端からの高さ) を実測**して決める
- 配置順 (TN710): Type-C → ESD → 90Ω 差動 → RC 群 (ヘッダ直近) → ヘッダ。D+/D− ジャンクションから各 R・RX 対へのスタブ 3mm 以内
- 4 層 (S/G/P/S)、D+/D− は L1 のみ、L2 GND 連続。差動 90Ω / 単端 50Ω、等長 ±10mil
- VREF (R8/R9/C1) は RXDP_N / RXDN_N ピン直近。VREF 配線は GND で囲む (130mV の閾値なのでノイズに弱い)
- Type-C のシェルは GND に直結 (ExtEasyCDR と同じ)

## 4. FPGA 側の対応表 (ボード別)

[README.md](README.md) §3 の表をそのまま使う (25K: pmod2/pmod1、9K: pmod0/pmod1)。IO 制約と DRIVE は
[README.md](README.md) §4、RTL ラッパは `rtl/usb/gowin/usb_phy_gowin.v`。

## 5. 作業チェックリスト

1. `local.pretty` (Pmod Spec-B Thin) と `Pmod_DisplayPort` の基板データの所在確認、なければ Pmod 仕様書からフットプリント作成
2. ExtEasyCDR.kicad_sch を `eda/pmod_usb_hs/Pmod_USB.kicad_sch` にコピーし、§2.1 削除 → §2.3/2.4 追加
3. Type-C シンボルを USB2.0 16P 版に差し替え、CC Rd・ESD・VBUS 分圧を追加
4. ファミリ別 R 値の BOM を 3 種 (LittleBee / Arora / Arora-V) で用意、基板は共通
5. PCB: 外形実測 → 4 層 → TN710 の配置規則で配線 → DRC (90Ω 差動、等長)
6. ブリングアップは README §7 (FS → チャープ → HS)
