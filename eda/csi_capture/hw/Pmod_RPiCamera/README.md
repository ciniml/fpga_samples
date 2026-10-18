# Pmod RPi Camera (Rev. A)

Raspberry Pi カメラ (15 ピン 1.0 mm FFC, 2 レーン MIPI CSI-2) を Pmod 1 個につなぐ変換基板。
FPGA 側はソフト D-PHY (`eda/csi_capture`, `rtl/csi2`)。KiCad 10。

<img src="fab/Pmod_RPiCamera_3d.png" width="45%"/> <img src="fab/Pmod_RPiCamera_top.png" width="30%"/>

状態: **設計のみ (未発注・実機未確認)**。ERC / DRC (回路図との一致を含む) はエラー 0。

## 仕様

- 外形 25.4 × 24.13 mm、2 層 1.6 mm (FR4)、角 1.27 mm 面取り。
  FFC コネクタ (取付金具込み 20.8 mm) を載せるため Pmod 標準幅 (20.32 mm) より片側 2.5 mm 程度広い
- J1: Pmod 2x6 直角ヘッダ (TangFPGAExtensions の `Conn_Pmod_Spec_B_Thin`)、基板下端
- J2: **Amphenol (FCI) SFW15R-1STE1LF** (15 ピン 1.0 mm FFC、**下面接点**、ZIF、JLC C3168538)。
  Raspberry Pi Camera Module 2 の J1 と同じ部品。フットプリントは FCI 図面 JSA95855 rev AE / JSA95854
  から作成 (`Local/local.pretty`)。基板上端寄り、ケーブルは上から挿す (ハウジング前端は基板端から 2.5 mm 内側)。
  rev A の当初は TE 1-84952-5 だったが JLC 在庫が 1 個のため変更 (接点列の位置は同じ = 配線は無変更)
- CSI 3 対: 差動 100Ω (Pmod_DisplayPort と同じ Link クラス 0.1661 / 0.127 mm)、
  F.Cu のみ・ビアなし、B.Cu は全面 GND (3.3V の短いストラップは I2C の下だけ)。
  P/N の長さ差 ~2.5 mm (~17 ps) は 1 Gbps 以下では無視できる
- F1: ポリスイッチ 0.5 A (カメラの 3.3V)、C1: 10 µF、R1/R2: I2C プルアップ 2.2k、R3: CAM_GPIO プルアップ 10k
- 直列抵抗・AC 結合・バイアス抵抗なし (D-PHY は DC 結合が必須、終端は FPGA 内蔵)

## ピン割り当て

| Pmod | 信号 | FFC | Tang Primer 25K (pmod0) |
|---|---|---|---|
| 1 / 7 | SCL / SDA | 13 / 14 | F5 / G5 |
| 2 / 8 | CLK P / N | 9 / 8 | G7 / G8 |
| 3 / 9 | D1 P / N | 6 / 5 | H8 / H7 |
| 4 / 10 | D0 P / N | 3 / 2 | H5 / J5 |
| 5, 11 | GND | 1, 4, 7, 10, MP | |
| 6, 12 | 3.3 V | 15 (F1 経由) | |
| — | CAM_GPIO | 11 | R3 で 3.3 V へ (カメラは Pmod 給電で即起動) |
| — | CAM_CLK | 12 | 未接続 |

FFC のピン配置は Raspberry Pi 4 公式回路図 (J3 CAMERA) で確認。Pmod 上の並び (CLK, D1, D0) は
FFC 上の並びと同じ順にして、差動対が交差しないようにしてある (FPGA の `pins.cst` も同じ割り当て)。
FPGA 側の定義は `mod/pmod_rpi_camera/pmod_pins.csv`。

## ケーブルの向き

公式資料から確認済み:
- 標準カメラケーブル (Raspberry Pi RP-008146) は**両端で接点の面が逆** (片端は上面、もう片端は下面)
- カメラ側 J1 (SFW15R-1STE1LF) も本基板の J2 も**下面接点で、ピン 1 の位置の約束が同じ**
  (FCI JSA95855: 実装面から見て、ケーブル挿入口を手前にしたときピン 1 が左)

同じコネクタ同士を両端逆面のケーブルでつなぐと、基板の向きによらず **ピン n ↔ ピン n** になる
(3.3V は 15 番どうし、GND は 1 番どうし)。カメラに付属の標準ケーブルを使うこと。
**両端が同じ面の社外ケーブル**では逆転し、本基板の 3.3V (15 番) がカメラの GND に当たる (F1 が制限する)。

念のための確認 (カメラをつながずに): ケーブルを J2 に挿し、ケーブル反対端の導体 1 番と Pmod の GND (5/11 番) の
導通をテスタで見る。導通すれば正しい。

## 製造データ

`tools/build.sh` が ERC / DRC (回路図との一致、ベタ再充填込み) を通してから `fab/` を作る:

| ファイル | 内容 |
|---|---|
| `fab/Pmod_RPiCamera_gerber.zip` | ガーバー (F/B Cu, Mask, Silk, F.Paste, Edge) + ドリル (PTH/NPTH 別) |
| `fab/Pmod_RPiCamera_bom.csv` | 部品表 (LCSC 番号、MPN 付き) |
| `fab/Pmod_RPiCamera_pos.csv` | 実装位置 (表面のみ、原点は基板左下) |
| `fab/jlc/Pmod_RPiCamera_jlc_bom.csv`, `..._jlc_cpl.csv` | JLCPCB 実装用 BOM / CPL (LCSC 番号のある部品のみ。J1 は手はんだ想定で除外) |
| `fab/Pmod_RPiCamera_schematic.pdf` | 回路図 |
| `fab/*.png` | 3D レンダリング |
| `fab/erc.rpt`, `fab/drc.rpt` | 検査結果 (ライブラリ表の警告はヘッドレス環境由来) |

回路図・基板の初版は `tools/gen_sch.py` / `tools/gen_pcb.py` で生成し、その後 KiCad で手を入れている
(rev A: P 側の等長化ミアンダ、ティアドロップ、ロゴ、J2 を SFW15R-1STE1LF に変更、LCSC 番号)。**KiCad のファイルが正**
(スクリプトは初版の TE コネクタのまま)。`tools/build.sh` は既定で
現状のファイルを検査して出力するだけ。`--regen` を付けるとスクリプトから作り直し、KiCad での修正は消える。

## 部品 (JLCPCB 在庫は 2026-10-18 時点)

| Ref | 部品 | LCSC | 備考 |
|---|---|---|---|
| J1 | 2x6 2.54 mm 直角ピンヘッダ | — | 手はんだ想定。JLC で載せるならピン長・本体寸法をフットプリントと照合 (候補 C41417354) |
| J2 | Amphenol SFW15R-1STE1LF | C3168538 | 在庫 9,155、Extended |
| F1 | RUILON SMD0805P050TF (I_hold 0.5 A, 6 V) | C20978 | 代替 Littelfuse 0805L050WR (C207022) |
| C1 | Samsung CL21A106KAYNNNE (10 µF 25 V X5R 0805) | C15850 | Basic |
| R1, R2 | UNI-ROYAL 0402WGF2201TCE (2.2 kΩ) | C25879 | Basic |
| R3 | UNI-ROYAL 0402WGF1002TCE (10 kΩ) | C25744 | Basic |

JLC の配置プレビューで J2 の回転・原点を確認すること (KiCad のフットプリント原点は接点列の中心。
JLC 側のモデル原点と違う場合はオフセットが出る)。J2 の 3D モデルは無い (3D 画像に J2 は写らない)。

## 未確定事項

- 差動インピーダンスは DP 基板の実績値を流用 (2 層 1.6 mm でのペア結合主体)。製造業者のスタックアップで要再計算
- カメラ v2 の消費電流 (~250 mA 程度の見込み、未実測) に対する F1 の定格と電圧降下
- GW5A LVDS25 入力のコモンモード下限 (SLVS-200 は ~200 mV) は FPGA 側の最大リスク (`../../README.md`)
