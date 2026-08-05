# Type-C Alt Mode ソース基板 — KiCad設計ノート

構成: FUSB302B (PD PHY) + HD3SS460 (Alt Mode mux)。
Tang Primer 25K + 既存DPソースIP (I2Cマスタ/仮想HPD実装済み) 前提。

## 1. 主要ネット接続表

### HD3SS460 (RHR/WQFN-28)

| HD3SS460ピン | 接続先 | 備考 |
|---|---|---|
| LnA± | FPGA ML0± (100nF AC結合をFPGA側近傍に) | 4レーンDPモード時 ML0 |
| LnB± | FPGA ML1± (同上) | ML1 |
| LnC± | FPGA ML2± (同上) | ML2 |
| LnD± | FPGA ML3± (同上) | ML3 |
| CTX1±/CRX1± | USB-C TX1±/RX1± | コネクタ側そのまま |
| CTX2±/CRX2± | USB-C TX2±/RX2± | 〃 |
| SSTX±/SSRX± | 未使用 (USB3非搭載) | 未接続可 (DS推奨処理に従う) |
| AUXP/AUXN (低速ポート) | FPGA AUX± + バイアス網 | SBUクロスは内蔵 |
| SBU1/SBU2 | USB-C SBU1/SBU2 | |
| AMSEL | プルで「4レーンDP」固定 (将来FW制御ならGPIOへ) | Assignment C専用 |
| POL | FPGA GPIO (cpu_io_out空きビット) | FUSB302Bの向き判定を反映 |
| EN | FPGA GPIO | 未確定時ディセーブル |
| VCC | 3.3V | パスコン100nF+1uF |

### FUSB302B (WLCSP9/MLP)

| ピン | 接続先 | 備考 |
|---|---|---|
| CC1/CC2 | USB-C CC1/CC2 | 直結 (Rp/Rd/VCONNは内蔵切替) |
| SDA/SCL | FPGA I2C (実装済みマスタ, 400kHz) | 2.2k〜4.7kプルアップ to 3.3V |
| INT_N | FPGA GPIO入力 (無ければ未接続でポーリング運用) | 10kプルアップ |
| VBUS | USB-C VBUS (検出用) | |
| VDD | 3.3V | |

### 電源系

| ネット | 内容 |
|---|---|
| VBUS_SRC | 5V → ロードスイッチ (電流制限付, 例 AP22653/TPS25200) → USB-C VBUS。EN=FPGA GPIO |
| VCONN | FUSB302B内蔵スイッチで CC1/CC2 へ (外部部品不要, 供給元3.3V→302BのVCONN入力) |
| 3.3V | HD3SS460 / FUSB302B / プルアップ類 |

### FPGA側の必要ピン(ドック側割当は要決定)

- ML0±..ML3± (高速差動 8本) — 現Pmod DPと同じバンク/規格 (LVDS25 + 外部AC結合)
- AUX± (2本, TLVDS_IOBUF運用 + バイアス: AUX+ 100kΩ PD / AUX− 100kΩ PU)
- I2C SDA/SCL (2本, オープンドレイン運用)
- GPIO: POL, EN(HD3SS460), VBUS_EN (+INT_N入力を確保できれば+1)

## 2. 設計チェックリスト

- [ ] SS差動ペア: 目標差動インピーダンス 90Ω (USB-C規格 85–95Ω)。DP単体の100Ωではない点に注意
- [ ] ペア内スキュー ≤ 5mil程度で長さ合わせ。RBR 1.62Gbpsなので裕度は大きいがペア内は揃える
- [ ] AC結合 100nF (0201/0402) はソース(FPGA)側に配置、パッド段差最小
- [ ] HD3SS460の未使用SS側ポート処理はデータシートの指示に従う
- [ ] SBU/AUX: 低速 (1MHz Manchester)。特性インピーダンス管理不要、ただしバイアス抵抗を忘れない
- [ ] CCライン: FUSB302Bへ直結。コネクタ近傍にESD (CC/SBU/SS: 例 TPD4E05U06系, CC/SBUは24Vトレラント品 FUSB251も可)
- [ ] VBUS: 逆流防止/電流制限。コールドソケット時にVBUSを出さない (FW/EN制御, デフォルトOFFのプル)
- [ ] USB2.0 D± は未接続 (映像専用。Billboard非搭載の割り切りを明記)
- [ ] レセプタクル: ミッドマウント/トップマウントのフットプリント確認、シェルGND縫い
- [ ] 電源シーケンス: 3.3V→EN類はFPGAコンフィグ完了後にFWがアサート

## 3. FW制御シーケンス(対応表)

1. 起動: EN=0, VBUS_EN=0, POL=X
2. FUSB302B初期化 (I2C) → Rp提示、アタッチ待ち
3. アタッチ: CC測定で向き判定 → POL設定 → EN=1 → VBUS_EN=1
4. PD契約 (Source Cap 5V) → VDM (Discover→Enter Mode→Configure C)
5. Attention→仮想HPD (SYSTEM HPD bit4) → 既存DPブリングアップ合流


## 4. 回路接続構成(回路図作成用の結線ガイド)

### 4.0 全体トポロジ

```
                                 +---------------------+
  FPGA ML0± ──100nF×2──> LnA± ──|                     |── CTX1± ──> [C] A2/A3   (TX1)
  FPGA ML1± ──100nF×2──> LnB± ──|                     |── CRX1± ──> [C] B10/B11 (RX1)
  FPGA ML2± ──100nF×2──> LnC± ──|      HD3SS460       |── CTX2± ──> [C] B2/B3   (TX2)
  FPGA ML3± ──100nF×2──> LnD± ──|  (4L DP + SBU mux)  |── CRX2± ──> [C] A10/A11 (RX2)
  FPGA AUX± ──バイアス網──> AUX側低速ポート ──|       |── SBU1/2 ──> [C] A8/B8
  FPGA GPIO(POL) ──────────> POL |                     |
  FPGA GPIO(EN)  ──────────> EN  |   AMSEL=4レーンDP固定(ストラップ)
                                 +---------------------+

  [C] A5 (CC1) ─────直結───── FUSB302B CC1
  [C] B5 (CC2) ─────直結───── FUSB302B CC2
  FPGA SDA/SCL ──4.7kプルアップ── FUSB302B SDA/SCL
  FPGA GPIO入力(任意) <──10kPU── FUSB302B INT_N
  [C] VBUS(A4,B9,A9,B4) <── ロードスイッチ <──EN=FPGA GPIO(VBUS_EN)── 5V
  FUSB302B VBUS ピン ──── VBUSネットへ (検出用)
  [C] D+/D-(A6/A7,B6/B7): 未接続 / [C] GND(A1,B1,A12,B12)+シェル: GND
```

### 4.1 Type-Cレセプタクル

| ピン | ネット | 備考 |
|---|---|---|
| A1,B1,A12,B12 | GND | シェルもGNDへ(ビア縫い) |
| A4,B9,A9,B4 | VBUS | 4ピン全て結線。ロードスイッチ出力 |
| A5 | CC1 | FUSB302B CC1へ直結(抵抗なし。Rp/VCONNはチップ内蔵) |
| B5 | CC2 | FUSB302B CC2へ直結 |
| A6/A7, B6/B7 | (D±) 未接続 | 映像専用の割り切り。フロートで可 |
| A2/A3 | TX1± → HD3SS460 CTX1± | SS高速ペア。90Ω差動 |
| B10/B11 | RX1± → HD3SS460 CRX1± | 〃 |
| B2/B3 | TX2± → HD3SS460 CTX2± | 〃 |
| A10/A11 | RX2± → HD3SS460 CRX2± | 〃 |
| A8/B8 | SBU1/SBU2 → HD3SS460 SBUポート | 低速。インピーダンス管理不要 |

### 4.2 HD3SS460

- **コネクタ側**: CTX1/CRX1/CTX2/CRX2 を上表どおりレセプタクルSSピンへ
- **システム側(DPレーン)**: LnA..LnD ← FPGA ML0..ML3(各線100nF AC結合、
  コンデンサはFPGA側に配置)
  - **LnA..D と ML0..3 の対応順はデータシートの4-Lane DPアプリケーション
    図(および Ln↔コネクタポートのマッピング表)から転記すること**。
    レーン順を誤ると映像が出ない(RTL側にレーンスワップ機能はない)
- **システム側(USB3)**: SSTX/SSRX ペアは未使用。データシート指定の
  未使用ポート処理に従う(通常フロート可)
- **SBU/AUX**: FPGA AUX±+バイアス網(§4.4)→AUX側低速ポート、
  SBU1/2→レセプタクル。表裏の入替えはPOLに連動してチップが行う
- **制御**:
  - AMSEL: 「4レーンDPモード」になる論理レベルへ**抵抗ストラップで固定**
    (レベルはデータシートのモード表から。将来D対応時はFPGA GPIOへ変更)
  - POL: FPGA GPIO(cpu_io_out bit25)。**10kプルダウン**を付け未確定時の
    レベルを定義
  - EN: FPGA GPIO(bit24)。**10kプルダウン**(FPGAコンフィグ前はmux無効 =
    Hi-Zで安全)
- 電源: 3.3V、パスコン 100nF×2 + 1µF

### 4.3 FUSB302B

| ピン | ネット | 備考 |
|---|---|---|
| CC1 / CC2 | レセプタクル A5 / B5 | 直結。VCONN供給もこのピン経由(チップ内スイッチ、電源はVDD=3.3V) |
| SDA / SCL | FPGA I2C | 3.3Vへ4.7kΩプルアップ各1 |
| INT_N | FPGA GPIO入力(確保できる場合) | 10kプルアップ。未接続でもポーリング運用可 |
| VBUS | VBUSネット | 検出用。直結で可 |
| VDD | 3.3V | 100nF + 1µF |
| GND | GND | |

### 4.4 AUXバイアス網(§1と同じ、再掲)

- FPGA側(AC結合の内側): 各線 100kΩ↑3.3V + 100kΩ↓GND(中点バイアス)
- AC結合: AUX_P/AUX_N 各 100nF
- コネクタ側(=HD3SS460のAUXポート側): AUX_P 100kΩ↓GND、
  AUX_N 100kΩ↑3.3V(ソース側規定極性)
- オプション: 各線に直列0Ω(デバッグ用切り離し)

### 4.5 VBUS系

- 5V入力 → 電流制限ロードスイッチ(AP22653等) → VBUSネット
- スイッチEN = FPGA GPIO(bit26)、**10kプルダウン**(コールドソケット時OFF)
- オプション: VBUSに10kΩブリード抵抗(取り外し時の放電)

### 4.6 デフォルト状態の設計(重要)

FPGAコンフィグ完了までの間、基板が安全な状態であること:
- EN(mux)=L、VBUS_EN=L となるよう全制御GPIOにプルダウン
- FUSB302BはPOR後アイドル(Rp提示はFWが設定するまで無し)→
  相手ホストから見て「何も繋がっていない」状態が保たれる

## 5. 実基板回路図レビュー結果 (2026-08-06, ネットリスト復元による)

対象: `eda/display_port_typec/Pmod_DisplayPort.kicad_sch`
構成: J1=レーンPmod, J2=AUX側Pmod, J3=USB-C, J4=USB-C給電専用(Rd 5.1k),
J5=USB2ブレークアウト, CN1=DPコネクタ, JP1=HPD/INT_N結合ジャンパ

確認OK:
- AUXバイアス網は§4.4どおり (FPGA側100k/100k中点、線路側P:100k↓/N:100k↑)
- レーン: FPGA→100nF→[DPコネクタ ∥ HD3SS460 LnA-D] のティー分岐。
  ML0-3→LnA-D、CTX/CRX→レセプタクルSSピンは正順
- CC: FUSB302B直結+470pF (PD実通信で動作確認済み)、I2C 4.7k↑3V3
- DP_PWR=3V3直結、CONFIG1/2=GND

設計ノートとの相違・注意点:
- **EN/POL/AMSEL は10kプルアップ(3V3)** — §4.6の「プルダウンで安全側」と
  逆。FPGAコンフィグ前はmuxが有効(EN=1,POL=1,AMSEL=1)になる
- **VBUSはJ4から常時直結**(ロードスイッチなし)。VBUS_EN GPIO(bit26)は
  未接続で無効。コールドソケットでVBUS印加あり(ベンチ用途は割り切り)
- FUSB302BのVCONNはVBUS(5V)直結 — 定格内(2.7-5.5V)だが給電はVBUS依存
- JP1: DPコネクタのHPD(R14 10k経由)とFUSB302B INT_N(R25 4.7k↑)を同一
  Pmodピンに結合。DPコネクタでHPDを使う場合はJP1開放、Type-C運用
  (INT_Nポーリング/未使用)ではどちらでも可
- レーンFPGA側の10k VCM(1.65V)バイアス(R31-38)は不要だが実害なし
- DPコネクタ経路は muxへの分岐トレースが常設スタブとなり1.62Gbps CRが
  通らない実測結果。次版では分岐に0Ω/結合C挿入で切り離し可能にする
