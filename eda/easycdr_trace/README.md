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

## Phase 2: キャプチャバッファ + UARTダンプ

受信ペイロードを16KiBのBSRAMバッファに取り込み、UART (BL616経由、
C3=TX / B3=RX、115200 8N1) でホストにダンプします。

- プロトコル: ホストから `S` でキャプチャ開始 (バッファ満杯で `K` 応答)、
  `D` で16384バイトの生ダンプ
- ホストツール: `host/trace_dump.py -p /dev/ttyUSBx`
  (カウンタ連番の連続性を検証)

## Phase 3: タイムスタンプ付きトレースレコード

TX側が信号の変化を検出してレコード化し、リンクへ流します。

- レコード形式: `[K28.1][ts 7:0][ts 15:8][ts 23:16][data 7:0][data 15:8]`
  (ts=100MHzリンククロックのサイクル数=10ns単位、K28.2=FIFO溢れ通知、
  K28.3=アイドル充填)
- TX: `trace_frontend.v` (2FF同期→変化検出→16段レコードFIFO→バイト直列化)
- デモ信号: 8bitカウンタ (2.56µs毎に+1) + UART RX線の生波形
  (ホストのコマンド自身がイベントとして記録される)
- RX: {Kフラグ,バイト}の9bitエントリでキャプチャ、`D`で2バイト/エントリの
  32KiBダンプ
- ホストツール: `host/trace_view.py -p /dev/ttyUSBx` (レコードをデコードして
  タイムスタンプ/Δt付きで表示、`-o`でCSV保存)

## Tang Nano 9K 送信側 (TARGET=tangnano9k_pmod)

「安価なターゲットFPGA→GW5Aホスト」の非対称構成です。GW1NR-9Cは
TX専用 (EasyCDRは受信側だけのIP) で、共通RTL (src/common/) をそのまま
使います。

- ラインレート: 27MHz×37/2×2 = **999Mbps** (ホストの1Gbps設定に対し
  -1000ppm。CDRの±5000ppm許容内なのでホスト側は無変更)
- クロック: rPLL 499.5MHz (VCO 999MHz) + CLKDIV/5 = 99.9MHz
- TXピン: pmod0 ピン2/8 = ExtEasyCDRレーンL1 (IOB8真性ペア、pin26/25)。
  ツールがo_serial_pをAサイド (pin25=PMODピン8=L1_N) に置くため、
  OSER10のD入力で全ビット反転して線路極性を合わせている
- デモトレース入力: 2.56µs周期カウンタ + **ボタンS2** (押すとホスト側の
  trace_view.pyにタイムスタンプ付きイベントが現れる)
- LED: lock (PLLロック) / heartbeat

```sh
DISPLAY= QT_QPA_PLATFORM=offscreen make synthesis TARGET=tangnano9k_pmod GW_SH=~/gowin/1.9.12/IDE/bin/gw_sh
make run TARGET=tangnano9k_pmod
```

接続: Nano9K pmod0のExtEasyCDR ⇔ USB-Cケーブル ⇔ 25K pmod2のExtEasyCDR。
ホスト側は既存のtangprimer25kビットストリームのままでOK
(ホスト自身のTX(pmod0)は未使用になるだけ)。

クロスファミリ検証はsimで実施済み: Nano9K TXネットリスト (GW1N simライブラリ)
の送信波形を記録し、25K RXネットリスト (GW5A simライブラリ) に再生する
2段方式で、-1000ppmオフセット込みのロックとボタンイベントの記録を確認。

## ロードマップ

- ~~Phase 1: 8b10bリンク層~~ 済 (実機確認済み)
- ~~Phase 2: キャプチャバッファ+UARTダンプ~~ 済 (実機確認済み)
- ~~Phase 3: タイムスタンプ付きレコード~~ 済 (実機確認済み)
- ~~Nano9K TX~~ 済 (実機確認済み: 999Mbpsでロック、S2イベント記録)
- Phase 3: トレースフロントエンド (トリガ・圧縮、debug_probe_core資産流用)
- TX移植: GW1N (Tang Nano 9K) / GW2A (Tang Primer 20K) 用PLLラッパ追加。
  CDRが±5000ppmを許容するため27MHz水晶の999Mbps (-1000ppm) でも
  RX側1Gbps設定のまま受信可能
