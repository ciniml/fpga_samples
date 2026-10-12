# SLogic16U3 ロジックアナライザ

Sipeed SLogic16U3 (GW5AT-LV15MG132C1/I0) を USB 3.0 のロジックアナライザとして使うデザインです。
16 CH を最大 800 MS/s でサンプリングし、USB 3.0 (rtl/usb3) でホストへストリーミングします。
目標は公式仕様の **800 MS/s × 4 CH、400 MS/s × 8 CH、200 MS/s × 16 CH** (どれも 400 MB/s) です。

- RTL: `rtl/la` (Veryl、`veryl test` で LaCore 全体を試験)
- USB 3.0 コア: `rtl/usb3`、PHY IP と共通部品: `../slogic16u3_usb3/src/slogic16u3`
- ホスト: `host/la_stream.c` (取り込み・テストモード検証・自動マトリクス)、`host/la_status.py` (JTAG 状態)、
  GUI は `util/serial_bridge` の `/la` (`host/web/la.html`、下記)

## 構成

```
CH0..7  ─ IDES8 ─┐                                             (sclk 100 MHz)        (pclk 125 MHz)
CK0     ─ IDES8 ─┴ LaFront A ─ LaPacker A ─ LaAfifo A ─┐
CH8..15 ─ IDES8 ─┐                                      ├─ LaFramer ─ Usb3Device EP1 IN (32 ビット入口)
CK1     ─ IDES8 ─┴ LaFront B ─ LaPacker B ─ LaAfifo B ─┘
                       ↑ 設定 (レジスタ, vendor 要求 0x03 / 0x04)
```

- クロック: USB 3.0 PHY の pclk (125 MHz、基板の 125 MHz 発振器に同期) → PLL (VCO 1200 MHz) → 400 MHz
  (IDES8 の FCLK、DDR で 800 MS/s) → CLKDIV /4 → sclk 100 MHz。1 sclk に 1 ピン 8 サンプル。
- 入力: CH は SSTL33 + 外部 VREF (M8 ← J12 の PWM を RC で平滑)。入力は基板で約 1/2 に分圧されるので、
  しきい値 ≈ 6.7 V × デューティ (レジスタ 0x10、既定 252/1024 ≈ 1.65 V)。CK0 (H13) / CK1 (G13) は
  分圧なしで同じ VREF (しきい値 ≈ 3.3 V × デューティ)。
- 2 グループ (A = CH0..7、B = CH8..15) は独立: それぞれチャネル数 (1/2/4/8、下位から)、
  サンプルクロック (内部 800 MHz / div、または自グループ / 他グループのクロック入力の立ち上がり /
  立ち下がり / 両エッジ) を持つ。取り込み開始は両グループ同じ sclk (サンプル位置がそろう)。
- 外部クロックは「クロック入力自体も 800 MS/s でサンプリングしてエッジを検出し、そこのデータを取る」方式。
  時間分解能 1.25 ns、skew (0..7) でエッジの何サンプル前のデータを取るか調整できる。
- サンプル数の制約 (論理を小さくするため。1 ワード = 10 ns = 8 サンプルから取る数を 8 の約数にしている):
  - 内部クロックの div は 1 / 2 / 4 (800 / 400 / 200 MS/s、固定位置で 8 / 4 / 2 個) か 8 以上 (100 MS/s 以下、
    1 ワードに最大 1 個)。div 3 / 5 / 6 / 7 (266 / 160 / 133 / 114 MS/s) は扱わない。
  - 外部クロックは使うエッジが 1 ワードに 1 つまで: 片エッジ 100 MHz、両エッジ 50 MHz まで。
  - それ以外は END フラグ bit 1 で止まる。
  最初の実装 (任意の位置の最大 8 個、一般の分周) は LaCore 6200 ロジックで、USB 3.0 コアと合わせて
  GW5AT-15 に収まらなかった (15308 / 15120)。この制約で 3500 になった。

## ストリーム形式 (rtl/la/la_pkg.veryl)

32 ビットワード (リトルエンディアン) のブロック列。ヘッダ 1 ワード + ペイロード `len` ワード。

| ビット | 内容 |
|---|---|
| [31:28] | 種別: 1 = サンプル (DATA)、2 = 予約 (RLE などの圧縮形式用)、4 = START、5 = END |
| [27:26] | ストリーム: 0 = グループ A、1 = グループ B |
| [23:16] | DATA: ストリームごとのブロック番号 (START 後 0 から)、START/END: キャプチャ ID |
| [15:0] | ペイロードのワード数 |

- DATA: グループのサンプルを W = 2^wlog ビットずつ、ペイロード先頭のビット 0 から詰めたもの。
  同じストリームのブロックは連続している。ブロックは 256 × 64 ビット (2 KiB) まで、ヘッダの割合は 0.2 %。
  データが少ないとき (低レート) は 20 µs 待って短いブロックを出す。
- START / END: 64 ビットの制御ビート (2 ワード)。END は [47:0] にサンプル数、[56] オーバーフロー、
  [57] 外部クロックが速すぎた。最後のワードの余りは 0 で埋まる。
- 圧縮 (RLE など) は、LaPacker と LaAfifo の間に AXI4-Stream の段を入れ、ブロック種別 2 で出す想定
  (LaFramer は FIFO の制御ビート / ブロック境界をそのまま扱う)。

モジュール間はすべて AXI4-Stream (tvalid / tready):
LaFront → LaPacker (tdata 8 レーン × 8 ビット、tkeep = サンプル数、tuser = データ / START / END)、
LaPacker → LaAfifo → LaFramer (tdata 64 + tuser 1 = 制御ビート)、LaFramer → Usb3Device (tdata 32、tlast)。
サンプリング側は止められないので、tready が下がってデータを失ったらオーバーフローとして END を出して止まる。

## レジスタ (vendor 要求 0x03 書き込み wIndex = アドレス / wValue = 値、0x04 読み出し 4 バイト)

| アドレス | 内容 |
|---|---|
| 0x00 | CTRL: [0] run (0→1 で開始、1→0 で停止)、[15:8] キャプチャ ID。読み出し = 0x01004C41 ("LA") |
| 0x01 | [0] グループ A 有効、[1] グループ B 有効。読み出し = 状態 {sclk 動作 [5], ovf B/A [4:3], run B/A [2:1], run [0]} |
| 0x02 / 0x0A | グループ A / B 設定: [1:0] wlog (1/2/4/8 CH)、[3:2] クロック (0 内部、1 立ち上がり、2 立ち下がり、3 両方)、[4] テストモード、[7:5] skew、[8] 他グループのクロック入力を使う |
| 0x03,0x04 / 0x0B,0x0C | 内部クロックの分周 div (24 ビット): 800 MHz / div |
| 0x05 / 0x0D | テストクロックの半周期 (サンプル数) |
| 0x10 | しきい値 PWM デューティ (10 ビット) |

## テストモード

設定 [4] を立てると、そのグループの 8 CH は入力ピンの代わりに PRBS (A: PRBS15、B: PRBS17、取り込み開始で
初期化)、クロック入力は半周期 thalf サンプル (2 のべき) の矩形波になる。サンプリング以降 (選択・詰め込み・FIFO・
フレーミング・USB・ホスト) を実データと同じ経路で通し、`host/la_stream` がサンプル 1 つずつ照合する
(期待値は周期表をあらかじめ作って 64 ビット単位で比較するので 400 MB/s でも追いつく)。

```
cc -O2 -o host/la_stream host/la_stream.c -lusb-1.0
host/la_stream -T                                  # テストモードのマトリクスを全部回して PASS/FAIL と MB/s
host/la_stream -a test,ch=4,rate=800M -s 10        # 1 構成を 10 秒
host/la_stream -a ch=8,rate=100M -b ch=8,clk=rise,skew=2 -s 1 -o cap   # 実入力を cap_a.bin / cap_b.bin へ
```

ホスト側のモデルは、シミュレーションが書き出したストリーム (`+dump=DIR`) を `la_stream -f` で照合して確認済み。

## ビルド

```
make PLACE_OPT=3 TAG=base          # (125 MHz のタイミングは PnR 次第: PLACE_OPT / PNR_EXTRA を変えて数通り)
```

## 実機結果 (2026-10-12、Linux xHC、ハブ経由、build p3_base: pclk 125.1 MHz / sclk 104.3 MHz で閉じた)

pclk 124.67 MHz、サンプルクロック 99.73 MHz (JTAG で実測)。リソース: ロジック 12124 / 15120 (81 %)、CLS 90 %。

`host/la_stream -T` (テストモード、全サンプル照合) は 15 構成すべて PASS:

| 構成 | 帯域 | 結果 |
|---|---|---|
| A 4 CH 800 MS/s | 400.5 MB/s | 2.4 G サンプル一致 |
| A 8 CH 400 MS/s | 400.6 MB/s | 一致 |
| A + B 8 CH 200 MS/s (16 CH) | 400.6 MB/s | 一致 |
| A + B 4 CH 400 MS/s | 400.6 MB/s | 一致 |
| A + B 2 CH 800 MS/s | 400.6 MB/s | 一致 |
| B 4 CH 800 MS/s | 400.6 MB/s | 一致 |
| 100 / 80 / 88.9 / 61.5 / 1 / 0.1 MS/s | - | 一致 |
| 外部クロック (テストクロック) 100 MHz 立ち上がり / 立ち下がり、50 / 25 MHz 両エッジ、skew 0〜7 | - | 一致 |
| 速すぎる外部クロック、div 3 | - | END フラグ 2 で停止 (期待どおり) |
| 8 CH 800 MS/s (800 MB/s) | - | オーバーフロー (フラグ 1)、それまでのデータは一致 |

長時間: 16 CH 200 MS/s を 30 秒 (12 GB)、4 CH 800 MS/s を 20 秒 × 5 回と 60 秒 × 2 回 (各 24 GB) で誤り 0。
ただし 4 CH 800 MS/s の最初の 60 秒の試行は約 1 秒でオーバーフローした (それまでのデータは一致)。
400.6 MB/s に対してリンクは 446 MB/s なので余裕は約 10 %、FIFO はグループあたり 16 KiB (40 µs 分) しかない。
ホストの転送の途切れで起きうる。BSRAM は 26 / 35 使用で、FIFO を倍 (グループあたり +8) にするには足りない。

## 実信号での確認 (2026-10-12)

信号源: Tang Primer 25K の `eda/la_pattern_gen` (25 MHz で進む 8 ビットカウンタを PMOD0 → CH0..7、同じ値の
グレイコードを PMOD2 → CH8..15、各段の中央で立ち上がるクロックを PMOD1 1 番 → CK0、ジャンパ線、GND 共通)。
`host/la_check.py` が値の変化 (+1 か) と各値の持続サンプル数を調べる。

- 内部クロック 100 / 200 / 400 / 800 MS/s: グレイコード (1 ビットずつ変わる) は全変化が +1、持続は
  サンプルレート / 25 MHz ± 1 サンプル。2 進カウンタは複数ビットが変わるときに 1〜2 サンプル (1.25〜2.5 ns)
  の中間値が出る = 配線・出力ごとのビット間スキュー (LA としては正しい観測)。
- 外部クロック (CK0 = H13 を確認、CK1 は未配線): 立ち上がりで取ると 25 MHz ちょうどのサンプル数で全サンプル +1。
  データが変わる立ち下がりで取ると skew 0 / 1 で化け、skew 2 (2.5 ns 前) 以上で 0 エラー。
  グループ B を cksel=other で CK0 に載せても同じ。
- しきい値: 3.3 V 信号でグレイコードがきれいに取れるのは 1.3〜2.5 V (既定 1.65 V)。それより外は
  リンギングで化ける。
- 帯域: 実信号でも 4 CH 800 MS/s・8 CH 400 MS/s で 400.5 MB/s、オーバーフローなし (1 秒 × 20 回中 0 回)。
- 4 CH 800 MS/s を 3 秒 (2.4 G サンプル) 取り込み、先頭 8 億サンプルのグレイコード下位 4 ビットの変化
  2343 万回がすべて 1 ビット変化 (8 ビットのグレイコードの下位 4 ビットは、上位ビットが変わる段では変わらない)。

注意: 「4 CH 800 MS/s」は合計 4 CH (片方のグループだけ)。A と B を両方 4 CH 800 MS/s にすると 800 MB/s で、
すぐオーバーフロー (END フラグ 1) する。

## GUI (util/serial_bridge の /la)

```
cd util/serial_bridge && cargo build --release
./target/release/serial-bridge -l 127.0.0.1:8082      # ブラウザで http://127.0.0.1:8082/la
```

取り込みはサーバ (Rust、nusb) が行い、ブラウザは画面に見える範囲の要約 (ピクセルごとの OR/AND) か
サンプルそのものを問い合わせる。詳細と API は `util/serial_bridge/README.md`。

- 設定: グループごとのチャネル数・クロック (内部レート / 外部エッジ、skew、他方の CK)・テストモード、
  長さ、しきい値、メモリ上限。帯域 (MB/s) と 400 MB/s 超過の警告を表示
- トリガ: 信号マップの名前で `rise(CH3) && CH5 == 0` のように書く (1 グループのチャネルのみ、
  ソフトウェア: サーバが取り込みながら全サンプルを判定)。プリトリガ % 指定
- 波形: EasyCDR トレースビューアと同じ `wave.js` (信号マップの構文・バス表示・派生信号も共通)。
  ホイールでズーム、ドラッグでパン、クリック / Shift+クリックでカーソル A/B (Δt と周波数)。
  引いた表示では変化のある区間を帯で示す
- 検索 (条件の次 / 前)、VCD 出力 (表示範囲 / 全体)

実機 (2026-10-12、Tang Primer 25K のパターン): 4 CH 800 MS/s 3 秒を 400.6 MB/s で取り込み、4.0 秒後に表示。
16 CH 200 MS/s で CH7 立ち上がりトリガ、外部クロック (CK0 立ち上がり、A/B 共用) でトリガ位置の値が
A = 128 / B = Gray(128) = 192 にそろうことを確認。

## フラッシュへの書き込み (公式 DFU、2026-10-12 実機確認)

### しくみ

- SLogic16U3 の SPI フラッシュ (XT25F128F、16 MiB) には、純正アプリが 0x0、Sipeed の DFU イメージが 0x800000 に入っている。
- MODE ボタンを押すと FPGA が再コンフィグされ、動いている位流が持つ「次の multiboot アドレス」から読み直す。
  純正の 2 つは互いを指しているので、MODE を押すたびにアプリと DFU が切り替わる。電源投入時は 0x0 から起動する。
- DFU モードでは USB2 の 359f:30f1 "SLogic DFU" として見える。これは USB-SPI ブリッジで、公式ツール
  (sipeed/slogic16u3-tools の `slogicpt.dfu`) がこれ越しにフラッシュを読み書きする。
- 自前の位流を 0x0 に書くときは、次アドレスを 0x800000 にしておく (`make dfu` / `host/mkdfu.py`、
  ビルド済みの `bitstream/slogic16u3_la.bin` は設定済み)。0 のままだと MODE で同じ位流が読み直され、DFU に戻れない。
- `host/mkdfu.py` が書き換えるのは位流ヘッダのコマンド 0xD2 の次の語 (.bin の 0x4C、Gowin の `-multi_boot 1
  -multiboot_spi_flash_address` に当たる) だけ。PnR をやり直さないので、元のビルドのタイミングが保たれる
  (同じオプションで作り直したら pclk 122 MHz になり、125 MHz を満たさなかった)。
- 平文の位流は、eFuse に AES 鍵が書かれた量産品でもフラッシュから起動する (純正の位流は暗号化されている)。

### 準備 (初回のみ)

```
git clone https://github.com/sipeed/slogic16u3-tools ~/slogic16u3-tools   # (確認したのは 018a75b)
pip install pyusb                              # (公式ツールは requirements.txt。DFU 部分は pyusb だけ使う)
# Linux: 359f (DFU / 純正アプリ) と 1209:0001 (このデザイン) をユーザーで開けるようにする
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="359f", MODE="0666"
SUBSYSTEM=="usb", ATTR{idVendor}=="1209", ATTR{idProduct}=="0001", MODE="0666"' | sudo tee /etc/udev/rules.d/60-slogic.rules
sudo udevadm control --reload
```

### 1. DFU モードにする

純正アプリ、またはこのデザインが動いている状態で MODE を 1 回押す。`lsusb` に `359f:30f1 Sipeed SLogic DFU` が
出れば DFU モード (約 1 秒かかる)。

### 2. バックアップ (書き込む前に必ず)

```
python3 host/dfu_backup.py --tools ~/slogic16u3-tools --out ~/slogic16u3-backup
# -> slogic16u3_0x000000.bin (アプリ 0x0 から 1 MiB)、slogic16u3_0x800000.bin (DFU 0x800000 から 384 KiB)、SHA256SUMS
```

読み出しだけで、消去も書き込みもしない。各領域を 2 回読み、一致したものだけを保存する (全体で約 13 秒)。
純正アプリの実体は 0x0 から約 0x78CF7 まで (このデザインは 0x9186A まで)、DFU イメージは 0x800000 から約 0x853877 まで。
JTAG の `gowin-prog dump-spi` で取ったダンプは使えない: 256 バイトごとに 3 バイトずれ、各ページの末尾 3 バイトが FF になっていた。

### 3. 書き込み

```
cd ~/slogic16u3-tools
python3 -m slogicpt.dfu.spi_flash <repo>/eda/slogic16u3_la/bitstream/slogic16u3_la.bin --pid 0x30F1 --addr 0x0
#   (自分でビルドしたもの: make PLACE_OPT=3 TAG=base dfu → build/dfu/slogic16u3_la_p3_base.bin)
```

ツールは書き込む範囲だけを 64 KiB 単位で消去し、消えたことを確かめてから書き込み、回読で照合する (最後に `Verify OK`)。
596 KB で数分かかる。0x800000 の DFU イメージには触れない。

### 4. 起動の確認

MODE を押すか USB を挿し直す。`lsusb` に `1209:0001 ... USB SS Sample` が出て (USB 3.0 ポート、`lsusb -t` で 5000M)、
`serial-bridge` の `/la` で取り込めれば成功。もう一度 MODE を押すと DFU に戻る。

### 5. 純正に戻す

DFU モードで、手順 2 のバックアップのアプリ領域を 0x0 に書き戻す:

```
cd ~/slogic16u3-tools
python3 -m slogicpt.dfu.spi_flash ~/slogic16u3-backup/slogic16u3_0x000000.bin --pid 0x30F1 --addr 0x0
```

その後 MODE を押せば純正アプリ (359f:3031) が起動する。0x800000 の DFU イメージは書き換えていないので、戻す必要はない。

### DFU に入れなくなったとき

0x0 の位流が起動しない、または次アドレスを設定し忘れた場合は、JTAG で次アドレス設定済みの位流を SRAM に読み込み、
MODE で DFU に入る (フラッシュは使わない):

```
gowin-prog --cable dap sram bitstream/slogic16u3_la.fs      # JTAG: G2 TCK / G3 TMS / J3 TDI / J2 TDO (基板の JST SH 8P)
# MODE を押す → 359f:30f1 → 手順 2〜5
```
