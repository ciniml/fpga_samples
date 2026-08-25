# Pmod USB 2.0 — 調査結果まとめ (2026-08-25)

`rtl/usb` (Veryl 製 USB 2.0 PHY / ULPI / デバイスコア) を実機で動かすための調査記録。
設計案本体は [README.md](README.md)。

## 1. 参照した Gowin 資料

| 資料 | 要点 |
|---|---|
| IPUG781-1.7J (USB 2.0 SoftPHY IP ユーザーガイド) | UTMI/ULPI 両 I/F、HS/FS/LS ペリフェラル。RX: IDES8 → NRZI → アンスタッフ → シフト、TX はその逆 + OSER8。Single/Dual LVDS モード (Dual = TX/RX 別ピン、推奨)。IO 属性 (LVCMOS33D/LVDS25、DRIVE 値) がファミリ別に規定。**対応デバイスは C7/I6 以上 (Arora V を除く)** |
| TN710-1.1E (Device Peripheral Circuit Design Application Note) | 外部回路 "USB2.0-RC" の確定回路。**11 I/O**: 差動 RX 対 (`USB_RX_D+/-`、0Ω 直結)、単端コンパレータ 2 対 (`USB_RXDP/RXDN`、N 側に VREF)、TX 対 (直列 R6/R7)、終端ピン 2 本 (L 駆動 + R2/R3)、プルアップ 1 本 (R1 1.5k)。定数はファミリ別 (下表)。差動信号は TRUE LVDS ピン、LittleBee/Arora は隣接下位番号ペア未使用・同一バンク・C7 以上。PCB: 単端 50Ω/差動 90Ω、等長 ±10mil、6 層推奨、RC 群は FPGA 直近・ESD はコネクタ直近 |
| USB 2.0 仕様 + Phase-Locked SOF ECN | HS ドライバ 45Ω ±10% (§7.1.1.3)、スケルチ 100〜150mV、チャープ/リセット時間 (§7.1.7.5: TUCH ≥1ms、TWTFS ≤2.5ms、TFILTSE0 2.5us、TWTRSTHS 100〜875us、TDCHBIT 40〜60us)、パケット間隔 (§7.1.18: FS 2〜6.5 bit、HS 8〜192 bit) |

### TN710 定数のファミリ差 (トポロジは共通)

| 部品 | LittleBee (GW1N: Nano 9K) | Arora (GW2A: Primer 20K) | Arora-V (GW5A: Primer 25K) |
|---|---|---|---|
| R1 プルアップ | 1.5k | 1.5k | 1.5k |
| R2/R3 終端直列 | 0Ω (DRIVE=16) | 0Ω (DRIVE=16) | 36Ω (DRIVE=8) |
| R4/R5 差動 RX | 0Ω | 0Ω | 0Ω |
| R6/R7 TX 直列 | 42Ω (DRIVE=8) | 42Ω (DRIVE=4) | 100Ω (DRIVE=8) |
| R8/R9 VREF | 1.8k/75Ω ≈130mV | 1.8k/56Ω ≈100mV | 1.8k/75Ω ≈130mV |
| C1 | 1uF | 1uF | 1uF |
| ピン配置制約 | 隣接下位ペア未使用、同一バンク | 同左 | なし |
| 速度グレード条件 | C7 以上 | C7 以上 | なし |

→ 抵抗値と IO 制約の DRIVE はセット。LittleBee/Arora は R9 のみ差。

## 2. ボード側の調査

### Tang Primer 25K (GW5A-LV25MG121NC1/I0, Arora-V)

- 純正 IP のサポート対象 (IPUG781 表 2-4 に GW5A-25 のリソース例あり)。速度グレード条件なし
- **USB-C はデバッガ (BL616) 専用**、FPGA には接続されていない
- **USB Type-A (J13) は FPGA 直結** (Dock 回路図 `Tang_Primer_25K_Dock_60033_Schematic.pdf` / USB シート):
  - D+/D- → R29/R30 0Ω → **L6 (IOT23A_USB_P) / K6 (IOT23B_USB_N)**、TRUE LVDS 対、BANK7、VCCIO6/7 = 3.3V
  - ホスト構成: R26/R27 **15k プルダウン実装済み**、VBUS は Dock の **+5V レールに直結** (スイッチ/電流制限なし)
  - デバイス用: R28 1.5k (USBA_P→+3V3) **未実装**、R31 1.5k (USBA_P→`USB_DP_Pull`) **未実装**。`USB_DP_Pull` ネットは Dock 上で FPGA ピンに繋がっていない (シート端子のみ)
  - ESD: LXES15AAA1-153 (D+/D-)、0402ESDA-05N (5V)
  - Sipeed の想定は「USB1.1 ホスト (HID ゲームパッド用)」
- Pmod: 2×06 の**上下段が A/B の真性ペア** (回路図 J6: H5_IOT61A/J5_IOT61B, H8_IOT66A/H7_IOT66B, G7_IOT68A/G8_IOT68B, F5_IOT72A/G5_IOT72B)。`easycdr_trace` で pmod2 の G11/G10 を 1Gbps RX に使用済み

### Tang Nano 9K (GW1NR-LV9QN88PC6/I5, LittleBee)

- **C6** のため IPUG781/TN710 の「C7 以上」条件を満たさない (純正 IP は非対応)。本コアは 60MHz ロジック + IDES8/OSER8 なので速度自体は `easycdr_trace` の **999Mbps 送信実績** から足りる見込み。480Msps IDES8 の余裕は要実測
- USB-C はデバッガ (BL702) 専用。FPGA に USB 信号なし
- Pmod: pmod0 pin2/8 (26/25) = IOB8 真性ペア (実績あり)。他のペアと「隣接下位ペア未使用」制約は回路図で要確認

### Tang Primer 20K (GW2A-LV18PG256C8/I7, Arora)

- **C8** で条件を満たす。小型ボードで唯一「公式条件内」で HS を試せる候補
- TN710 定数は LittleBee と R9 のみ差 (56Ω)
- Pmod (Dock 4 ポート) の上下段が真性ペアかは PG256 ピン表で未確認。`easycdr_trace` の 20K 移植も未実施

### リポジトリ内の既存基板

- `eda/display_port_typec` (Pmod DisplayPort): Type-C レセプタクル (Molex 105450-0101) の `USB_DP/USB_DM` はボード内で完結、Pmod には出ていない。Pmod 2 ポート幅の外形と `local:Conn_Pmod_Spec_B_Thin` フットプリントが流用可能
- `eda/gowin_easycdr_sample` (ExtEasyCDR): 同じ Type-C レセプタクルで 1Gbps 差動を Pmod に通した実績 → コネクタ/フットプリントを流用
- `eda/cpu_usb`: 名前に反して `cpu_matrix_led` のコピー。USB 回路なし

## 3. 実現性マトリクス

| 構成 | FS (12Mbps) | HS (480Mbps) | 備考 |
|---|---|---|---|
| 25K + Dock USB-A をデバイスとして使用 | **可** (改造要: §4) | **不可** | プルアップ固定・終端なし・単端コンパレータなし |
| 25K + Pmod USB 基板 (TN710 準拠) | 可 | 見込みあり | Pmod ヘッダ〜FPGA の未整合区間が最大リスク。IODELAY で位相掃引 |
| 9K + Pmod USB 基板 | 可 | 要実測 (C6) | 速度は 999Mbps 実績から見込みあり、ピン制約要確認 |
| 20K + Pmod USB 基板 | 可 | 見込みあり (C8、公式条件内) | Pmod 差動対の確認が必要 |
| 市販 ULPI PHY (USB3300/3320) を Pmod 化 | 可 | 可 | `UlpiLink`+`UsbDevice` の検証には最短。自作 PHY の評価にはならない |

## 4. Tang Primer 25K の USB-A をデバイスとして使う場合 (FS 限定)

コネクタ変換 (A-A ケーブル、または A→C アダプタ) だけでは動かない。必要な改造:

1. **VBUS を絶縁する**: J13 の VBUS は Dock の +5V レールに直結しているため、そのままホスト PC に挿すと
   PC の VBUS と Dock の 5V (USB-C デバッガ経由の給電) が短絡する。VBUS 線を切ったケーブル/アダプタを使うか、
   R29/R30 側ではなく **J13 の VBUS ピンを浮かせる** (D9 の 5V ESD は残ってよい)
2. **D+ プルアップ**: R28 (1.5k → +3V3) を実装する。固定プルアップなので FPGA からの接続/切断制御はできない
   (= HS チャープ後にプルアップを外せないため HS 不可)。FPGA 制御にしたい場合は R31 を実装し、`USB_DP_Pull` を
   ジャンパ線で空き IO に引く
3. **15k プルダウン**: R26/R27 はホスト用。残しても D+ アイドルは 3.3V × 7.5k/9k ≈ 2.75V (> VIH 2.0V) で動くが、
   信号品質のため外すのが望ましい
4. FPGA 側: `UsbPhy` を FS 専用ラッパ (サンプル 0 のみ、`i_rx_dd = i_rx_dp`、TX はビット 0 を双方向パッドへ) で
   L6/K6 (BANK7、LVCMOS33) に接続。直列抵抗は 0Ω なので FS ドライバインピーダンスは FPGA ピンのみ
   (規格 28〜44Ω からは外れるが FS では実用上動く)

HS は、プルアップ制御・45Ω 終端・単端コンパレータ (VREF) が Dock にないため不可。

### 4.1 「抵抗の置き換え + 特殊ケーブル」で HS にできるか → **できない (FS まで)**

抵抗交換と VBUS 絶縁で解決するのは「プルアップの有無」と「VBUS 短絡」だけで、HS に必要な
TN710 の USB2.0-RC 回路のうち次が Dock に存在しない:

| HS に必要な要素 (TN710) | Dock USB-A の状態 | 後付けの可否 |
|---|---|---|
| 差動 RX 対 `USB_RX_D+/-` (TRUE LVDS) | **あり** (L6/K6 直結) | — |
| 単端コンパレータ 2 対 `USB_RXDP/RXDN` + VREF (R8/R9/C1) | なし | D+/D- ノード (R26/R27 パッド) から別の LVDS 入力対 2 組へ配線が必要。FPGA ピンは Pmod ヘッダ経由しかなく、数 cm のジャンパ線 = 480Mbps のスタブになる |
| 45Ω 終端 ×2 (`USB_TERM_*` ピン L 駆動 + 36Ω) | なし (15k プルダウンのみ) | 同上。終端はノード直近に置かないと意味がない |
| TX 直列 R6/R7 (100Ω) と TX 専用対 | なし (0Ω で L6/K6 に直結、RX と共用) | L6/K6 を Single LVDS モード的に双方向で使うことは可能だが、100Ω 直列を入れると RX 感度が落ちる |
| プルアップの FPGA 制御 (HS 移行後に切断) | R31 未実装、`USB_DP_Pull` は未接続 | R31 実装 + ジャンパ線で空き IO へ (これは可) |

つまり HS には「D+/D- ノードに 4 本 (終端 2 + コンパレータ入力 2、実際は差動対なので 6 本) の
FPGA 配線を数 mm 以内で追加する」必要があり、Dock の基板構造 (FPGA ピンは Pmod/40P ヘッダのみ、
D+/D- ノードは USB-A 直近) では信号品質の観点で成立しない。ジャンパ線改造で無理に試しても
チャープまでは通る可能性があるが、480Mbps のデータ受信は期待できない。

結論: Dock の USB-A は **FS デバイス評価専用** (改造: VBUS 絶縁 + R28 または R31+ジャンパ、R26/R27 除去推奨)。
HS 評価は TN710 準拠の Pmod 基板 ([README.md](README.md)) で行う。

### 4.2 40P ヘッダの K7/J7 (IOT21A/B) を使えば HS にできるか

K7/J7 は 40P ヘッダ pin 28/27 に出ている **真性 LVDS ペア (IOT21A/B, BANK7)** で、ピンの種別としては
TN710 の差動入力対に使える。ただし目的によって答えが分かれる:

**(a) USB-A (J13) の D+/D- に K7/J7 をジャンパ配線して不足分を補う → 不可**
- Dock 上の位置: USB-A は基板左端中央、K7/J7 は上辺の 40P ヘッダ右寄り (pin 27/28)。D+/D- ノード
  (R26/R27/R29/R30 パッド) からヘッダまで **30〜40mm** の配線になり、480Mbps (立ち上がり 500ps ≈ 電気長
  約 25mm) に対して終端・コンパレータ入力のスタブとして長すぎる。§4.1 の結論は変わらない
- FS なら距離は問題にならないが、FS に追加ピンは不要

**(b) USB-A を使わず、40P ヘッダ上に TN710 回路 + Type-C を載せた小基板を作る → 可 (Pmod 基板の代替案)**
- 40P ヘッダには真性 LVDS ペアが少なくとも 4 組ある: **K7/J7 (IOT21A/B)、L7/L8 (IOT19A/B)、
  L10/K10 (IOT15A/B)、J11/J10 (IOT1A/B)** (Dock 裏面シルクと回路図より、いずれも BANK7 3.3V)。
  TN710 の必要数「差動 4 対 + 単端 3 本」がこのヘッダ 1 本で揃う
- Pmod 2 ポートに跨がる必要がなく、2.54mm の 1 列ヘッダなので基板も単純。ヘッダ〜FPGA の未整合区間が
  スタブになる問題は Pmod 案と同程度 (Dock 内配線 + ヘッダ)
- 制約: Arora-V なので隣接ペア未使用・同一バンクの条件は不要。R2/R3 36Ω・R6/R7 100Ω・R9 75Ω の Arora-V 定数
- Nano 9K / Primer 20K には流用できない (ヘッダ配置が異なる) ので、複数ボードで使い回すなら Pmod 案、
  25K 専用で最短に作るなら 40P 案

→ 「K7/J7 を使えば HS 対応可能か」への答え: **USB-A の改造としては不可、40P ヘッダ用の TN710 基板 (Type-C 付き)
としてなら可**。後者は README の Pmod 案と同じ回路をヘッダだけ変えたもの。

## 5. RTL 側の対応状況

- `UsbPhy` に差動レシーバ入力 `i_rx_dd` を追加 (TN710 の `USB_RX_D+/-`)。HS では差動で J/K、単端両 L で SE0
- `rtl/usb/gowin/usb_phy_gowin.v` を TN710 の 11 I/O 構成 (TLVDS_IBUF×3 + IDES8×3 + OSER8×2 + TBUF×2) に書き換え (未検証)
- `veryl test` 9 本 (PHY HS/FS/LS、ULPI、デバイス FS/HS/HS+ULPI) は変更後も合格

## 6. 未確認事項

- Nano 9K: pmod0 の 26/25 以外の真性ペア、「隣接下位ペア未使用」を Pmod 配線で満たせるか (Nano 9K 回路図)
- Primer 20K: Dock Pmod の真性ペア (PG256 ピン表)
- Gowin プリミティブ (IDES8/OSER8/TLVDS_IBUF) の実機動作、480Msps での位相余裕 (IODELAY 掃引の要否)
- TN710 の LVCMOS33D 1 対の TX で FS の SE0 (両線 L) をどう出しているか (本ラッパは単端 2 パッドで回避)

## 参考リンク

- Tang Primer 25K Wiki: https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html
- 25K Dock 回路図: https://dl.sipeed.com/fileList/TANG/Primer_25K/02_Schematic/Tang_Primer_25K_Dock_60033_Schematic.pdf
- 25K 資料一式: https://dl.sipeed.com/shareURL/TANG/Primer_25K
