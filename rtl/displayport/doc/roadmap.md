# DisplayPort 1.2 Source IP — 実装ロードマップ

## 1. 概要と前提

本ドキュメントは [rtl/displayport/](../) に存在する作りかけの DisplayPort IP について、残作業を段階的に実装していくための方針をまとめたものである。

仕様書: [DP-1.2.pdf](DP-1.2.pdf) (VESA DisplayPort Standard Version 1, Revision 2)
本ドキュメント中の「§N.N」「Tab N-N」「Fig N-N」「App X」は、すべて上記仕様書の節番号・図表番号・付録への参照である。

確定済スコープ:

| 項目 | 値 |
|------|----|
| 方向 | Source (TX) のみ |
| リンクレート | RBR (1.62 Gbps/lane) のみ |
| ストリーム形態 | SST のみ (MST 非対応) |
| シミュレータ | Veryl 内蔵シミュレータ (`veryl test`)、テストベンチは `.veryl` で記述 |
| FPGA 実装 | 後回し。10:1 シリアライザ等のベンダ依存部はラッパで抽象化 |

対象外 (将来拡張): Audio SDP (§2.2.5)、HBR/HBR2、MST、HDCP、eDP 専用機能。

## 2. 現状サマリ (既存資産)

[src/](../src/) に以下が揃っている。`.sv` ファイルは Veryl からの自動生成物なので、ソース・オブ・トゥルースは `.veryl` 側。

| ファイル | 役割 |
|----------|------|
| [aux_ch_tx.veryl](../src/aux_ch_tx.veryl) | AUX CH 送信機 (Manchester-II 符号化、PRECHARGE / SYNC / TRANSMIT / STOP) |
| [aux_ch_rx.veryl](../src/aux_ch_rx.veryl) | AUX CH 受信機 (Manchester-II 復号、エッジ追従) |
| [aux_ch_peripheral.veryl](../src/aux_ch_peripheral.veryl) | 256 B 共有バッファ + 制御レジスタ (OPERATION_STATUS, RX/TX_COUNT/INDEX, INTERRUPT_STATUS) |
| [aux_ch_subsystem.veryl](../src/aux_ch_subsystem.veryl) | FemtoRV32 + メモリマップ + AUX ペリフェラル |
| [aux_ch_subsystem_picorv32.veryl](../src/aux_ch_subsystem_picorv32.veryl) | PicoRV32 版サブシステム |
| [stream_memory_access.veryl](../src/stream_memory_access.veryl) | シリアル経由でのメモリ書込み (ファームロード用) |

ファーム ([test/sw-rs/](../test/sw-rs/)、Rust): `requester_process` / `replier_process` を実装。Native AUX の Read/Write、ACK/NACK/DEFER 応答が形になっている。DPCD はハードコードのデモ値のみ。

テストベンチ ([test/](../test/)): `tb_aux_ch.sv`、`tb_aux_ch_tx.sv`、`tb_aux_ch_subsystem.sv` (現状は SystemVerilog)。今後追加分は `.veryl` で記述する。

未実装: メインリンク全体、HPD、リンクトレーニング、DPCD/EDID 取得シーケンス、MSA/TU 生成、映像入力。

## 3. DP 1.2 Source SST のレイヤ構造

仕様書 §1.7.4 (Fig 1-2) と §2.1 (Fig 2-1) を踏まえると、ソース機の機能は次のレイヤに分けられる。本 IP の最終形を図示する:

```
+------------------------------ Application -----------------------------+
| Video pixel stream (AXI-Stream)             Audio (将来)                |
+------------------------------ Link Layer ------------------------------+
|  MSA gen (§2.2.4) | TU packer (§2.2.1) | SDP (§2.2.5、将来)             |
|  Lane distribution / control symbol insertion (Tab 2-1)                |
+------------------------------ Physical Layer --------------------------+
|  Scrambler (§3.1.6, App E)  |  8B/10B encoder (§3.1.7, Tab 3-5)         |
|  Training pattern gen (§3.5.1, Tab 3-16)                               |
|  Serializer 10:1  --  1.62 Gbps × N lanes (RBR)                        |
+------------------------------------------------------------------------+
|  AUX CH (実装済)              |  HPD detect (§3.3, Tab 3-4)             |
+------------------------------------------------------------------------+
|  CPU (FemtoRV32) firmware                                              |
|    - HPD イベント → リンク起動                                         |
|    - DPCD/EDID 読み出し                                                |
|    - リンクトレーニング SM (§3.5, App C)                                |
+------------------------------------------------------------------------+
```

## 4. 未実装機能の分解と仕様参照

| # | 機能 | 仕様節 | 実装場所 | 備考 |
|---|------|--------|----------|------|
| 1 | HPD 検出 | §3.3, Tab 3-4 | RTL (簡易) + FW (イベント処理) | パルス幅で disconnect / IRQ 区別 |
| 2 | DPCD 取得 | §2.9.3, Tab 2-75 | FW のみ (Source 側はリードのみ) | Sink の応答を保持するキャッシュ |
| 3 | EDID 読出し | §2.7.5 (I²C-over-AUX) | FW のみ | 既存 AUX requester を拡張 |
| 4 | リンクトレーニング | §3.5, App C, Fig 3-32/33 | FW 主体 + RTL のパターン切替 | Clock Recovery → Channel EQ |
| 5 | トレーニングパターン生成 | §3.5.1, Tab 3-16 | RTL | TPS1 / TPS2 / TPS3 / IDLE |
| 6 | スクランブラ | §3.1.6, App E | RTL | LFSR (`x^16 + x^5 + x^4 + x^3 + 1`)、SR でリセット |
| 7 | 8B/10B エンコーダ | §3.1.7, Tab 3-5 | RTL | D-code / K-code 区別、RD ステート保持 |
| 8 | 制御シンボル挿入 | §2.2, Tab 2-1 | RTL | BS, BE, SR, FS, FE, SS, SE |
| 9 | レーン分配 | §2.2.1, Fig 2-10 | RTL | 1 / 2 / 4 レーン構成 |
| 10 | MSA 生成 | §2.2.4, Fig 2-12, Tab 2-3 | RTL (CPU が値設定) | Mvid, Nvid, HTotal 他 |
| 11 | TU パッキング | §2.2.1, Fig 2-13, Tab 2-44 | RTL | TU=64 シンボル、有効データ + FE で詰める |
| 12 | ストリームクロック (Mvid/Nvid) | §2.2.3, Fig 2-16/17 | RTL (M/N 計測カウンタ) | 非同期クロックモード対応 |
| 13 | 10:1 シリアライザ | §3.1.7 | RTL ラッパ + Sim ビヘイビア | FPGA 化時に GT/OSER10 に差替 |
| 14 | AUX/メインリンク調停 | §2.3 | RTL (薄いステートマシン) | AUX 中もメインリンクは独立に進行可 |

## 5. 段階的実装ロードマップ

依存関係を踏まえた 5 フェーズ。各フェーズ末で `veryl test` がパスすることをマイルストンにする。

### Phase A — HPD と DPCD/EDID 取得 (FW 中心)

- HPD 入力端子を持つ薄い `dp_source_top.veryl` (将来拡張するスケルトン) を追加。デバウンスとパルス幅判定を含む
- ファームに以下を実装:
  - HPD イベント処理 (§5.1.4)
  - DPCD `00000h–000FFh` (Receiver Capability, §2.9.3) のリード
  - EDID リード (I²C アドレス `0x50`、§2.7.5)
- 既存 AUX サブシステムをそのまま使用
- TB: 模擬 sink (AUX replier) を `.veryl` で記述し、HPD↑ → DPCD/EDID 取得シナリオを再生

### Phase B — メインリンク PHY 部品 (RTL 単体)

- `scrambler.veryl`: 16-bit LFSR、SR シンボル受信時にリセット (App E の C コード相当)
- `encoder_8b10b.veryl`: D-code / K-code、Running Disparity ステート、Tab 3-5 のゴールデンベクタで検証
- `link_symbol_mux.veryl`: D/K の選択と制御シンボル (BS, BE, SR, FS, FE, SS, SE) の差し込み
- `serializer_10to1.veryl`: シミュレーション用ビット出力。FPGA 化時に OSER10/OSERDES に差し替えるためのインタフェースを切る
- 単体 TB を `.veryl` で書き、仕様書サンプル列との bit-exact 比較

### Phase C — トレーニングパターンとリンクトレーニング

- `training_pattern_gen.veryl`: TPS1 (D10.2 連続)、TPS2、TPS3、IDLE パターンの生成 (Tab 3-16)
- `main_link_tx_ctrl.veryl`: CPU から
  - 現在のパターン
  - 電圧スイング / プリエンファシス値 (RBR では情報出力のみ、PHY モデル側で消費)
  - レーン数 (1/2/4)
  - スクランブラ enable
  
  を制御するレジスタ群
- ファームに ANSI リンクトレーニング SM を実装 (§3.5, Fig 3-32 = Clock Recovery、Fig 3-33 = Channel EQ):
  1. DPCD `100h` (LINK_BW_SET) と `101h` (LANE_COUNT_SET) を設定
  2. TX 側で TPS1 を出力 → DPCD `202h–207h` (LANE_STATUS) を polling
  3. 必要に応じて電圧スイングを上げて再試行 (最大 5 回)
  4. CR_DONE 確認後 TPS2 (HBR2 なら TPS3) → CHANNEL_EQ_DONE / SYMBOL_LOCKED / INTER_LANE_ALIGN_DONE 確認
  5. パターン解除 → IDLE → 通常運転
- TB: 模擬 sink がパターンに応じて LANE_STATUS を返すモデルを `.veryl` で実装

### Phase D — 映像パイプライン (RTL)

- `pixel_in.veryl`: AXI-Stream で 24bpp RGB を受信。§2.2.1 のレーンマッピング (例: Tab 2-5 24bpp 4-lane) を実装
- `msa_generator.veryl`: VBlank 区間に MSA を出力 (Fig 2-12、Tab 2-3 VB-ID)
- `transfer_unit_packer.veryl`: TU = 64 シンボル、有効データ + FE / FS、レーン跨ぎ並べ替え (Fig 2-10, 2-13)
- M/N 値生成: §2.2.3 Fig 2-16/17 に従い、Stream Clock とリンク Symbol Clock の比から Mvid / Nvid をカウント
- 暫定ターゲット: 24bpp / 2 レーン (or 4 レーン) で 720p60 まで通すこと
- TB: テストパターンを入力し、出力 10b シンボル列を仕様の例 (Tab 2-44 等) と突き合わせる

### Phase E — 統合とエンドツーエンド検証

- `dp_source_top.veryl` で AUX サブ + main link TX + HPD を結線して最終トップを完成
- 模擬 sink TB に「10b デシリアライザ + 8B/10B デコーダ + デスクランブラ + MSA 抽出器 + ピクセル復元」を実装
- ファームのトップシナリオ: HPD↑ → DPCD/EDID 取得 → リンクトレーニング → MSA + 映像 enable → 1 フレーム流す
- 受け入れ基準: 模擬 sink 側で再構成したピクセルが入力ピクセルと一致

## 6. ディレクトリ構成案

```
rtl/displayport/
├── doc/
│   ├── DP-1.2.pdf                   (取得済)
│   └── roadmap.md                   (本ドキュメント)
├── src/
│   ├── aux_ch_*.veryl               (既存)
│   ├── stream_memory_access.veryl   (既存)
│   ├── scrambler.veryl              (Phase B)
│   ├── encoder_8b10b.veryl          (Phase B)
│   ├── link_symbol_mux.veryl        (Phase B)
│   ├── serializer_10to1.veryl       (Phase B)
│   ├── training_pattern_gen.veryl   (Phase C)
│   ├── main_link_tx_ctrl.veryl      (Phase C)
│   ├── msa_generator.veryl          (Phase D)
│   ├── transfer_unit_packer.veryl   (Phase D)
│   ├── main_link_tx.veryl           (Phase D 統合)
│   └── dp_source_top.veryl          (Phase A → 拡張)
└── test/
    ├── tb_scrambler.veryl           (Phase B)
    ├── tb_8b10b.veryl               (Phase B)
    ├── tb_link_training.veryl       (Phase C)
    ├── tb_video_pipeline.veryl      (Phase D)
    ├── tb_dp_source_top.veryl       (Phase E)
    └── sw-rs/                       (拡張: link training, EDID, HPD ハンドラ)
```

## 7. 検証方針

- 各 RTL モジュールは Veryl 内蔵シミュレータ (`veryl test`) で実行する。テストベンチは `.veryl` で記述する (新規分)
- ゴールデンデータの出所:
  - 8B/10B: Tab 3-5 / Tab 3-15 の符号表
  - スクランブラ: App E の参照 C コード
  - MSA / TU: Tab 2-3、Tab 2-44 のサンプル
- 模擬 sink モデル (`.veryl`) を整備:
  - AUX replier (DPCD レジスタモデル + DEFER 応答)
  - 10b デシリアライザ + 8B/10B デコーダ + デスクランブラ
  - MSA / TU パーサで 1 フレーム再構成
- E2E 受け入れ基準: 模擬 sink で「リンクトレーニング 1 発成功 + 1 フレーム再現一致」

## 8. リスクとオープン事項

- **10:1 シリアライザの抽象化**: RBR (1.62 Gbps) でも実装は FPGA primitive (Gowin OSER10 / Xilinx OSERDES) 依存になる。シミュレーションでは bit シリアル出力をモデル化し、FPGA 移行時に差し替えるためのインタフェースを Phase B 段階で固める
- **ファーム ROM サイズ**: 現 8 kB。リンクトレーニング SM + EDID パーサ + DPCD キャッシュで足りる見込みだが、Phase C 終了時に再評価する
- **AUX クロック**: `MANCHESTER_CLOCK_HZ = 1 MHz` と仕様書値 (§3.4) との整合性を Phase A 着手時に再検証
- **電圧スイング/プリエンファシス**: シミュレーションでは数値だけ伝えれば十分だが、FPGA 移行時には外部 PHY/LVDS 出力段との結合方法を改めて検討
- **MSA の M/N 計算**: 同期/非同期モードのどちらを優先するか。最初は同期 (ピクセルクロック = ストリームクロック) で 1 フレーム流すことを優先し、非同期は Phase D 後半で追加

## 9. 仕様照合検証の結果 (2026-07)

実機検証に先立ち、仕様書との突き合わせレビューを実施した。以下は**修正済み** (テストも仕様ゴールデン値ベースに更新):

| 項目 | 仕様参照 | 修正内容 |
|------|---------|---------|
| スクランブラ LFSR 遷移式が App E と不一致 (Fibonacci 型で実装されており 2 バイト目以降全て不一致) | §3.1.6, App E (`advance(0xFFFF)=0xE817`) | Galois 型左シフトに修正。`tb_scrambler` に App E 参照値のゴールデンテスト (`scrambler_golden`) を新設 |
| K シンボルで LFSR を進めていない | §3.1.6 "The LFSR advances on all symbols, both D and K" | K / scramble_disable 中も 8 ステップ advance |
| スクランブラを毎 BS でリセット (実 Sink 非互換) | §3.1.6 (リセットは SR のみ) | TX/Sink モデルとも SR のみでリセット |
| FS/FE/SE の K コード誤り (K28.4/K28.7/K28.3 は RESERVED/CP 用) | §3.5.1.1 Table 3-15 | FS=K30.7(0xFE), FE=K23.7(0xF7), SE=K29.7(0xFD) に修正 (`link_pkg`, `tu_packer`, TB パーサ) |
| MSA が Fig 2-18 と不一致 (33 バイト・Mvid 2 回) | §2.2.4 Fig 2-18 (p76) | 1 レーン 39 シンボル構成 (SS×2 + 36 + SE、Mvid×4) に修正。golden も正解値に差し替え |
| BS 後の VB-ID/Mvid/Maud が 1 回のみ | §2.2.1 / Fig 2-11, 2-12 ("must be transported four times, regardless of the number of lanes") | video/idle 両パスで ×4 反復。TB で 4 回一致を検証 |
| アイドル VB-ID = 0x08 | Table 2-3 (bit3=1 なら bit0 も 1) | 0x09 に修正 |
| FW の MISC0=0x01 (6bpc 扱い) | Table 2-45 | 0x21 (sync + 8bpc RGB) に修正 |

**未修正の既知課題** (機能追加規模のもの):

- **Enhanced Framing Mode 未対応**: DPCD Rev 1.2+ の Sink と接続する Source は必須 (§2.2.1.1/2.2.1.2、BS→BS+BF+BF+BS の 4 シンボル列)。実モニタ接続前に要対応
- **8B/10B**: エンコーダの D.x.A7 代替符号未実装 (D11/13/14.7@RD+、D17/18/20.7@RD- の 6 値が ANSI 非準拠)。デコーダの代替符号受理・ディスパリティエラー検出なし
- **HPD**: IRQ パルス (0.5–1ms) / unplug (>2ms) の幅判別未実装、`STABLE_CYCLES` が CLOCK_HZ 非連動 (16 サイクル ≒ 160ns)、FW が plug 後の HPD/IRQ (DPCD 201h) を監視しない
- **FW 堅牢性**: AUX DEFER リトライなし (仕様は最大 7 回)、AUX 無応答時の 400µs タイムアウト未実装 (無限ループ)、CR ループの絶対上限なし、EDID 読み出し未実装
- **AUX PHY**: RX の re-arm 時 stale バイト混入ハザード、送信中の自己受信ゲートなし、TX ビットレートが `MANCHESTER_CLOCK_HZ` 非連動 (1Mbps 固定)
- **アーキテクチャ**: バイトレート = リンクシンボルレートの簡略化のため `tu_active=64` のみ整合 (tu_active<64 では MSA hwidth と実転送画素数が不一致)。M/N 計測ハードウェア未実装。MSA を全 vblank 行で送信 (仕様は once per frame)
- **テストホール**: `CONTINUOUS_BYTE_TICK=1` (FPGA/OSER10 経路) が全テスト未使用、`pixel_fifo`/`hpd_detect` の単体テストなし、AUX エラー経路 (NACK/DEFER/無応答) 未検証、8b10b の両 RD 網羅・ラン長検査なし
