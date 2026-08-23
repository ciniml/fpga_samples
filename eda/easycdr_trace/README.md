# EasyCDR トレースリンク (Phase 1: 8b10b リンク層)

EasyCDRを使った省ワイヤ高速トレース取得ツールのリンク層です。
1本の差動ペアだけで(クロック配線なしで)ターゲットFPGAから
ホストFPGAへデータを送ります。

## 構成 (Phase 1: リンク層ループバックテスト)

| 項目 | 内容 |
|---|---|
| ラインレート | 1Gbps (ペイロード800Mbps) |
| リンク層 | 8b10b + K28.5コンマ (16ワードフレーム: K×1 + データ×15) |
| TX | easycdr_trace_tx_core (ファミリ非依存) + OSER10 (FCLK500MHz/PCLK100MHz) |
| 8b10bエンコーダ | rtl/displayport/src/encoder_8b10b.sv を流用 |
| RX | EasyCDR 10bit + Word Alignment + 8B/10B Decoding 構成 (PCLK 125MHz) |
| RX出力 | dout_o[8]=Kフラグ, [7:0]=デコード済みバイト, align_flag_o, error_o |

物理層・ピン配置は gowin_easycdr_1g2_sample と同一です
(ExtEasyCDR×2 + パッシブUSB-Cケーブル、TX=G7/G8、RX=G11/G10、
RXオンチップ100Ω終端 + CTLE=HIGH、TX DRIVE=16mA)。

## 観測

| ピン | 信号 | 正常時 |
|---|---|---|
| B2 | o_dat_lock | High (アライン成功+コンマウォッチドッグ~65µs) |
| C2 | o_dat_err | Low (カウンタ不一致 or 8b10bデコードエラーでパルス) |
| E1 | dout_flag_xor | 82µs周期の方形波 (コンマ256個毎にトグル) |
| - | O_ERROR | 8b10bデコードエラーのスティッキーフラグ (Low正常) |

## ビルド

```sh
QT_QPA_PLATFORM=offscreen make synthesis GW_SH=~/gowin/1.9.12/IDE/bin/gw_sh
make run
```

## ロードマップ

- Phase 2: カウンタペイロード→リングバッファ+UARTドレイン+ホストツール
- Phase 3: トレースフロントエンド (トリガ・圧縮、debug_probe_core資産流用)
- TX移植: GW1N (Tang Nano 9K) / GW2A (Tang Primer 20K) 用PLLラッパ追加。
  CDRが±5000ppmを許容するため27MHz水晶の999Mbps (-1000ppm) でも
  RX側1Gbps設定のまま受信可能
