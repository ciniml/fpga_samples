# Pmod 10BASE-T1S (Rev. A)

IEEE 802.3cg 10BASE-T1S のバスに、**PHY チップを使わずに**つなぐ Pmod 基板。PCS / PMA / PLCA は FPGA のロジック
(`rtl/t1s_phy`) で実装し、基板には受動部品と、アナログスイッチ 1 個・CMC・ESD アレイだけを載せる。
検討の経緯と規格の要件は [`../../README.md`](../../README.md)。KiCad 10、2 層。

<img src="fab/Pmod_10BASE_T1S_3d.png" width="45%"/> <img src="fab/Pmod_10BASE_T1S_top.png" width="25%"/> <img src="fab/Pmod_10BASE_T1S_bottom.png" width="25%"/>

状態: **設計のみ (未発注・実機未確認)**。

## 仕様

- 外形 20.32 × 44 mm (Pmod 1 スロット幅)、2 層 1.6 mm (B.Cu は GND ベタ)、角 1.27 mm 面取り。
- J1: Pmod 2x6 直角ヘッダ (`Conn_Pmod_Spec_B_Thin`)、上端。Digilent のピン 1 は部品面から見て右端。
- J2: 5.0 mm 2 ピンねじ端子 (KF301-5.0-2P、フットプリントは互換の MaiXu MX126)、下端。1 = BI_DA+ (シルク「+」)、2 = BI_DA−。
  DME は極性に依存しないので逆につないでも動く。挿入実装なので手はんだを既定にする (`jlc_files.py --with-tht` で JLC 実装に含める)。
- J3: 2.54 mm 3 ピン (線 +、線 −、GND、**未実装**)。プローブやジャンパ線用。
- JP1: 2 ピンヘッダ + ショートピン。**バスの両端のノードだけ**挿して 100 Ω のエンド終端を入れる。
- 電源: Pmod VCC (3.3 V) のみ。PoDL 非対応 (給電されたバスにつながない)。

| J1 ピン | 信号 | 種類 | TP25K J6 (pmod0) |
|---|---|---|---|
| 1 / 7 | CMP_HP / CMP_HN (比較器 H: v > +th) | LVDS25 入力 | F5 / G5 |
| 2 / 8 | CMP_LP / CMP_LN (比較器 L: v > −th) | LVDS25 入力 | G7 / G8 |
| 3 | PWM_TH (しきい値) | LVCMOS33 出力 | H8 |
| 9 | TX_EN (TMUX1511 SEL1/SEL2、基板で 10 kΩ プルダウン) | LVCMOS33 出力 | H7 |
| 4 / 10 | TX_P / TX_N | LVCMOS33 出力 DRIVE=16 | H5 / J5 |

並びは `eda/pmod_100base_tx` と同じ (9 番だけ 2 本目の PWM から TX_EN に変更)。

## 回路

| Ref | 値 | 役割 |
|---|---|---|
| R1 / R2 | 100 Ω | 送信の直列抵抗 (FPGA 側)。ピン抵抗 + R1 + Ron + R5 ≈ 140 Ω/片側で、50 Ω (両端終端の並列) に 1.0 Vpp。実測で合わせる |
| C1 / C2 | 220 pF | 立ち上がりを約 10 ns (20〜80%) に鈍らせる。スイッチの FPGA 側にあるので、休止中はバスから見えない |
| U1 | TMUX1511 | 送信の切り離し (SW1/SW2、SEL = TX_EN)。Ron 2 Ω、COFF 最大 4 pF、電源断でも 3.6 V まで絶縁。SW3/SW4 は未使用 (GND) |
| R3 / R4 | 0 Ω (**未実装**) | スイッチの迂回 (検討書の案 A)。載せるときは U1 と C1/C2 を外す |
| R5 / R6 | 18 Ω | 送信の直列抵抗 (線路側) |
| R7 | 10 kΩ | TX_EN のプルダウン (FPGA の未コンフィグ時の弱プルアップでスイッチが入らないように) |
| R8 / R9 | 20 kΩ | TRX_P / TRX_N を VB にバイアス (比較器の VB 側の入力を兼ねる) |
| C4 / C5、R12 / R14 | 100 nF、20 kΩ | 比較器の VTH 側のタップ (AC 結合 + VTH へバイアス) |
| R10 / R11 / R13 / R15 | 1 kΩ | FPGA の各ピンとの直列抵抗 (ピン容量を高域で隠す、ESD 電流の制限) |
| R16 / R17 / C6 / C7 | 2.2 kΩ / 1.2 kΩ / 10 µF / 100 nF | VB = 1.165 V |
| R18 / R19 / C8 | 5.6 kΩ / 1 kΩ / 1 µF | PWM → VTH。th = VTH − VB = (D × 3.3 V − VB) × 0.152 = −176〜+324 mV |
| U2 | TPD4E02B04 | ESD (トランシーバ側、2 チャネル使用、フロースルー) |
| L1 | ACT1210L-201 (200 µH) | コモンモードチョーク。フットプリントはデータシートの推奨ランドから生成 (`gen_sch.py`) |
| C9 / C10 | 100 nF 50 V | DC 阻止 |
| R20 / R21 / C11 / R22 | 49.9 Ω ×2 / 100 nF / 100 kΩ | エンド終端 (JP1 で入/切) と静電気逃がし (OPEN Alliance の R1/R2/C3/R3) |
| R23 / R24 | 1.5 kΩ (**未実装**) | コモンモード終端 (ドロップノードの任意項目) |
| C12 / C13 / C3 | 10 µF / 100 nF / 100 nF | 3.3 V、U1 の電源 |

## 配線

- 自動配線 (circuitpnr、F.Cu / B.Cu)。ESD アレイの対向パッド (フロースルー) から CMC、CMC から DC 阻止コンデンサまでは
  `tools/gen_pcb.py` で手引き (自動配線が対向パッドの片側を取りこぼすため)。
- 12.5 MBd なので等長・差動インピーダンスは考慮していない。線路系のネット (LINE_*, CM_*, TRX_*) は幅 0.3 mm。

## 生成と製造データ

`tools/build.sh --regen` で回路図・基板を作り直し (gen_sch.py → gen_pcb.py → circuitpnr route / labels)、ERC / DRC
(回路図との一致を含む) のあと `fab/` にガーバー、ドリル、BOM、配置、回路図 PDF、画像を書く。`--regen` なしは今の KiCad ファイルから
製造データだけを出す。生成の流儀は Pmod_DVI / Pmod_GbE と同じ (Python)。

部品 (2026-11-20 照会): TMUX1511PWR は JLC 実装在庫 7,737 個 (LCSC 単体の在庫は 0)、ACT1210L-201 は 2.6 万個、TPD4E02B04 は 7.2 万個。
`tools/lcsc_order.py N` で手はんだ用の LCSC 購入リスト (`fab/lcsc/`)。
