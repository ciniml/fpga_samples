# ブランチ分析と整理提案

**作成日**: 2026-02-23
**リポジトリ**: fpga_samples
**現在のブランチ**: gowin_vol5

---

## 📊 ブランチ概要

**総ブランチ数**: 21個（ローカル）
**メインブランチ**: main
**最新ブランチ**: gowin_vol5（2025-09-26）

---

## 🔍 ブランチ詳細分析

### ブランチの分類

| ブランチ名 | 最終更新 | Main比較 | 状態 | 推奨アクション |
|---|---|---|---|---|
| **gowin_vol5** | 2025-09-26 | +32/-0 | 🟢最新 | **mainにマージ** |
| **kiwi** | 2025-08-15 | +7/-0 | 🟢活発 | 保持 or マージ検討 |
| **10gbe** | 2024-09-07 | +5/-0 | 🟡進行中 | 保持 or マージ検討 |
| **displayport** | 2024-04-01 | +1/-0 | 🟡進行中 | 保持 or マージ検討 |
| main | 2024-03-24 | 0/0 | 🔵基準 | gowin_vol5でアップデート |
| **dds_core** | 2024-03-24 | 0/-1 | ✅マージ済 | 削除推奨 |
| **tangprimer25k_dvi** | 2024-03-21 | 0/-4 | ✅マージ済 | 削除推奨 |
| **i2s_master** | 2023-11-14 | 0/-13 | ✅マージ済 | 削除推奨 |
| **hub75_multi_level** | 2023-09-03 | +1/-28 | 🟡古い | 削除 or マージ検討 |
| **add-tangnano20k** | 2023-06-11 | 0/-32 | ✅マージ済 | 削除推奨 |
| **add-pmod** | 2023-06-11 | 0/-36 | ✅マージ済 | 削除推奨 |
| **tbf14_ethernet_udp** | 2023-05-21 | 0/-37 | ✅マージ済 | 削除推奨 |
| **tangprimer20k** | 2022-10-25 | 0/-54 | ✅マージ済 | 削除推奨 |
| **chapter1** | 2022-10-20 | 0/-56 | ✅マージ済 | 削除推奨 |
| **riscv_cpu** | 2022-07-07 | 0/-66 | ✅マージ済 | 削除推奨 |
| **tangnano1k** | 2022-05-17 | 0/-73 | ✅マージ済 | 削除推奨 |
| **hls_fft** | 2022-05-03 | +10/-84 | 🔴古い+分岐 | 削除 or リベース |
| **serv** | 2021-09-06 | +1/-96 | 🔴非常に古い | 削除推奨 |
| **verilator** | 2021-12-16 | 0/-84 | ✅マージ済 | 削除推奨 |
| **picorv32** | 2021-12-16 | 0/-90 | ✅マージ済 | 削除推奨 |
| **ws2812** | 2021-09-04 | 0/-97 | ✅マージ済 | 削除推奨 |

**凡例**:
- `+N/-M`: Mainに対して +N コミット先行、-M コミット遅れ
- 🟢 = 活発な開発中、🟡 = やや古い、🔴 = 非常に古い、✅ = マージ済み、🔵 = 基準

---

## 🎯 主要ブランチの詳細

### 1. gowin_vol5（最重要）

**ステータス**: 🟢 最新・最も進んでいる
**最終更新**: 2025-09-26
**Main比較**: +32コミット（mainより先行）
**変更規模**: 128ファイル、+9,452/-3,340行

**主要な新機能**:
- ✅ **ディスプレイコントローラ** (`eda/display_controller/`)
  - VRAM reader/writer
  - ビデオシグナルジェネレータ
  - AXI Stream Mux/Demux
- ✅ **SPI実装** (`rtl/spi/`)
  - SPIマスター・スレーブモジュール
  - 完全なテストベンチ（583行）
- ✅ **プローブツール** (`rtl/util/probe/`)
  - デバッグ用プローブ実装
- ✅ **10GbEサポート改善**
  - WidthConverterWithKeepの修正
- ✅ **Kiwi Nano 4Kサポート**
  - 新しいFPGAボード対応
- ✅ **HUB75改善**
  - 128x128 RGB332対応

**コミット履歴** (最新5件):
```
d5bf6f3 Add TUSER skip test case to video signal generator
09d37b5 Adjust SPI clock speed to 60 MHz and add pixel writing
5fec81d Fix VRAM writer complete signal
4b6e6e4 Implement using display_controller
de2cdeb Implement display_controller
```

**推奨アクション**:
- 🔥 **即座にmainにマージすべき**
- mainブランチを更新してリポジトリの基準とする
- マージ後、gowin_vol5ブランチは保持 or 削除（選択可）

---

### 2. kiwi（アクティブ）

**ステータス**: 🟢 活発
**最終更新**: 2025-08-15
**Main比較**: +7コミット
**内容**: Kiwi Nano 4Kサポートとプローブ実装

**推奨アクション**:
- gowin_vol5にすでに含まれている内容を確認
- 重複している場合は削除
- 独自の開発がある場合は保持

---

### 3. 10gbe（進行中）

**ステータス**: 🟡 やや古い
**最終更新**: 2024-09-07
**Main比較**: +5コミット
**内容**: 10GbEイーサネット実装

**推奨アクション**:
- gowin_vol5にマージされているか確認
- マージ済みなら削除
- 独自の作業が残っていれば保持

---

### 4. displayport（進行中）

**ステータス**: 🟡 やや古い
**最終更新**: 2024-04-01
**Main比較**: +1コミット
**内容**: DisplayPort AUX_CH実装

**推奨アクション**:
- mainにマージされていないDisplayPort機能があるか確認
- 必要であればmainにマージ
- 不要なら削除

---

## ✅ マージ済みブランチ（削除推奨）

以下のブランチは既にmainにマージされており、mainより遅れています:

| ブランチ名 | 最終更新 | 遅れ | 削除優先度 |
|---|---|---|---|
| dds_core | 2024-03-24 | -1 | 🔥高 |
| tangprimer25k_dvi | 2024-03-21 | -4 | 🔥高 |
| i2s_master | 2023-11-14 | -13 | 🔥高 |
| add-tangnano20k | 2023-06-11 | -32 | ⚡中 |
| add-pmod | 2023-06-11 | -36 | ⚡中 |
| tbf14_ethernet_udp | 2023-05-21 | -37 | ⚡中 |
| tangprimer20k | 2022-10-25 | -54 | ⚡中 |
| chapter1 | 2022-10-20 | -56 | ⚡中 |
| riscv_cpu | 2022-07-07 | -66 | 低 |
| tangnano1k | 2022-05-17 | -73 | 低 |
| verilator | 2021-12-16 | -84 | 低 |
| picorv32 | 2021-12-16 | -90 | 低 |
| ws2812 | 2021-09-04 | -97 | 低 |

**削除コマンド例**:
```bash
# 最近マージされたブランチを削除（2024年以降）
git branch -d dds_core tangprimer25k_dvi i2s_master

# 2023年のマージ済みブランチを削除
git branch -d add-tangnano20k add-pmod tbf14_ethernet_udp

# 2022年以前の古いブランチを削除
git branch -d tangprimer20k chapter1 riscv_cpu tangnano1k verilator picorv32 ws2812
```

---

## 🔴 問題のあるブランチ

### hls_fft
**ステータス**: 🔴 分岐している
**最終更新**: 2022-05-03（古い）
**Main比較**: +10/-84（大きく分岐）

**問題点**:
- mainより84コミット遅れているが、10コミット先行もしている
- 3年以上前の最終更新
- 大きく分岐しているため、マージが複雑

**推奨アクション**:
- hls_fftディレクトリの内容を確認
- mainに必要な変更が含まれているか確認
- 含まれていれば削除
- 含まれていなければ、リベースまたは新ブランチで再実装

### hub75_multi_level
**ステータス**: 🟡 やや分岐
**最終更新**: 2023-09-03
**Main比較**: +1/-28

**推奨アクション**:
- +1コミットの内容を確認
- 必要であればmainにマージ
- 不要なら削除

### serv
**ステータス**: 🔴 非常に古い
**最終更新**: 2021-09-06
**Main比較**: +1/-96

**推奨アクション**:
- servディレクトリがmainに存在するか確認
- 削除してよいか確認後、削除

---

## 📋 推奨アクションプラン

### フェーズ1: 重要ブランチのマージ（即座）

```bash
# 1. gowin_vol5をmainにマージ
git checkout main
git merge --no-ff gowin_vol5 -m "Merge gowin_vol5: Latest features including display_controller, SPI, 10GbE improvements"

# 2. マージ後のテスト
# - ビルドが通るか確認
# - 主要プロジェクトが動作するか確認

# 3. リモートにプッシュ
git push origin main
```

### フェーズ2: アクティブブランチの確認（1週間以内）

以下のブランチについて、内容を確認:
- [ ] kiwi: gowin_vol5に含まれるか確認
- [ ] 10gbe: gowin_vol5に含まれるか確認
- [ ] displayport: mainにマージすべきか確認
- [ ] hub75_multi_level: 必要な変更があるか確認

### フェーズ3: マージ済みブランチの削除（2週間以内）

```bash
# 2024年のマージ済みブランチを削除
git branch -d dds_core tangprimer25k_dvi i2s_master

# 2023年のマージ済みブランチを削除
git branch -d add-tangnano20k add-pmod tbf14_ethernet_udp

# リモートブランチも削除（必要に応じて）
git push origin --delete dds_core tangprimer25k_dvi i2s_master
```

### フェーズ4: 古いブランチの削除（1ヶ月以内）

```bash
# 2022年以前の古いブランチを削除
git branch -d tangprimer20k chapter1 riscv_cpu tangnano1k verilator picorv32 ws2812
```

### フェーズ5: 問題のあるブランチの対応（必要に応じて）

```bash
# hls_fftの内容確認後、削除 or リベース
git branch -d hls_fft  # または git rebase main hls_fft

# servの確認後、削除
git branch -d serv
```

---

## 🎯 期待される結果

**整理前**: 21ブランチ
**整理後（推定）**: 5-8ブランチ

**残るブランチ（予想）**:
- main（最新化）
- gowin_vol5（オプション、mainと同期なら削除可）
- displayport（必要に応じて）
- kiwi（gowin_vol5に含まれなければ）
- 10gbe（gowin_vol5に含まれなければ）
- hub75_multi_level（必要な変更があれば）

**削除されるブランチ（予想）**: 13-16ブランチ

---

## 📊 ブランチ削除の確認方法

### 安全な削除確認コマンド

```bash
# 特定のブランチがmainに完全にマージされているか確認
git branch --merged main

# 特定のブランチの未マージコミットを確認
git log main..branch_name --oneline

# ブランチの変更内容を確認
git diff main...branch_name --stat

# ブランチを削除（マージ済みのみ）
git branch -d branch_name

# ブランチを強制削除（未マージでも）
git branch -D branch_name
```

---

## ⚠️ 注意事項

1. **バックアップ推奨**
   - ブランチ削除前に、リモートにプッシュされているか確認
   - 重要なブランチは削除前にタグを作成

2. **リモートブランチ**
   - ローカルブランチを削除してもリモートには残る
   - リモートも削除する場合は `git push origin --delete branch_name`

3. **作業中のブランチ**
   - 現在作業中のブランチは削除しない
   - チーム開発の場合、他の開発者に確認

4. **履歴の保持**
   - マージ済みブランチでも、履歴として残したい場合はタグ作成を検討

---

## 🔄 gowin_vol5 → main マージの詳細

### マージ前の準備

```bash
# 現在のブランチを確認
git branch --show-current

# mainブランチを最新化
git checkout main
git pull origin main

# gowin_vol5の状態を確認
git log --oneline -10 gowin_vol5
git diff --stat main...gowin_vol5
```

### マージ実行

```bash
# mainでgowin_vol5をマージ
git checkout main
git merge --no-ff gowin_vol5 -m "Merge gowin_vol5: Add display_controller, SPI modules, 10GbE improvements, and Kiwi Nano 4K support

Major changes:
- Add display_controller with VRAM reader/writer and video signal generator
- Implement SPI master/slave modules with comprehensive tests
- Add debug probe utilities
- Improve 10GbE support with WidthConverterWithKeep fix
- Add Kiwi Nano 4K FPGA board support
- Enhance HUB75 support for 128x128 RGB332"
```

### マージ後の確認

```bash
# マージ結果を確認
git log --oneline -5
git status

# ビルドテスト（主要プロジェクト）
cd eda/display_controller && make
cd ../ethernet_video && make

# 問題なければプッシュ
git push origin main
```

### マージ後の選択肢

**オプションA: gowin_vol5を削除**
```bash
# gowin_vol5がmainと同じ状態なら削除
git branch -d gowin_vol5
git push origin --delete gowin_vol5
```

**オプションB: gowin_vol5を保持**
```bash
# gowin_vol5を継続開発ブランチとして保持
# mainと同期しておく
git checkout gowin_vol5
git merge main
```

---

## 📝 更新履歴

- 2026-02-23: 初版作成
  - 21ブランチの詳細分析
  - gowin_vol5のマージ計画策定
  - 削除推奨ブランチのリストアップ
