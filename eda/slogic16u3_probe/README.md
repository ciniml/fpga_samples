# SLogic16U3 ピン調査デザイン

回路図が公開されていない Sipeed SLogic16U3 (GW5AT-LV15MG132C1/I0) のピン配置を、JTAG だけで調べるためのデザインとホストツールです。
公開されているピン情報 (litex-boards の LA CH0-15 と UART) とパッケージのピン一覧は `src/slogic16u3/pins.csv` と `../targets/slogic16u3/README.md` にまとめてあります。

| 方法 | FPGA 側 | 侵襲性 | 分かること |
|---|---|---|---|
| 1. SAMPLE 観測 | 純正 FW のまま | なし (SAMPLE のみ) | 操作に反応する BSR セル番号 (ボールは不明) |
| 2. ソフトバウンダリスキャン | このデザインを SRAM にロード | SRAM のみ (電源再投入で純正に戻る) | ボール単位の入力レベル・活動・プル応答、出力トグル |
| 3. BSR ↔ ボール対応付け | 2 と同じ | 同上 | 方法 1 のセル番号をボールに翻訳する表 |

Flash には一切書き込みません。ホストツールは IR に SAMPLE(0x01)/IDCODE/USERCODE/STATUS/ER1/ER2/BYPASS 以外を入れないようになっています (EXTEST や Gowin のコンフィグ命令は使えません)。

## 構成

- `src/slogic16u3/top.v` — GW_JTAG の ER1 (0x42) にぶら下げたピンレジスタ。TCK/TDI はパッドから直接内蔵発振器でオーバーサンプルし、GW_JTAG のストローブも同期して使う (`tck_o` で直接シフトすると、rust-dap の TDI 変化タイミングとの競合でビットがずれた)。TCK は ~6 MHz まで。全ピンのレベル・活動フラグ (内蔵発振器 ~52 MHz で変化を検出)・ピンごとのモード (Hi-Z/0/1/点滅) を TCK だけで読み書きする。外部クロック不要。
- `src/slogic16u3/pins.csv` — 対象ピンの唯一の定義。CST・RTL パラメータ・ホストツールの全部がここから作られる。`class` が `probe`/`uart_tx` のピンだけが出力可能 (RTL で固定)。`la`/`uart_rx`/`cfg` は入力のみ。
- `project.tcl` — pins.csv から `pins.cst` と `defines_gen.v` を生成して合成する。
- `host/slogic_probe.py` — pyusb だけで FT2232 互換プローブを MPSSE 駆動する JTAG ツール (pyftdi 不要)。`--sim` で下のシミュレーションも同じコードで駆動できる。
- `sim/tb.v` — 振る舞いモデルの GW_JTAG (TAP、IDCODE、偽の SAMPLE レジスタ) とボードモデル。`make sim` で iverilog 用にビルドする。

## ビルド

```
make PINSET=main PULL=UP      # 既定
make all-pulls                # main/cfg × UP/DOWN の 4 本
```

- `PINSET=main` は LA 16 本 + UART 2 本 + 未知 20 本、`PINSET=cfg` は LA の代わりに DONE/READY/MODE0/MODE1 を入れたもの。GW5AT-15 MG132 は JTAG の 4 パッドを含めて 42 ポートまでしか置けないので、2 つに分けている。
- `PULL` はピンの弱プル。分類 (classify) にはプルアップ版とプルダウン版の両方が必要。
- RECONFIG_N(M3) は GW5AT-15 では GPIO にできない (gw_sh が拒否する) ので対象外。
- gw_sh が PATH にない場合は `GW_SH=~/gowin/1.9.12.03/IDE/bin/gw_sh`、X が無い環境では `QT_QPA_PLATFORM=offscreen` を付ける。
- 出力: `build/slogic16u3_<pinset>_<pull>/impl/pnr/slogic16u3_probe.fs`

## 使い方

JTAG は基板上の JST SH1.0 8P (Tang Primer 20K と同じ形) にプローブをつなぐ。既定は CMSIS-DAP v2 プローブ (rust-dap、`--cable dap`) で、SRAM ロードには `~/repos/rust-dap/fpga-config` の `gowin-prog --cable dap sram` を使う。FT2232 互換プローブ (Sipeed USB Debugger など) を使う場合は `--cable ftdi` を付ける (ロードには openFPGALoader を使う)。ツールは最初に IDCODE が 0x0001681B (GW5AT-15) であることを確かめる。

### 0. 前提の確認

```
python3 host/slogic_probe.py detect
```

IDCODE、USERCODE、ステータスレジスタを表示する。IDCODE が読めない場合、配線を見直す。純正 FW が JTAG ピンを GPIO にしている可能性もある。量産時に eFuse の AES 鍵がロックされているので、`encrypted_format` / `key_right` が立つかを見ておく。ただし `Security Final` は普通のビットストリームでも立つ (Tang Console 60K で確認済み)。

### 1. SAMPLE 観測 (純正 FW のまま)

```
python3 host/slogic_probe.py bsr-len                       # SAMPLE レジスタ長
python3 host/slogic_probe.py sample -n 64 -o idle.json --label idle
python3 host/slogic_probe.py watch                         # 変化したセルを表示し続ける
python3 host/slogic_probe.py diff idle.json capture.json   # 条件間で値が変わったセル
```

GW5A の SAMPLE が 0x01 なのは GW1N の資料 (TN653) からの推定。`bsr-len` が数百ビット程度の妥当な長さを返し、LA チャネルに信号を入れると `watch` に反応が出れば、0x01 は SAMPLE と考えてよい。
調べ方: LA チャネルに信号を入れる、MODE ボタンを押す、キャプチャを開始する (赤 LED が速く点滅する)、CK ピンに信号を入れる。どれでも、反応したセル番号が分かる。

### 2. ソフトバウンダリスキャン

```
python3 host/slogic_probe.py load build/slogic16u3_main_up/impl/pnr/slogic16u3_probe.fs
python3 host/slogic_probe.py ubs-read                # レベル / 活動 / モード
python3 host/slogic_probe.py ubs-clear               # 活動フラグを消す
python3 host/slogic_probe.py ubs-read --watch        # 変化したときだけ表示 (ボタン、CK 入力探し)
python3 host/slogic_probe.py classify                # プルアップ版とプルダウン版をロードして分類 → classify.json
python3 host/slogic_probe.py blink-scan              # floating のピンを 1 本ずつ点滅 (LED / テストパッド探し)
python3 host/slogic_probe.py ubs-set H14 blink --fast   # 1 本だけ ~100 kHz で点滅 (スコープ用)
```

`load` の段階で SRAM ロードが拒否される場合 (eFuse のロックで暗号化ビットストリームしか受け付けない場合など)、方法 1 だけで進める。

分類の意味:
- `floating`: 内蔵プルに従う。強いものは何もつながっていないので、駆動して安全。
- `high`/`low`: 外部でプルされているか駆動されている。LED と抵抗で VCC につながっている、ストラップ、他の IC の出力、のどれか。
- `active`: 入力が変化している。発振器や信号の入力。

出力は `floating` のピンだけに許可される。`high`/`low` のピンも `--force` を付ければ駆動できる (例えば LED の可能性があるとき)。すべての出力は DRIVE=4mA で、モード 0 (Hi-Z) から始まる。`--od` を付けると点滅をシンク側だけにする (VCC 側に LED がある場合など)。

### 3. BSR ↔ ボールの対応付け

```
python3 host/slogic_probe.py map-bsr -o bsrmap.json
```

駆動可能なピンを Hi-Z/0/1 に切り替え、そのたびに SAMPLE を取る。駆動値に追従するセル (入力と出力) と OE らしいセルを記録する。何回かくり返し、無関係なクロックで変化するセルは除外する。入力専用の LA/CK ピンは方法 1 と同じく、ヘッダから信号を入れて `sample`/`diff` で特定する。

## シミュレーション

```
make sim                              # sim/build/tb_main_up.vvp
make sim SIM_PULL=down                # classify 用
python3 host/slogic_probe.py --sim "vvp -n sim/build/tb_main_up.vvp" ubs-read
python3 host/slogic_probe.py --sim "vvp -n sim/build/tb_main_up.vvp" classify
python3 host/slogic_probe.py --sim "vvp -n sim/build/tb_main_up.vvp" map-bsr
```

ボードモデル: F13 = 25 MHz 発振器、P14(CH3) = 信号入力あり、E14 = 外部 High、J12 = 外部 Low、N1 = ストラップ High。偽の BSR は 7 個の定数セルと、ピンごとに {in, out, oe} を逆順に並べたもの。シミュレーション上は、classify と map-bsr が両方ともモデルどおりの結果を返すことを確認した。

## 実機で確認したこと (2026-10-10、rust-dap CMSIS-DAP)

- 純正 FW 動作中: STATUS 0x7002E020。bit15 `encrypted_format` が立つ。Tang Console 60K の普通のビットストリームでは 0x70026020。Flash の 0x0 と 0x800000 のイメージは同期ワードが `A5 DB` (平文は `A5 C3`) で、暗号化されている。
- 平文のビットストリームの SRAM ロードは通る (eFuse ロックの影響はない)。ロード後の STATUS は 0x70026020。
- ER1 ソフトバウンダリスキャンは実機で動く (magic 検出、ubs-read、classify)。
- MODE ボタン:
  - 押すたびにフラッシュから再コンフィグされる。STATUS は Auto Erase → Non-JTAG 構成 → Done と進み、約 1 秒かかる。
  - USERCODE は 0xEA60 ↔ 0xE9DC と交互に入れ替わる。JTAG で SRAM ロードしてから押すと 0xE9DC になる。
  - `status-watch` で観測できる。
- LED: G14 = ACT LED の赤 (High で点灯)。L3 (DONE) = 緑 (DONE が High で点灯、Low に引くと消灯)。D14、M1、H2 と、floating な調査対象ピンはどれも反応しなかった。D13 を Low にすると、MODE と同じ再コンフィグが起きる。
- USERCODE 0xEA60 は DFU イメージ (USB2 HS の 359f:30f1 "SLogic DFU")。0xE9DC はロジアナのアプリ (USB3)。
- SAMPLE (0x01) は GW5A でも動き、長さは 98 ビットだった。
- 背面ヘッダの CK = H13 / G13 (GCLKT_1/GCLKC_1)。 CK (H13/G13) は分圧されていない: プルダウンなしだと浮いて High に見え、SSTL33+M8 VREF+PULL_MODE=DOWN のビルドで CLK0 / CLK1 のどちらに 3.35 V を当てても J12 デューティ 127/128 (VREF ≈ 3.27 V) でも 1 のまま (パッド ≈ 入力電圧)。同じ M8 VREF を使えばしきい値は ≈ 3.3 V × デューティで、CH (≈ 6.7 V × デューティ) の半分の目盛りになる。CH と同じ 0〜10 V 入力の保護は無いとみられるので、3.3 V を超える電圧は CK に入れない方がよい。
- SAMPLE の 98 セルは、JTAG 以外のユーザー I/O 49 本 × {2k: 入力 (Hi-Z) なら 1, 2k+1: パッドのレベル}。並びは IOL22A(H3) … IOL35B(P1)、IOB3A(K13) … IOB45B(G14) (map-bsr で確認)。
- アプリで取り込み中 (host の pyusb 版スターター、sipeed/sigrok_slogic の u16-demo ブランチのプロトコル) に CH0-15 に VCC を触れると、litex-boards のボールのセルが 1 本ずつ反応した → **LA の割り当て (CH0=J14 … CH15=P8) は正しい**。
- **LA 入力のしきい値 (2026-10-11 解決)**: フロントエンドにコンパレータ IC は無く、各 CH は受動部品 (分圧) だけで FPGA につながる。FPGA の入力バッファがコンパレータで、LA ピンを `IO_TYPE=SSTL33_I` にし、Bank 1 の外部 VREF を M8 に置くと動く。M8 には J12 の PWM を RC で平滑した電圧が来る。CH0 に 3V3 を当てると、J12 のデューティ (203 kHz) が 1〜3/8 では 1、4/8 以上では 0。LVCMOS33 や内部 VREF (`VREF1_LOAD`) では 3V3 を当てても 0 のまま (分圧後が約 1.64 V で、どちらにも届かない)。H14 を VREF にすると、J12 に関係なく ~0 V 相当になる (2 系統目のしきい値用か)。CH0〜15 に順に 3V3 を当てると、どの CH も J12 デューティ 3/8 まで 1、4/8 で 0 (1/8 刻みでは差なし)。しきい値の較正 (CH0、J12 203 kHz、1/128 刻み): 3.35 V は 62/63 で切り替わり (ヒステリシスなし)、4.9 V (VBUS) は 91〜93 (ノイズで揺れる)。Vth ≈ 6.7 V × デューティ (+0.06 V)、1 LSB ≈ 52 mV。VREF = 3.3 V × デューティとすると、入力の分圧比は約 0.49 (1/2)。3.3 V 入力でもパッドは約 1.64 V で、LVCMOS33 の VIH (2.0 V) にも内部 VREF (VCCIO/2) にも届かなかったのはこのため。 Bank 1 の外部 VREF は 1 本しか置けない (2 本目は CT1109 Illegal attribute) ので、FPGA 側で CH を 2 系統に分けることはできない。ビルド例:
  `make PINSET=la PULL=NONE LA_TAG=vxm8 LA_VREF=M8 LA_IO="IO_TYPE=SSTL33_I VREF=vref_ext"`
- (以下は LVCMOS33 で読んでいたときの記録) 自作デザインでは、パッドのレベル (SAMPLE) も変わらない。アプリが出力しているピン (DONE=1、READY=1、D14=1、C14=0、G14=0、J12=PWM) をすべて真似しても変わらなかった。取り込みの開始・停止でも、BSR に出るピンは赤 LED 以外変化しない。→ LA のフロントエンドは、BSR に出ないピン (MIPI 兼用ピン?) で制御されているとみられる。
- アプリ動作中は、N1 (MODE1) の入力が 1 Hz で、J12 の出力が高速にトグルしている。
- classify の結果: LA CH0-15、F14、E14 は floating。D13 は high。D14、G14、M1、H2 は low。DONE、READY、MODE0、MODE1 は high。active なピンはない (F13 などに発振器は来ていない)。

## 未確認事項

- GW5A でも SAMPLE が 0x01 か。
- バンク電圧。全ピンを LVCMOS33 として扱っているので、1.8V バンクがあると入力のしきい値がずれる。
