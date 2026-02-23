# FPGA Samples リポジトリ整理計画

**作成日**: 2026-02-23
**ステータス**: 実行中
**担当**: Claude Code

---

## 📊 現状分析

### リポジトリの概要
- **規模**: 8.0GB、630ファイル、162コミット
- **構成**: 31個のEDAプロジェクト、22個のRTLモジュール、83個のChiselモジュール
- **ブランチ**: 30個（整理が必要）
- **未追跡ファイル**: 91個（問題あり）
- **現在のブランチ**: gowin_vol5（最新機能）
- **メインブランチ**: main

### 主要ディレクトリ構成

| ディレクトリ | サイズ | 内容 |
|---|---|---|
| `/eda` | 414MB | FPGA開発プロジェクト（31個） |
| `/rtl` | 364MB | RTLモジュール（22個） |
| `/chisel` | 756KB | Chisel3モジュール（83ファイル） |
| `/riscv_cpu` | 147MB | RISC-V CPU関連 |
| `/external` | 193MB | 外部依存（Git submodules） |
| `/hls_fft` | 43MB | 高水準合成FFT |
| `/xls` | 2.7MB | XLS言語関連 |
| `/util` | 396KB | ユーティリティツール |
| `/doc` | 224KB | ドキュメント |

---

## 🔴 主要な問題点

### 1. バージョン管理の問題（重大）
- **未追跡ファイル91個**: ソースファイル、生成ファイル、設定ファイルが混在
- **ビルド成果物の追跡**: ログファイル（.log, .jou）が追跡対象に
- **巨大アーカイブ**: `xls.tar.gz` (132MB) がルートに放置 → **削除予定**
- **.gitignore不足**: EDA生成ファイル（.cst, .mod, IP/など）が未対応

#### ルートディレクトリの不要ファイル
```
xls.tar.gz (132MB)            # 削除予定
vivado_pid1479916.str (196KB) # 削除予定
y2k22_patch-1.2.zip (3.9KB)   # 削除予定
uart_test.fs (2.0MB)          # 削除予定
*.log, *.jou                  # 削除予定
```

### 2. ドキュメント不足（中）
- 31個のEDAプロジェクト中、**READMEは10個のみ（32%）**
- 大規模プロジェクトにドキュメントなし:
  - `display_controller` (31MB)
  - `cpu_matrix_led` (41MB)
  - `multi_segment_led`, `dram_test`, `blink` など

### 3. ブランチ管理（中）
- 30個のブランチ（整理が必要）
- gowin_vol5が最も進んでいるが、mainにマージされていない

---

## 🎯 整理方針

### フェーズ1: バージョン管理の改善（最優先）

#### 1.1 .gitignoreの拡充

追加すべきルール:
```gitignore
# ツールログとトレース
*.log
*.jou
*.str
*.rpt
vivado_pid*
hs_err_pid*
upgrade_project_migration_report.*

# アーカイブファイル
*.tar.gz
*.zip

# EDA生成ファイル
**/*.cst
**/*.gen.svh
**/ip/*/
**/impl/
**/project/

# IDE/ツール
.devcontainer/
.vscode-ctags
*.analyzer_prj
*.xml

# ビルド成果物
build/
output/
*.hex
*.mod
```

#### 1.2 不要ファイルの削除

即座に削除すべきファイル:
- `xls.tar.gz` (132MB)
- `y2k22_patch-1.2.zip`
- `uart_test.fs`
- `vivado_pid*.str`
- ルートの `*.log`, `*.jou` ファイル

#### 1.3 git履歴からの削除（オプション）

既にコミットされているログファイルを履歴から削除する場合:
```bash
git filter-branch --tree-filter 'rm -f *.log *.jou' HEAD
# または BFG Repo-Cleaner を使用
```

**推定効果**: 未追跡ファイル91個 → 20個程度に削減

---

### フェーズ2: ドキュメント整備

#### 2.1 プロジェクトREADMEの追加

優先度の高いプロジェクト（READMEなし）:

| 優先度 | プロジェクト | サイズ | 理由 |
|---|---|---|---|
| 🔥高 | `eda/display_controller/` | 31MB | 重要プロジェクト |
| 🔥高 | `eda/cpu_matrix_led/` | 41MB | 大規模プロジェクト |
| ⚡中 | `eda/multi_segment_led/` | 9.0MB | サンプルとして重要 |
| ⚡中 | `eda/dram_test/` | 1.4MB | テストプロジェクト |
| ⚡中 | `eda/blink/` | 2.7MB | 基本サンプル |

#### README テンプレート

```markdown
# [プロジェクト名]

## 概要
簡潔な説明（1-2文）

## 機能
- 主要機能1
- 主要機能2

## 対象ボード
- Tang Nano 9K
- Tang Primer 20K
など

## 必要なツール
- GOWIN EDA
- Veryl (オプション)

## ビルド方法
\`\`\`bash
cd eda/[project_name]
make
\`\`\`

## 使用方法
1. ビルド後のbitstreamを書き込み
2. 実行手順

## 依存関係
- 使用しているRTLモジュール
- 外部ライブラリ

## ピン配置
主要な入出力ピンの説明

## 参考資料
関連ドキュメントへのリンク
\`\`\`

#### 2.2 トップレベルREADMEの充実

追加すべき内容:
- プロジェクト一覧表（カテゴリ別）
- ディレクトリ構成の詳細説明
- 開発環境のセットアップ手順（Docker/devcontainer）
- ビルド方法の統一ガイド
- 貢献ガイドライン（オプション）

---

### フェーズ3: ディレクトリ構成の最適化

#### 3.1 推奨構成

```
fpga_samples/
├── eda/                    # EDAプロジェクト（現状維持）
│   ├── blink/
│   ├── display_controller/
│   ├── ethernet_video/
│   └── ...（31個）
├── rtl/                    # RTLモジュール（現状維持）
│   ├── displayport/
│   ├── ethernet/
│   ├── uart/
│   └── ...（22個）
├── chisel/                 # Chiselモジュール（現状維持）
│   └── src/main/scala/
├── riscv_cpu/              # RISC-V CPU（現状維持）
├── hls_fft/                # HLS（現状維持）
├── external/               # 外部依存（現状維持）
│   ├── picorv32/
│   ├── riscv-chisel-book/
│   ├── ebaz4205_ethernet/
│   └── learn-fpga/
├── util/                   # ユーティリティ（現状維持）
├── doc/                    # ドキュメント
│   ├── figures/            # 図形ファイル
│   ├── guides/             # ガイド文書（新規）
│   └── REPOSITORY_CLEANUP_PLAN.md  # このファイル
├── scripts/                # ビルドスクリプト（script/ → scripts/）
├── build/                  # ビルド成果物（新規、gitignore）
├── .gitignore              # 拡充
├── .gitmodules             # submodule設定
├── build.sbt               # Scalaビルド
└── README.md               # トップレベルドキュメント（充実化）
```

#### 3.2 移動・整理が必要

- `doc/synthesize_gowin_from_cli.md` → `doc/guides/` に移動（オプション）
- `script/` → `scripts/` にリネーム（オプション、一貫性のため）
- ビルド成果物を `build/` に集約（オプション）

---

### フェーズ4: ブランチ整理とマージ

#### 4.1 gowin_vol5 → main マージ計画

**状況**:
- `main`: メインブランチだが古い
- `gowin_vol5`: 最新機能を含む
- コミット差分: 調査必要

**マージ手順**:
1. gowin_vol5を最新の状態に（フェーズ1-3を適用）
2. コンフリクトを確認
3. mainにマージ
4. gowin_vol5ブランチを削除（オプション）

#### 4.2 ブランチ整理

30個のブランチを調査し、以下を判断:
- **保持**: 現在開発中のブランチ
- **マージ**: 完了したが未マージのブランチ
- **削除**: 古い実験的ブランチ

詳細は別途「ブランチ検討資料」を参照

---

## 📋 実行計画（優先順位付き）

### ✅ フェーズ1: 即座に実行（影響大、リスク小）

- [ ] 1. `.gitignore`の拡充
- [ ] 2. ルートの不要ファイル削除（xls.tar.gz等）
- [ ] 3. git clean -fd でキャッシュディレクトリ削除
- [ ] 4. git status確認と調整

**所要時間**: 15分
**完了目標**: 2026-02-23

### ⚡ フェーズ2: 短期（1-2週間）

- [ ] 5. 主要5プロジェクトのREADME作成
  - display_controller
  - cpu_matrix_led
  - multi_segment_led
  - dram_test
  - blink
- [ ] 6. トップレベルREADME更新
- [ ] 7. EDAプロジェクトの個別.gitignore調整

**所要時間**: 4時間
**完了目標**: 2026-03-07

### 🎯 フェーズ3: 中期（1ヶ月）

- [ ] 8. 全プロジェクトREADME作成（残り21個）
- [ ] 9. ブランチ整理とマージ
- [ ] 10. ビルドスクリプトの統一化
- [ ] 11. ドキュメントディレクトリ構成改善

**所要時間**: 8時間
**完了目標**: 2026-03-23

---

## 🔧 技術的詳細

### EDAプロジェクト一覧（31個）

| プロジェクト | サイズ | README | 説明 |
|---|---|---|---|
| ethernet_video | 104MB | ✅ | イーサネット+ビデオ |
| i2s_master | 47MB | ✅ | 音声I/Fマスタ |
| cpu_matrix_led | 41MB | ❌ | CPU + 行列LED |
| ethernet_icmp | 52MB | ✅ | イーサネット ICMP |
| display_controller | 31MB | ❌ | ディスプレイコントローラ |
| dvi_out_tpg | 26MB | ✅ | DVI出力テストパターン |
| display_port_tpg | 25MB | ✅ | DisplayPort TPG |
| fpga_performance | 25MB | ✅ | パフォーマンス測定 |
| turn_table | 19MB | ✅ | ターンテーブル制御 |
| multi_segment_led | 9.0MB | ❌ | 複数セグメントLED |
| gowin_easycdr_sample | 8.4MB | ✅ | GOWIN CDR |
| fpga_debug_probe | 8.5MB | ✅ | デバッグプローブ |
| uart | 7.6MB | ✅ | UART |
| blink | 2.7MB | ❌ | LED点滅サンプル |
| dram_test | 1.4MB | ❌ | DRAM テスト |
| その他16個 | <1MB | 主に❌ | 小規模サンプル |

### 外部依存（Git Submodules）

```gitmodules
[submodule "external/picorv32"]
    path = external/picorv32
    url = https://github.com/cliffordwolf/picorv32

[submodule "external/riscv-chisel-book"]
    path = external/riscv-chisel-book
    url = https://github.com/chadyuu/riscv-chisel-book

[submodule "external/ebaz4205_ethernet"]
    path = external/ebaz4205_ethernet
    url = https://github.com/ciniml/ebaz4205_ethernet

[submodule "external/learn-fpga"]
    path = external/learn-fpga
    url = https://github.com/BrunoLevy/learn-fpga
```

---

## 📝 進捗トラッキング

### 実行済み
- ✅ リポジトリ全体構造の調査（2026-02-23）
- ✅ 問題点の分析（2026-02-23）
- ✅ 整理方針の策定（2026-02-23）
- ✅ このドキュメントの作成（2026-02-23）

### 実行中
- 🔄 フェーズ1: .gitignore拡充と不要ファイル削除

### 今後の予定
- ⏳ ブランチ検討資料の作成
- ⏳ gowin_vol5のmainへのマージ
- ⏳ READMEの整備

---

## 🎯 成功基準

1. **バージョン管理**
   - 未追跡ファイルが20個以下
   - ビルド成果物が追跡されていない
   - .gitignoreが適切に設定されている

2. **ドキュメント**
   - 主要プロジェクト（10MB以上）に全てREADMEがある
   - トップレベルREADMEでプロジェクト概要がわかる

3. **ブランチ管理**
   - mainブランチが最新の機能を持つ
   - 不要なブランチが削除されている
   - 開発ブランチの目的が明確

4. **構成**
   - ルートディレクトリが整理されている
   - ビルド成果物が適切な場所にある

---

## 📚 参考資料

- リポジトリURL: https://github.com/ciniml/fpga_samples
- ライセンス: Boost Software License 1.0
- 最終更新: 2024年9月（gowin_vol5ブランチ）

---

**更新履歴**:
- 2026-02-23: 初版作成
