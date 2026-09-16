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

## トレースIP (`src/common/easycdr_trace_tx.v`) とトリガ付きキャプチャ

TX側はIP化されており、ユーザーデザインには次を置くだけです:

```verilog
easycdr_trace_tx #(.WIDTH(16), .TS_BITS(24)) u_trace_tx(
    .clk(link_parallel_clk),   // ラインレート/10 (1Gbpsなら100MHz)
    .rstn(rstn),
    .sig(any_signals),         // WIDTHビット (非同期入力可、内部で2FF同期)
    .o_symbol(tx_symbol),      // → OSER10 D0..D9 (bit0が先頭)
    .o_overflow());
```

+ デバイス依存部 (PLL / OSER10 / 差動OBUF) は各ターゲットのtop.vを参照。
`WIDTH` は8の倍数で任意 (レコードのdataバイト数=WIDTH/8、**チャネル拡張は
パラメータ変更のみ**)。変化検出はパイプライン化済み (GW1Nで100MHz達成)。

ホスト側はリングバッファ + トリガ + プリトリガをサポート:

| コマンド | 内容 |
|---|---|
| `S` | 即時キャプチャ (バッファ全体を新規に埋める) |
| `T` mask[DB] value[DB] | トリガ条件 `(data & mask) == value` を設定 (LSBファースト) |
| `A` post_hi post_lo | トリガ待ちでアーム。トリガ後 `post` エントリ書いて凍結。
  残り (バッファサイズ − post) が**プリトリガ履歴**になる |
| `D` | 時系列順 (最古から) に2バイト/エントリでダンプ |
| `?` / `F` / `X` / `Z` / `P` | デスクリプタ / TX フラグ / 逆方向チャネル転送 / 中止 / パルスリセット (後述) |
| `L` | **リンク診断** 14 バイト: status (bit0 lock, bit1 align, bit2 desc, bit3 comma 監視, bit4 IP reset, bit7 受信クロック無応答)、VER、前回 `L` 以降の K28.5 / K28.1 / 復号誤り / K28.2 / K28.4 / データ語 の各 u16 (飽和) |

```sh
# Nano9KのS2押下 (bit8) をトリガに、前後半分ずつ取得
python3 host/trace_view.py -p /dev/ttyUSB2 --trigger 0x0100 0x0100 --post 8192
```

### ホストトランスポートの差し替え (USBコア接続用)

`trace_capture` はホスト側を**バイトストリーム (valid/ready)** で抽象化しており、
UARTは top.v 側で外付けしているだけです。USB CDC等のコアは次の5本を
`clk_sys` (50MHz) ドメインで繋げば、そのまま同じコマンドプロトコルで動きます:

```verilog
.h_rx_valid (host→FPGA バイト有効), .h_rx_data ([7:0])   // 受信側は常時ready
.h_tx_valid (FPGA→host バイト有効), .h_tx_data ([7:0]), .h_tx_ready
```

UARTボーレートは top.v の `UART_BAUD` 1箇所。BL616ブリッジ向けに
921600 / 2000000 のビルド変種を `variants/` (非管理) に作って試行中。

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
- ~~トレースIP化 + チャネル幅パラメータ化 + トリガ/プリトリガ~~ 済 (sim検証済み)
- UART帯域強化 → USB FSソフトデバイス (計画中)
- Phase 3: トレースフロントエンド (トリガ・圧縮、debug_probe_core資産流用)
- TX移植: GW1N (Tang Nano 9K) / GW2A (Tang Primer 20K) 用PLLラッパ追加。
  CDRが±5000ppmを許容するため27MHz水晶の999Mbps (-1000ppm) でも
  RX側1Gbps設定のまま受信可能

## 診断と自己試験 (つながらないとき)

順番に確認する。前段が通るまで次へ進まない。

| 手順 | コマンド | 期待 | 通らないとき疑う場所 |
|---|---|---|---|
| 1. 25K 単体自己試験 | USB-C ケーブルを 25K の pmod0 ↔ pmod2 に接続し `python3 host/ctrl_test.py --selftest` | ALL OK (自前ストリーム: 16bit カウンタが 5.12µs 毎に +1) | 25K のビットストリーム、ブリッジのポート (`USB_Debugger_*-if01`)、モジュール/ケーブル |
| 2. リンク診断 | 送信側と接続して `ctrl_test.py` の先頭 (または UI の Link diag) | `[lock align desc commas]`、errors 0、records > 0 | lock 無し: 送信側の PLL/ビットストリーム、レート変種の不一致 (999M と 742.5M)、ケーブルのレーン (TX L1 → RX L0)。commas はあるが desc 無し: 送信側の極性反転 (8b10b は極性非耐性)。records 0 で desc あり: 送信側が ARMED/DONE/無効 → `X` で RESET |
| 3. 制御チャネル | `ctrl_test.py` 全項目 | ALL OK | Manchester の極性 (`CTRL_INVERT`)、レーン (25K pmod2 L1 → Nano9K pmod0 L0) |

`L` の status bit7 は受信クロック (EasyCDR の share_clk) が止まっている印で、RX PLL がロックしていない
(ケーブル以前の問題)。ctrl_test.py は `L` を最初に実行し、lock/commas が無ければそこで止まる。

## 逆方向制御チャネル (ホスト → トレース送信側)

追加ケーブル無しで、25K 側の **pmod2 モジュールの L1 レーン (pmod2 ピン 2/8 = D10/D11)** →
USB-C クロス → Nano9K の空き RX レーン (pmod0 ピン1/7 = L0 = FPGA 28/27, IOB11 真性ペア) に
2Mbps Manchester (`rtl/manchester`) を通し、トレース送信側を制御する (往路と同じケーブルを
逆向きに使う。単板ループバック時代の G7/G8 = pmod0 L1 では別モジュールに出てしまうので注意)。
**2026-09-13 実機確認済み** (`host/ctrl_test.py`: `?` デスクリプタ、IGNORE_MASK でレコード停止、
ENABLE 0/1、RESET でタイムスタンプ再始動、`Z` アボート — ALL OK)。

- Nano9K 側: `TLVDS_IBUF` (LVDS25) → `ManchesterRx` → `CtrlFrameRx` →
  `TraceCtrlRegs`。ツールが i_ctrl_p を A パッド (pin27 = L0_N) に置くため
  **CTRL_INVERT=1** で受信極性を反転している
- 制御内容: ソフトリセット / トレース有効 / 無視マスク / デスクリプタ要求 /
  **周期サンプリング (PERIOD 毎のレコード、変化検出 OFF 可) / TX 側トリガ (ARM → 条件一致まで
  抑止 → 一致サンプル + POST 個を送って停止)** (レジスタマップは `rtl/manchester/README.md`)。
  TX 状態 (armed/triggered/done/periodic) はデスクリプタ flags → ホストコマンド `F`
- TX コアは K28.4 デスクリプタ `[VER][WIDTH][TS_BITS][flags]` を約1.3ms毎に送出。
  25K のデコーダがラッチし、ホストコマンド `?` で
  `[VER][WIDTH][TS_BITS][ADDR_BITS]` を返す (ブラウザUIのパラメータ自動設定用)
- ホストコマンド追加: `?` (上記)、`X len bytes` (バイト列を逆方向チャネルへ転送)、
  `Z` (アボート: アーム解除して IDLE へ、応答 `Z`)。**アーム中 ('S'/'A' 後、'K' 前) は `X`/`?` は
  無視される** — 設定してからアームするか、`Z` (UI の Abort) で解除する
- **サンプルクロック分離** (2026-09-13): `easycdr_trace_tx` は `sclk`(監視対象のクロック)と
  `clk`(リンク 99.9MHz)を持ち、内部の非同期 FIFO とハンドシェイクで分離する。制御入力は
  `clk` 側のまま。Nano9K デモは 27MHz 水晶をサンプルクロックにしている(タイムスタンプ 37.037ns、
  UI の sample clk period と `ctrl_test.py --tick-ns` の既定値)。構造と再構成パラメータは
  `doc/tx_core_spec.md` §4 参照
- **信号マップと構成ハッシュ** (2026-09-17): `maps/*.map` に `name[:width[:radix]]` を LSB から並べて書く
  (`maps/nano9k_demo.map` = `count:8:dec, s2:1, spare:7`)。`host/tracemap.py` が幅と CRC-32 (正規形
  `name:width,...`) を出し、`project.tcl` が Nano9K ビルドに `TRACE_MAP_WIDTH` / `TRACE_MAP_HASH` を埋める
  (`make TRACE_MAP=maps/x.map`、`TRACE_WIDTH=32` は無名マップ)。送信側はデスクリプタ v2
  `[K28.4][02][WIDTH][TS_BITS][flags][HASH×4]` で配り、`?` は 8 バイト (末尾 4 バイトがハッシュ、v1 送信機は 0) を返す。
  UI の「Signal map」欄と `ctrl_test.py --map` が同じ CRC-32 を計算して照合し、不一致なら警告する
- **信号名での表示・トリガ** (2026-09-17、UI 段階 2): Signal map が送信側と一致 (または幅が一致) すると、波形は
  信号ごとの行になり、多ビット信号は値の箱 (16 進 / 10 進 / 2 進 / `enum(A,B,..)` の名前) で描く。レコード表は
  信号ごとの列 + 生データ。マップに `name = expr` (`&`,`|`,`^`,`~`,`!`,`==`,`!=`,`<`,`>`、括弧) を書くと派生信号
  (ハッシュには含めない)。トリガ条件は `s2 == 1 && count == 0x10` のように書くとマスク/値に変換される (等値のみ、
  ホスト側・TX 側とも)。無視マスクも信号名で指定可。CSV は信号ごとの列、VCD は `$var wire N id name [N-1:0]` のベクタ
- **受信側は幅可変** (2026-09-13): 25K のデコーダとキャプチャはレコード形式 (WIDTH / TS_BITS) を
  デスクリプタから実行時に取る (最大 64 / 32 bit)。送信側の幅を変えても 25K の再合成は不要。
  Nano9K デモの幅は `make TRACE_WIDTH=32 TARGET=tangnano9k_pmod` (出力 `build/tangnano9k_pmod_w32/`)
- **リンクレート変種 742.5 Mbps** (2026-09-13、実機 OK): `make RATE=742M5 TARGET=...` で両ボードとも
  `build/<target>_742m5/`。720p DVI の 371.25 MHz / 74.25 MHz を送信側で流用する構成向け。
  Nano9K は rPLL 27×55/4 = 371.25 MHz、25K は PLLA 50×(22+2/8)/3 = 370.83 MHz (−1120 ppm、PLLA の
  制約 PFD 19〜87.5 MHz / VCO 700〜1400 MHz 内で分数 MDIV を使用) と EasyCDR IP の DELAY_1 を 21→28 に
  スケール (`easycdr_1912_742m5/`)。TRACE_WIDTH / CTRL_PULSE と併用可 (サフィックスが連結される)
- リセット専用変種: `make CTRL_PULSE=1 TARGET=tangnano9k_pmod` (出力 `build/tangnano9k_pmod_pulse/`)
  は Nano9K の受信側を `PulseResetRx` だけにする (レジスタ無し、トレースは常時有効・変化検出のみ)。
  25K は常に `PulseResetTx` を持ち、ホストコマンド `P` (返信 `P`) で 4×20µs のバーストを Manchester
  線に割り込ませる。UI の「Pulse reset (P)」ボタン、`host/ctrl_test.py --pulse` で確認
- 全体構成図: `doc/system_overview.drawio` (draw.io)
- EasyCDR の原理と実機で確かめたこと: `doc/easycdr_principles.md` (方式、OSIDES32、IODELAY の制約、8b10b、PRBS、アイスキャン)
- 検証: `test/e2e_ctrl_tb.sv` (Verilator, `make -C test test`) がホストコマンド →
  Manchester → 制御レジスタ → トレースTX → 8b10bデコード → キャプチャ → ダンプの
  全周回を検証 (12チェック)。デバイスプリミティブ(PLL/OSER10/IBUF)以外は実RTL
- ビルド前に `rtl/manchester` で `veryl build` を実行しておくこと (生成 .sv を参照)

## ブラウザ版ホストツール

`host/web/index.html` を Chrome/Edge で開くと Web Serial (UART) / WebUSB (ベンダクラス USB) 経由で
キャプチャ・波形表示・CSV/VCD 出力ができる (Python/pyserial 不要)。設計は `doc/web_host_design.md`。
