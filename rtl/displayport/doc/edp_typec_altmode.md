# eDP 対応 / USB Type-C DP Alt Mode 対応の検討

現行資産 (DP 1.2 Source, RBR 1.62Gbps / 1レーン, Tang Primer 25K + Pmod DP,
FemtoRV32 FW によるリンクポリシー) を出発点に、(1) eDP パネル直結、
(2) USB Type-C DP Alternate Mode ソース、それぞれに必要な回路上の課題と
論理回路構成の変更を整理する。

---

## 1. eDP 対応

eDP はプロトコル的には DP のサブセット+拡張であり、メインリンク/AUX/8b10b/
フレーミングはそのまま流用できる。差分は主に「パネルは常時接続の既知デバイス」
であることに由来する。

### 1.1 回路上の課題

| 項目 | 内容 |
|---|---|
| コネクタ | eDP パネルは 30/40 ピン FPC (I-PEX 20453/20455 系など)。Pmod DP からの変換基板が必要。レーン数/ピン配置はパネルデータシート依存 |
| 電源シーケンス | パネル VDD (3.3V) → AUX/メインリンク → バックライトの順序と T1〜T12 タイミング制約 (eDP 規格 §T-parameters)。違反するとパネルが応答しない/劣化する。電源イネーブル用 FET スイッチと GPIO 制御が必要 |
| バックライト | LED ドライバ (昇圧、定電流) が別途必要。調光は PWM ピンまたは AUX (DPCD 0x720 系 backlight control) |
| 信号振幅 | eDP は低振幅スイング (200mV 級) が既定。現行 TLVDS_OBUF の振幅 (約350mV) はレシーバ耐性的には通常問題ないが、パネルによっては上限確認が必要 |
| HPD | パネルの HPD は「パネル準備完了」通知 (ホットプラグではない)。プルダウン/レベルは現行回路のままで可 |
| AUX プルアップ/ダウン | 現行 Pmod と同じ (AUX は 1Mbps Manchester、変更なし) |

### 1.2 論理回路 (RTL) の変更

1. **ASSR (Alternate Scrambler Seed Reset)** — 最重要。多くの eDP パネルは
   ASSR 必須 (eDP セキュリティ要件)。SR 受信時のスクランブラシード初期値を
   0xFFFF → **0xFFFE** に切り替える。
   - `scrambler.veryl`: シード定数を入力ポート化 (1 ビット選択で十分)
   - `main_link_tx_lane` 経由で CPU レジスタ (MAIN_LINK CTRL の空きビット) に接続
   - FW: DPCD 0x0000D (eDP_CONFIGURATION_CAP) を読み、0x0010A
     (eDP_CONFIGURATION_SET) bit0 で ASSR 有効化してからトレーニング
   - CDC: 準静的 (トレーニング前に設定) なので既存の 2FF 同期+false path 方式
2. **Fast Link Training / No-AUX training (任意)** — パネルが
   NO_AUX_HANDSHAKE_LINK_TRAINING に対応する場合、AUX 応答を待たず固定時間で
   TPS1→TPS2→通常動作に遷移できる。RTL 変更は不要 (パターン切替は既存レジスタ)
   で、FW のシーケンス追加のみ
3. **中間リンクレート (任意)** — eDP 1.4 の 2.16/2.43/3.24Gbps 等は PLL/OSER の
   再設計になるため当面対象外。RBR/1 レーンで一般的な HD 未満のパネルを駆動する
   場合は変更不要 (帯域: RBR 1 レーンで 1366x768@60 8bpp は不可、1024x600@60 等
   は可 — パネル選定に制約)
4. **バックライト/電源 GPIO** — cpu_io_out の空きビットをトップレベルで
   パネル電源/バックライトイネーブルに割当て (RTL は配線のみ)。PWM 調光を
   FPGA で行うなら小さな PWM モジュールを追加

### 1.3 FW の変更

- 電源シーケンサ (T1〜T12 のタイマ、GPIO 制御)
- ASSR 設定 → (Fast) リンクトレーニング → 映像有効化
- EDID が無いパネルへの対応 (タイミングを FW 定数で保持 — 現行の
  VideoConfig 方式そのままで適合)
- バックライト制御 (PWM duty または DPCD 0x720 系)

### 1.4 まとめ (eDP)

RTL 差分は実質 **ASSR のシード切替 1 点**。残りは基板 (電源シーケンス、
バックライト、コネクタ) と FW。現行アーキテクチャの半レートモード
(27Mpix) / フルレート (54Mpix) の制約内で駆動できるパネルを選ぶのが現実的。

---

## 2. USB Type-C DP Alternate Mode (ソース側)

Alt Mode は「DP 信号を Type-C コネクタのピンに載せ替える」仕組みで、
メインリンク/AUX のプロトコル自体は不変。課題のほぼ全てが
**USB PD (Power Delivery) ネゴシエーションと物理的なレーン切替** にある。

### 2.1 回路上の課題

| 項目 | 内容 |
|---|---|
| PD PHY | CC ライン上の BMC 変調 PD 通信は FPGA 直結不可 (1.2V 系アナログ)。PD PHY チップが必須。選択肢: (a) FUSB302B (I2C, PD スタックはホスト側=FW 実装)、(b) CYPD3125/STUSB4500 系スタンドアロン PD コントローラ (Alt Mode VDM まで自律処理する品種は限られる)、(c) TI TPS65982 等フル機能 PD+mux 統合 (BGA、入手性難) |
| 表裏反転 (orientation) | Type-C は表裏どちらでも挿せる。DP レーンを CC 判定結果に応じて物理的に入れ替える **SS mux (例: TI HD3SS460, PI3USB30532)** が必要。FPGA の出力ピンを 2 組用意して論理側で切り替える案は、82ns 級の高速差動を 2 系統引き回すことになり基板設計負荷が大きい → mux チップ推奨 |
| ピンアサイン | DP Alt Mode Pin Assignment C (4 レーン DP) / D (2 レーン DP + USB3)。現行 1 レーンでも「C の Lane0 のみ駆動」で成立する (シンク側は Configure で通知されたアサインの Lane0 から使う) |
| AUX の配線 | Type-C では AUX は SBU1/SBU2 に割当て。orientation で SBU も入れ替わるため、SS mux か専用 SBU スイッチ (例: HD3SS3220 内蔵、または FSA4159 級アナログ SW) が必要 |
| HPD | 物理ピンが存在しない。シンク→ソースの HPD/IRQ は **PD の Attention/Status Update VDM** で通知される。PD コントローラ経由で FW に伝える |
| VBUS/VCONN | ソースとして最低 5V VBUS 供給 (Rp 提示)。VCONN (E-Marker ケーブル給電) も規格上必要 |

### 2.2 論理回路 (RTL) の変更

1. **メインリンク/AUX: 変更ほぼ不要**。1 レーン RBR のままなら信号は現行と同一。
   将来 2 レーン (Pin Assignment D) に広げる場合はレーン複製 (roadmap の
   マルチレーン項目) が先行課題
2. **HPD の仮想化** — 現行 `hpd_in` は物理ピン前提。Alt Mode では PD
   コントローラからの通知 (I2C 読出し or 割込み) を FW が受け、
   仮想 HPD として扱う必要がある。
   - 案: SYSTEM レジスタに「FW が書ける仮想 HPD ビット」を追加し、
     `aux_ch_subsystem` の HPD 検出器の入力を `hpd_in | hpd_virtual`
     (または選択 mux) にする — 小規模な RTL 変更
   - HPD パルス幅分類 (IRQ/unplug) は PD の Attention メッセージ側で
     判別済みなので、仮想 HPD では分類器をバイパスするレジスタ経路が素直
3. **I2C マスタ** — PD PHY (FUSB302 等) 制御用。FemtoRV32 のレジスタ空間に
   I2C マスタペリフェラルを追加 (ソフト I2C を cpu_io_out の GPIO ビットで
   実装する手もあり、PD のタイミング要件的には HW マスタ推奨)
4. **レーン極性/順序反転 (保険)** — mux チップを使わず基板で反転を吸収する
   構成を選ぶ場合、10b シンボルのビット順反転・P/N 反転オプションを
   シリアライザ手前に入れる (数行の組合せ回路)。HD3SS460 採用なら不要

### 2.3 FW の変更 (最大の作業項目)

- **USB PD スタック**: Source ポリシー (Rp 提示、Source Capabilities、契約成立)
- **VDM シーケンス**: Discover Identity → Discover SVIDs (0xFF01 = DisplayPort)
  → Discover Modes → Enter Mode → DP Status Update → **DP Configure**
  (ピンアサイン C を指定) → mux/orientation 設定 → 以降は通常の DP ブリングアップ
- Attention 受信 → 仮想 HPD/IRQ_HPD への反映
- FUSB302 採用時は PD スタックを自前実装 (数千行規模、ただし
  ソース固定・Alt Mode 固定に絞れば大幅に削減可能)。
  スタンドアロン PD コントローラ採用ならレジスタ設定のみに縮む

### 2.4 段階案

1. **Step 0 (回路PoC)**: 市販の「Type-C → DP 変換基板 (シンク方向)」を逆用は
   不可 (方向が逆) — ソース用には PD コントローラ+mux 搭載の自作基板か、
   Alt Mode ホスト評価ボードが必要。まず FUSB302B + HD3SS460 + Type-C
   レセプタクルの小基板を起こすのが現実的
2. **Step 1**: 仮想 HPD レジスタ + I2C マスタを RTL に追加 (eDP とは独立、
   シミュレーションで検証可能)
3. **Step 2**: PD スタック FW (Source 固定、PD2.0 レベルで可) + VDM
4. **Step 3**: 実機で Configure 後に既存 DP ブリングアップへ接続

### 2.5 まとめ (Type-C)

RTL 差分は **仮想 HPD と I2C マスタの追加程度**で小さい。支配的なのは
(a) PD PHY / SS mux を載せた回路 (Pmod では完結しない、専用基板が必要) と
(b) PD/VDM の FW スタック。スタンドアロン PD コントローラを選べば FW も
大幅に軽くなるが、Alt Mode ソースを自律処理できる石の選定が鍵。

---

## 3. 共通の示唆

- どちらも**メインリンク RTL は現行のまま通用**する (eDP は ASSR のみ追加)。
  現在の 480p 半レートモード/タイミングクローズ資産はそのまま活きる
- 先行して入れておくと両対応が楽になる RTL 変更:
  1. スクランブラシード選択 (ASSR) — 1 ビット
  2. 仮想 HPD レジスタ経路 — SYSTEM レジスタ 1 ビット+mux
  3. I2C マスタペリフェラル (PD PHY 用、eDP でも外部 EEPROM/センサ流用可)
- 帯域は RBR×1 レーンが上限 (有効 1.296Gbps ≒ 54Mpix @24bpp)。eDP パネルや
  Alt Mode モニタで実用解像度を出すにはマルチレーン化 (roadmap 既載) が
  中期課題になる
