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
