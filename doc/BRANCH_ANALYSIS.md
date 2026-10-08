# ブランチ構成とアーカイブ

**更新日**: 2026-10-09

## 現在のブランチ

| ブランチ | 内容 |
|---|---|
| `main` | 全成果物の統合先。2026-10-09 に `hs_phy_120m` まで fast-forward 済み |
| `hs_phy_120m` | 作業中ブランチ（2026-10-09 時点で `main` と同一） |

2026-04 以降の作業（displayport → dvi_in/dvi_capture → DP/Type-C → EasyCDR → NVMe →
USB HS → dvi_hub75）は 1 本の直線履歴で `displayport` / `dvi_out_and_debug` /
`hs_phy_120m` と名前を変えながら積み上げられていたため、`main` へ fast-forward して
途中のブランチ名は削除した。

## アーカイブタグ（`main` 未マージのまま残した内容）

ブランチは削除済み。参照するときは `git checkout -b <name> archive/<name>`。

| タグ | 元ブランチ | 内容 |
|---|---|---|
| `archive/hls_fft` | hls_fft | HLS Cooley-Tukey FFT / NTT（2022-04〜05, 10 commits） |
| `archive/serv` | serv（ローカルのみ） | SERV design（2021-09, 1 commit） |
| `archive/hub75_multi_level` | hub75_multi_level（ローカル） | "Add I2S Master"（2023-09, 1 commit） |
| `archive/atom_display_16bit` | feature/atom_display_16bit | 16bpp StreamReader/Writer, AXI4 priority demux（2024-01, 3 commits） |
| `archive/atom-display_timing-issue` | atom-display_timing-issue | タイミング修正（同等の変更は main に取り込み済み） |
| `archive/chisel6` | chisel6 | Chisel6 移植, MSMP module（2024-06〜12, 2 commits） |
| `archive/gowin_vol5_ja` | gowin_vol5_ja | 記事向けにコメントを日本語化（2025-09, 3 commits） |
| `archive/stash-ethernet_icmp-hub75` | main 上の stash | ethernet_icmp tangprimer20k_hub75 の修正（2023-03） |

## 削除したマージ済みブランチ

10gbe, add-pmod, add-tangnano20k, atom_display, chapter1, dds_core, gowin_vol5,
i2s_master, kiwi, packetqueue, picorv32, riscv_cpu, tangnano1k, tangprimer20k,
tangprimer25k_dvi, tbf14_ethernet_udp, verilator, ws2812,
displayport, dvi_out_and_debug（いずれも `main` に含まれる）

## 運用方針

- 新しいテーマはそのテーマ名でブランチを切り、区切りごとに `main` へマージする
  （作業ブランチの上に別テーマを積み続けない）
- ビルド成果物（Verilator `obj_dir*`、合成出力など）はコミットしない
