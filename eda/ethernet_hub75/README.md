# ethernet_hub75 — Ethernet / UDP 映像入力 → HUB75 LED マトリクス (Veryl)

PC から UDP で送った映像 (RGB565) を受けて HUB75 パネルに表示する。RTL はすべて Veryl で書いた。
プロトコルは Chisel 版 (`eda/ethernet_video`、`EthernetVideoSystem`) と互換で、送信側は既存の
`util/udpvideosend` / `util/play_video.sh` をそのまま使う。

| ボード | PHY | パネル | 状態 |
|---|---|---|---|
| Tang Primer 20K (Dock) | RTL8201F、RMII 100M | HUB75 ×2 系統 (各 64x64 ×2 枚のチェーン) = 128x128 | シミュレーション・配置配線 OK、実機未確認 |
| DK_LED-RXCARD_GW3A-LV20UG324S_V2.1 (Arora III) | RTL8211E、RGMII 10/100/1000M | HUB75 J4〜J9 に 64x64 を 1 枚ずつ、横 2 × 縦 3 = 128x192 (`PANEL_ROWS=2` で上 4 枚 128x128) | ソフト版 (6 枚 / 4 枚)、GMT 版 (4 枚) がシミュレーション・配置配線 OK、実機未確認 |

```
PC (udpvideosend) ── UDP 10004 ──► PHY ─ RmiiRx ─ EthRxMac ─(PktFifo: PHY clk → sys)─► EthService ─► UdpVideoWriter
                 ◄── 0xdeadbeef ──      RmiiTx ─ EthTxMac ◄─(PktFifo: sys → PHY clk)──┘   ARP / ICMP     │ 色テーブル
                                                                                                         ▼ lane / addr / RGB666
                                                       Hub75Lanes: ダブルバッファ (sys 書き込み / 表示読み出し)、6 bit BCM
                                                                                                         ▼
                                                                                         HUB75 ×N レーン (CLK / LAT / OE / A–E 共通)
```

## ソースの構成

| 場所 | モジュール | 内容 |
|---|---|---|
| `rtl/eth_mac` | `Crc32Pkg` `PktFifo` | riscv-veryl から無変更でコピー (Tang Primer 20K の実機で動作済み)。`PktFifo` はデュアルクロックのストア＆フォワード FIFO で、受信は FCS の正しいフレームだけを読み手に見せる |
| | `EthRxMac` `EthTxMac` | PHY に依存しない MAC の受信 / 送信。riscv-veryl の `EthMac` の RX / TX エンジンを、CPU バスのレジスタ部を外して切り出した。PHY アダプタとは「SFD 後のバイト列」と「バイト要求 (`i_ce`)」でつなぐ |
| | `RmiiRx` `RmiiTx` | RMII アダプタ (100M) |
| | `RgmiiRx` `RgmiiTx` | RGMII アダプタ (10/100/1000M)。DDR の入出力レジスタ (ベンダのプリミティブ) はボードのトップに置き、その出力 / 入力だけを扱う。送信は全速度を 125 MHz 1 本で回す |
| | `RgmiiSpeedMeter` `MdioMaster` | RXC の周波数からリンク速度を判定 (MDIO のポーリング不要) / clause 22 の MDIO |
| `rtl/hub75` | `Hub75Lanes` | `Hub75` (dvi_hub75 と共通) の BCM 走査をそのまま使い、データ側を N レーン + デュアルクロックのフレームバッファにしたもの。`Hub75` 自体は変更していない |
| | `Hub75Planes` | `Hub75Lanes` のフレームバッファをビットプレーン形式 (1 ワード = 1 色 1 プレーンの 32 画素分) にしたもの。GMT 版で使う |
| `src/common` | `EthService` | ARP 応答、ICMP echo (TX FIFO に入る大きさまで)、UDP の振り分け。映像の送信元を覚えておき、表示切り替えのたびに ack を返す |
| | `UdpVideoWriter` | オフセット付きのバイト列 → 画素 → 色テーブル → レーン / アドレス。フレームの最終バイトで表示切り替えを要求する |
| | `GmtCornerTurn` | GW3A の GMT ハードブロック (`GMT_DB`) で 32 画素 × RGB666 を転置し、プレーンワードにして `Hub75Planes` に書く |
| | `EthernetHub75Core` | 上をつないだボード非依存のコア。クロックは PHY 受信 / PHY 送信 / システム / 表示の 4 系統 (同じでもよい)。`HUB75_IMPL` で出力段を選ぶ (0 = `Hub75Lanes`、1 = `GmtCornerTurn` + `Hub75Planes`) |
| `src/tangprimer20k` | `TangPrimer20kTop` | PLL (27 → 49.5 MHz)、リセット、RMII アダプタ、ピン、LED |
| `src/dk_led_rxcard_gw3a20` | `DkLedRxcardTop` `Rtl8211eInit` | PLLB (50 → 125 / 50 MHz)、RGMII (IDDR / ODDR / IODELAY)、PHY の RGMII 遅延設定 (MDIO)、ピン、LED |

Veryl のプロジェクトはこのディレクトリ (`Veryl.toml`) で、`rtl/eth_mac` と `rtl/hub75` をパス依存で取り込む
(生成される SV のモジュール名は `eth_mac_EthRxMac` のように依存先の名前が前に付く)。

## プロトコル (Chisel 版と互換)

- **映像:** UDP 宛先ポート 10004。ペイロード = 2 バイトのバイトオフセット (ビッグエンディアン) + データ。
  データは RGB565 リトルエンディアン、画面全体を行優先 (128x128 なら 32768 B。udpvideosend は 1024 B ずつ 32 パケット)
- **表示切り替え:** フレームの最終バイト (オフセット 32767) を書いたら切り替えを要求し、パネルの次のフレーム境界で切り替える
  (ティアリングなし)。切り替わったら、最後に映像を送ってきた送信元 (MAC / IP / ポート) に 4 バイトの `de ad be ef` を返す。
  udpvideosend はこの返信でペースを取る (返信がなければ 100 ms で次へ進む)。切り替え待ちの間に届いた映像データは捨てる
- **アドレス:** 192.168.10.2、MAC 11:22:33:44:55:66 (どちらも Chisel 版と同じ既定値、`EthernetHub75Core` のパラメータ)。
  この MAC は先頭バイトのグループ (マルチキャスト) ビットが立っている。Chisel 版ではこれで動いていたので互換のために残したが、
  PC 側で ARP が解決しないときは `02:…` などのローカル管理アドレスに変える
- **ARP / ICMP:** ARP 要求 (宛先ブロードキャストまたは自分) に応答、ICMP echo に応答 (`ping 192.168.10.2`)
- **色テーブル (追加):** UDP 宛先ポート 10005。ペイロード = チャネルマスク 1 バイト (bit0 R、bit1 G、bit2 B) + 8 bit 値
  (エントリ 0 から。R / B は RGB565 の 5 bit 値で引く 32 エントリ、G は 6 bit 値で引く 64 エントリ)。上位 `COMPONENT_BITS` bit を使う。
  リセット後は恒等 (ビット複製で 6 bit に伸ばす = Chisel 版と同じ見え方)。ホストからは `tools/send_lut.py gamma 2.2` など
- **Chisel 版からの変更点:** 表示切り替えの 20 Hz 上限をなくした (パネルのフレーム境界で切り替え)。ポート 10000 (ループバック)、
  10001 (GPIO)、10002 / 10003 (音声) は持たない。色テーブルのポート 10005 を足した

帯域は 128x128 × 16 bit × 60 fps でペイロード 15.7 Mbps、ヘッダ込みで約 16.5 Mbps なので、100M で足りる。
udpvideosend は 1 フレーム分 (32 パケット) を間を空けずに送るので、GbE では受信側がワイヤレート (125 MB/s) で
処理し続ける必要がある。Arora 版はそのためシステムクロックを 125 MHz にしている (1 バイト / クロック)。
オフセットが 16 bit なので、この形式で送れるのは 64 KB (128x256 相当) まで。

## Tang Primer 20K

- **PHY:** Dock の RTL8201F (RMII)。50 MHz の基準クロックは PHY から来る (`rmii_txclk` = A9)。PHY はリセット中に
  クロックを止めるので、PHY のリセットピンはシステムクロック側で約 21 ms 駆動し、RMII 側のリセットはクロックが
  動き出してから外れるよう、その倍の時間かける
- **パネル:** `mod/pmod_hub75` + `mod/pmod_hub75_2` (eda/ethernet_video と同じピン)。2 系統は CLK / LAT / OE / A–E が共通で、
  各系統に 64x64 パネルを 2 枚チェーン (128x64、1/32 スキャン)。レーン 0–3 = 系統 1 の R1 / R2、系統 2 の R1 / R2 で、
  表示の行 0–31 / 32–63 / 64–95 / 96–127 に当たる
- **クロック:** システム・表示とも 49.5 MHz (27 MHz × 11 / 6)。HUB75 CLK = 49.5 / 3 = 16.5 MHz (Low 2 + High 1 クロック、
  dvi_hub75 の実機で通った 16.7 MHz とほぼ同じ)
- **LED (Active Low):** 0 = パネルのフレームごとに点滅 (約 1.4 Hz)、1 = 映像パケット受信、2 = ARP / ICMP 応答、
  3 = FCS 不良フレーム、4 = 表示切り替え、5 = PLL ロック

### 結果 (Gowin 1.9.12.03、GW2A-LV18PG256C8/I7)

| 項目 | 値 |
|---|---|
| 論理 | 2923 / 20736 (15%) — LUT 2440、ALU 273、SSRAM 35 |
| レジスタ | 1426 / 16173 (9%) |
| BSRAM | 44 / 46 — フレームバッファ 36 (レーンごとに 8K×2 bit ×9)、MAC の FIFO 8 (受信 8 KB、送信 2 KB) |
| Fmax | RMII 50 MHz 系 123.3 MHz、システム 49.5 MHz 系 119.9 MHz (違反なし。Arora 向けのレジスタ段追加後) |
| パネルのリフレッシュ | 356 Hz (6 bit BCM、16.5 MHz、シミュレーションで測定) |

BSRAM はほぼ埋まっている。パネルを大きくするなら、BCM のビット数を落とすか、フレームバッファを RGB565 のまま持って
読み出し側で色テーブルを引く形にする必要がある。

## ビルド

```
cd eda/ethernet_hub75
make                     # TARGET=tangprimer20k (既定)。veryl build → Gowin の合成 / 配置配線
make run                 # openFPGALoader で SRAM に書き込み (make deploy でフラッシュ)
make TARGET=dk_led_rxcard_gw3a20                  # Arora III、ソフト版 6 枚 128x192 (build/dk_led_rxcard_gw3a20)
make TARGET=dk_led_rxcard_gw3a20 PANEL_ROWS=2     # Arora III、ソフト版 上 4 枚 128x128 (build/dk_led_rxcard_gw3a20_4p)
make TARGET=dk_led_rxcard_gw3a20 HUB75_IMPL=gmt PANEL_ROWS=2   # Arora III、GMT 版 4 枚 (build/dk_led_rxcard_gw3a20_gmt_4p)
make TARGET=dk_led_rxcard_gw3a20 [...] run        # Gowin programmer_cli で SRAM に書き込み (変数はビルドと同じに)
make sim                 # テストベンチ (Verilator、Tang Primer 20K)
make -C test rxcard IMPL=soft|gmt [PROWS=2] [TXS=1]   # テストベンチ (Arora III、PROWS=2 は 4 枚、TXS=1 は TXC_SHIFTED 版)
```

gw_sh が PATH にないときは `make GW_SH="env LD_LIBRARY_PATH=$HOME/gowin/1.9.12.03/IDE/lib QT_QPA_PLATFORM=offscreen $HOME/gowin/1.9.12.03/IDE/bin/gw_sh"`
(1.9.12.03 の gw_sh は `IDE/lib` を先に読ませないと Qt のプラグインで落ちる)。Arora III のターゲットは
`eda/targets/dk_led_rxcard_gw3a20/target.mk` で 1.9.12.03 の gw_sh を直接指定している (GW3A-20A に対応するのは 1.9.12.03 のみ)。
`HUB75_IMPL` はビルドディレクトリに書き出すパッケージ `ethernet_hub75_cfg` 経由でトップのパラメータになる。
配置オプションは環境変数 `GW_PLACE_OPTION` / `GW_ROUTE_OPTION` で変えられる (Arora III の既定は place 2)。

## シミュレーション (Tang Primer 20K)

`make sim` (`test/tb_tp20k.sv`、Verilator 5): ボードのトップ (`TangPrimer20kTop`) をそのまま使い、RMII の向こう側の
ホストと HUB75 パネルモデルをつなぐ (PLL はシミュレーション用の置き換え、PHY リセットは短縮)。

1. ARP 要求 → 応答のフィールドを照合
2. ICMP echo 64 B / 1000 B → チェックサム (IP / ICMP)、ペイロード、長さを照合
3. FCS を壊したフレーム → 応答しない (捨てる)
4. 映像 1 フレーム (udpvideosend と同じ 32 パケット、乱数の画素) → ack を照合 → パネルモデルの 2 フレーム後の表示を全画素照合
5. 色テーブルを書き換えてから 2 フレーム目 → テーブルどおりの値になっているか全画素照合
6. もう一度 ARP (映像のあとも応答するか)

パネルモデルは CLK の立ち上がりでシフト、LAT ごとにビットプレーンを取り込み (行が変わったら MSB から)、
各プレーンの OE パルス長 (2 × 16 × 2^bit クロック) も検査する。チェーンの向きを反転させたビルドでは全画素が
不一致になることを確認済み (検査が効いていることの確認)。

## 実機の確認手順 (Tang Primer 20K)

1. HUB75 の配線は eda/ethernet_video と同じ (Dock の Pmod に HUB75 ベースボード 2 枚、各系統に 64x64 を 2 枚チェーン)
2. `make run` で書き込む。LED 5 (PLL ロック) が点灯、LED 0 が約 1.4 Hz で点滅すること
3. PC の有線 LAN を 192.168.10.1/24 にして Dock の RJ45 とつなぐ。`ping 192.168.10.2` が返り (LED 2 が点灯)、
   `ip neigh` に 11:22:33:44:55:66 が載ること
4. テストパターン: `cd util/udpvideosend && RUST_LOG=debug cargo run --release -- --width 128 --height 128 --test-pattern`。
   横縞のグラデーションが流れ、LED 1 と 4 が点灯していること。ログの fps が 100 を大きく超えていれば ack でペースが
   取れている (ack が返らないと 1 フレームごとに 100 ms 待つので、10 fps 前後に落ちる)
5. 動画: `cd util && VIDEO_FILE=<動画ファイル> ./play_video.sh` (128x128 に縮小して 20 fps で送る。同時に送られる音声
   (ポート 10002) は受け手がないので捨てられる)
6. 向きの確認: 左右が逆なら `CHAIN_REVERSE` を 1 に (トップのパラメータ)、上下や系統の入れ替わりはレーンの割り当てを見直す
7. ガンマ: `tools/send_lut.py gamma 2.2` / `tools/send_lut.py identity`

## Arora III (DK_LED-RXCARD_GW3A-LV20UG324S_V2.1)

資料: DBUG1298 (このボードのユーザーガイド、中国語版のみ)、DS1351、UG1353 / UG1354 (ピン)、UG311 (GMT)、UG313 (UBM)、
UG317 (クロック)、UG318 (GPIO)。いずれも `https://cdn.gowinsemi.com.cn/<文書番号>.pdf` (英語版は末尾に `E`) から
ログインなしで取れる。回路図そのものは公開されていない。

- **PHY:** RTL8211E ×2 (RGMII)。使うのは U43 ("PHY1": RXC が GCLKT_15 の H4、RXD は IODELAY のあるバンク 6)。
  U42 ("PHY2") の RXC は K4 = GCLKC_13 (相補側) なので使わない。どちらの RJ45 が U43 かは資料に書かれていない
- **RGMII の遅延:** RXDLY / TXDLY のストラップ抵抗が不明なので、起動時に MDIO で全アドレスを走査し、RTL8211E
  (PHY ID 1 = 0x001C) が見つかったら拡張ページ 0xa4 レジスタ 0x1c の bit 13:11 を 111 (強制 + RX / TX 遅延オン) にして
  オートネゴシエーションをやり直す (`Rtl8211eInit`、Linux の realtek ドライバと同じレジスタ。ドライバの定義とコメントで
  bit 12 / 11 のどちらが RX かが食い違っているので、両方を同じにしている)。PHY が遅延を入れるので、TXC は TXD と同じ
  ODDR から位相そろえで出し、受信は RXC で IDDR に直接取り込む。予備として PLL の 270° 出力で TXD を遅らせる版 (`TXC_SHIFTED`) と
  受信データの IODELAY (`RX_DELAY`) をパラメータで用意してある
- **速度:** 10/100/1000M に対応。RXC の周波数 (125 / 25 / 2.5 MHz) で速度を判定し、送信は 125 MHz のまま
  1000M = 毎クロック 1 バイト (DDR)、10/100M = 50 / 5 クロックごとに 1 ニブル (TXC はニブルの中央で立ち上がる)
- **パネル:** 1 組目の HUB75 (J4〜J11 は CLK / LAT / OE / A–E を共有) の J4〜J9 に 64x64 を 1 枚ずつ (チェーンなし)。
  左上から行ごとに、上段 J4 (左) / J5 (右)、中段 J6 / J7、下段 J8 / J9 で、表示は 128x192 (`PANEL_ROWS=3`、既定)。
  `PANEL_ROWS=2` は上 4 枚 (J4〜J7) で 128x128 にし、J8 / J9 は 0 (黒) を出す。レーンは幅 64 × 32 行で、表示を行優先に
  切ったもの (レーン 2k = 左、2k + 1 = 右、行 32k〜32k+31)。パネル (段 p、列 c) の R1 / R2 はレーン 4p + c / 4p + 2 + c。
  2 組目 (J12〜J19) は OE を High にして消灯。HUB75 は 74HC245 経由。ピンは DBUG1298 の表 3-6〜3-12
- **クロック:** 50 MHz (B16) → PLLB (VCO 1000 MHz) → システム / RGMII 送信 125 MHz、表示 50 MHz
  (HUB75 CLK = 50 / 3 = 16.7 MHz、dvi_hub75 の実機で通った値)
- **LED (Active Low):** LED1 = PLL ロック中、パネルのフレームごとに点滅 (約 1.4 Hz)。LED2 = 映像 / ARP / ICMP の受信で点灯、
  MDIO で RTL8211E が 1 つも見つからなかったときは速い点滅。ボタン (J6) はリセット

### HUB75 向けハードブロック: GMT

GW3A の「LED 向け」ブロックは HUB75 のドライバそのものではなく、次の 2 つ (どちらも GW3A-20 に 1 個):

- **GMT (Generic Matrix Transpose、プリミティブ `GMT_DB`、UG311):** 32 × 32 ビットの行列転置器 ×4 コンポーネント。
  各コンポーネントにピンポンバッファ 2 面。書き込みは 1 クロック 1 行 (`WADDR[5]` = 面、`WADDR[4:0]` = 行、`WDATA0..3`、`WEN0..3`)、
  読み出しは 1 クロック 1 列 (`RADDR`、データは次のクロック)。書き込みクロック最大 250 MHz、同じアドレスの書き→読み 5 ns 以内。
  書き込み行の付け替え表 (remap、mDRP で設定) あり。パラメータは `WADDR_REMAP_EN`、`COMP_EN`
- **UBM (Universal Bit Mapping、`UBM_DB`、UG313):** 32 ビットの任意ビット並べ替え ×4。GMT の出力をそのまま入力にできる
  (`BIT_REMAP_EN`、`USE_GMT_CLK`)。出力ピンの並びを合わせる用途

LED 受信カードでは「画素ごとのデータ (階調値) → ビットプレーンごとのデータ」への変換 (コーナーターン) を GMT で行う。
32 画素の階調値を 32 行として書くと、列 k を読んだ 32 ビットが「32 画素のビット k」= そのままシフトアウトできる形になる。

### ソフト版と GMT 版

| | ソフト版 (`HUB75_IMPL=soft`) | GMT 版 (`HUB75_IMPL=gmt`) |
|---|---|---|
| フレームバッファ | レーンごとに 1 画素 = RGB666 18 bit のワード | レーン × 色ごとに 1 ワード = 1 プレーンの 32 画素 |
| 書き込み | 画素ごとに 1 ワード | 32 画素を GMT に書き、18 列 (6 プレーン × 3 色) を読み出してワード書き込み |
| 表示 (シフトアウト) | 画素ワードからプレーンのビットを選ぶ (レーン × 3 本の 6:1) | ワードから x % 32 のビットを選ぶ (レーン × 3 本の 32:1) |
| 走査・BCM・タイミング | 共通 (`Hub75` と同じエンジン) | 共通 |

結果 (Gowin 1.9.12.03、GW3A-LV20UG324SC1/I0、place option 2。どちらも Ethernet 部込みの全体)。以下の表は J4 / J6 に 2 枚チェーンを
2 本つないだ最初の構成 (レーン 4 本 × 幅 128) のもの。今のパネル構成 (レーン幅 64) の結果はその下:

| 項目 | ソフト版 | GMT 版 |
|---|---|---|
| LUT / ALU | 2749 / 327 | 3142 / 331 |
| レジスタ | 1723 | 1873 |
| CLS | 2278 / 11520 (20%) | 2633 / 11520 (23%) |
| BSRAM | 84 / 120 — フレームバッファ 72 (レーンごと 18)、MAC の FIFO 12 | 108 / 120 — フレームバッファ 96 (12 メモリ × 8)、FIFO 12 |
| GMT | 0 | 1 (コンポーネント 0 のみ) |
| Fmax (制約) | RXC 225 (125)、システム 125.4 (125)、表示 85.5 (50) MHz | RXC 225 (125)、システム 125.3 (125)、表示 89.0 (50) MHz |
| リフレッシュ | 359.5 Hz (シミュレーションで測定) | 359.5 Hz (同じ) |
| 階調 | 6 bit BCM (RGB666、色テーブル経由) | 同じ |
| 最大シフトクロック | 表示 Fmax / 2 = 42 MHz (`CLK_LOW_EXTRA=0`)、既定は / 3 = 16.7 MHz | 同じ (表示 Fmax / 2 = 44 MHz) |
| 最大パネル (ダブルバッファ、6 bit) | 128x128 (BSRAM で決まる。256x128 には 144 個必要) | 128x128 (256x128 には 192 個必要) |

今のパネル構成 (64x64 を 1 枚ずつ、レーン幅 64):

| 構成 | LUT / ALU | レジスタ | BSRAM | Fmax システム / 表示 (MHz) | リフレッシュ |
|---|---|---|---|---|---|
| ソフト版 6 枚 128x192 (12 レーン) | 3186 / 327 | 1839 | 120 / 120 (100%) | 126.8 / 77.0 | 489.2 Hz |
| ソフト版 4 枚 128x128 (8 レーン) | 2942 / 327 | 1777 | 84 / 120 | 128.0 / 93.1 | 489.2 Hz |
| GMT 版 4 枚 128x128 (8 レーン) | 3635 / 331 | 1991 | 108 / 120 | 125.7 / 89.1 | 489.2 Hz |
| GMT 版 6 枚 | — | — | 入らない (下記) | — | — |

チェーンが 128 → 64 に短くなったので、リフレッシュは 359.5 → 489.2 Hz に上がる (行ごとの固定の待ちがあるので 2 倍にはならない)。
ソフト版 6 枚は BSRAM をすべて使っていて余裕がない。GMT 版はプレーンのメモリ (レーン × 色ごとに 6 プレーン × 128 ワード = 768 ワード)
が 1024 ワード = BSRAM 4 個に切り上げられるので、6 枚では 12 × 3 × 4 = 144 個必要になり入らない (合成がメモリを LUT に回して
リソース超過になる。make はこの組み合わせをエラーにしている)。プレーンを 2 枚ずつ 256 ワードのメモリに分ければ 3 個ずつ = 108 個
(FIFO と合わせて 120 個) にできる見込み

- **このデザインでは GMT 版のほうが重い。** フレームバッファを内蔵 BSRAM に置き、レーンごとに別のメモリを持つ構成では、
  ソフト版は書き込みが画素単位のまま済み、表示側のプレーン選択も 6:1 のセレクタで済むので、転置そのものが要らない。
  GMT 版は転置の制御 (グループ単位の書き出し、表示切り替えの保留) と 32:1 のビット選択が増え、LUT が約 400、FF が約 150 多い
- **BSRAM の差 (+24) はメモリの深さの端数。** プレーンメモリは 1 つ 1536 ワード (6 プレーン × 2 面 × 32 行 × 4 ワード) で、
  Gowin が 2048 ワード分 (8 個) を割り当てる。ビット数はソフト版と同じ (589,824 bit) なので、プレーン数を 8 にそろえる
  (階調 8 bit) か色をまとめたアドレス割り付けにすれば 72 個まで減らせる見込み。リフレッシュ・階調・シフトクロックは
  同じエンジンなので差がない
- **GMT が効くのは、画素データを外部メモリ (このボードの DDR2) に置く構成。** DDR から行単位で画素を読み、GMT でプレーン形式に
  変えて小さな行バッファに置けば、BCM の各プレーンのたびにフレームバッファを読み直さずに済み、パネルの大きさが BSRAM で
  決まらなくなる。そのとき同じ転置をソフトでやると、32 × 32 ビットの転置 1 組に約 1000 個の FF とセレクタが要る。
  4 コンポーネントで 16 本の出力 (このボードは 1 組あたり 48 本、計 96 本) を並列に作れる。今回は内蔵 BSRAM の構成のまま
  比べたので、この利点は数字に出ていない
- 1000M のワイヤレート処理のため、MAC / FIFO / `EthService` に 125 MHz 向けのレジスタ段を足した
  (`PktFifo` のポインタのグレイ→バイナリ変換、残りバイト数、`EthService` の判定、ack のチェックサム)。
  余裕はほぼない (システム 125.3〜125.4 MHz)。place option 1 / 3 では 1 ns 弱届かない

### シミュレーション (Arora III)

`make -C test rxcard IMPL=soft|gmt` (`test/tb_rxcard.sv`): GW3A のプリミティブ (PLLB、IDDR / ODDR、IODELAY) と `GMT_DB` は
`test/gw3a_sim.sv` の振る舞いモデル (`GMT_DB` は Gowin がモデルを出していないので UG311 の記述から書いた)。
RTL8211E 役の MDIO スレーブ (アドレス 1) と、RGMII の向こう側のホスト (PHY の遅延込みのタイミング) をつなぎ、

1. MDIO: PHY が 1 個見つかり、拡張ページ 0xa4 / 0x1c が bit 13:11 = 111 (他のビットは保持)、ページが 0 に戻り、BMCR が 1 回書かれること
2. 1000M (RXC 125 MHz) で Tang Primer 20K と同じ 1〜6 (ARP、ICMP 64 / 1000 B、FCS 不良、映像 2 フレームの全画素照合、色テーブル、ARP)。
   映像はフレーム間 12 バイトの詰めた送り方 (ワイヤレート)
3. RXC を 25 MHz にして速度判定が 100M に切り替わり、ARP と ICMP がニブル形式で通ること

`TXS=1` は `TXC_SHIFTED=1` のトップに対して、PHY 役が TX 遅延なし (TXC のエッジで TXD を取る) で同じ検査をする。

ソフト版・GMT 版 (それぞれ 6 枚 / 4 枚)・TXS=1 (ソフト版) とも PASS (6 枚は 128x192 = 24576 画素、48 パケット)。GMT 版では最初、GMT 側の保留が解けてから `Hub75Planes` が busy を出すまでの 1 クロックに busy が
落ち、ack が 2 回出ていた (検査で見つかり修正済み)。

### 実機の確認手順 (Arora III)

1. パネル: 64x64 を J4〜J9 に 1 枚ずつ、上段 J4 (左) / J5 (右)、中段 J6 / J7、下段 J8 / J9。4 枚だけなら J4〜J7 で
   `PANEL_ROWS=2` のビルドを使う
2. ボードの Type-C (J20) を PC に。`make TARGET=dk_led_rxcard_gw3a20 run` (4 枚は `PANEL_ROWS=2`、GMT 版は 4 枚のみで
   `HUB75_IMPL=gmt PANEL_ROWS=2`) で SRAM に書き込む。
   `programmer_cli` が FT232 を掴めないときは `ftdi_sio` を外す (make run が自動で外す)。ケーブルの指定が要るときは
   `PROGRAMMER_CABLE=...` (`make scan-cables` で確認)
3. LED1 が約 1.4 Hz で点滅すること (PLL ロックとパネル走査)。パネルは起動直後は黒 (フレームバッファの初期値)
4. LED2 が速く点滅し続ける場合は MDIO で PHY が見つかっていない (遅延設定が入っていない)。その場合は知らせてほしい
5. PC の有線 LAN を 192.168.10.1/24 にして、どちらかの RJ45 とつなぐ。リンク LED が点かない / ping が通らなければ反対側の
   RJ45 に差し替える (U43 がどちらか資料にない)。`ping 192.168.10.2` が返り、`ip neigh` に 11:22:33:44:55:66 が載ること。
   `ethtool <if>` でリンク速度 (1000Mb/s が期待値) も見てほしい
6. テストパターン / 動画 / 向き / ガンマは Tang Primer 20K の 4〜7 と同じだが、6 枚では画面サイズを 128x192 にする:
   `cargo run --release -- --width 128 --height 192 --test-pattern`、動画は `VIDEO_WIDTH=128 VIDEO_HEIGHT=192 VIDEO_FILE=... ./play_video.sh`
   (4 枚は 128x128 のまま)。各パネルの左右が逆なら `CHAIN_REVERSE`、パネルの位置が入れ替わっていればつなぎ先を知らせてほしい。
   GbE では udpvideosend の fps が Tang Primer 20K より上がるはず (上限はパネルのフレーム境界での切り替え待ち)
7. 4 枚構成で、ソフト版と GMT 版の表示が同じであること
8. ping が通らない場合は、RGMII のタイミングを変えたビルドを順に試す (make 変数、既定以外の値はビルドディレクトリ名に付く)。
   各ビルドで ping と `ethtool -S <if>` の受信エラー (rx_crc_errors など)、`ip -s link` の RX/TX カウンタを見てほしい

   | 変数 | 値 | 意味 |
   |---|---|---|
   | `PHY_DLY` | `on` (既定) | PHY の RX / TX 遅延を MDIO で強制オン (拡張ページ 0xa4 レジスタ 0x1c bit 13:11 = 111) |
   | | `strap` | 強制を外し、ボードのストラップ抵抗の設定に任せる (bit 13 = 0) |
   | | `off` | RX / TX 遅延を強制オフ (FPGA 側の受信はこれに対応していないので切り分け用) |
   | | 4 桁の 16 進 | bit 13:11 を直接指定。`3000` / `2800` はどちらか片方の遅延だけオン (どちらが RX かはドライバの記述が食い違う) |
   | `TXC_SHIFTED` | `1` | TXD / TX_CTL を PLL の 270° 出力の ODDR から出し、TXC がデータより 2 ns 遅れる形にする (GW3A のファブリックには立ち下がりの FF がないので TXC 側は動かさない)。PHY の TX 遅延がオフのときに使う |
   | `RX_DELAY` | 0〜255 | 受信の RXD / RX_CTL に IODELAY (1 段 12.5 ps) を入れる。PHY の RX 遅延がオンで微調整したいとき |

   試す順番の目安:
   1. `make TARGET=dk_led_rxcard_gw3a20 PHY_DLY=strap run` (MDIO の書き込み自体が悪さをしている場合)
   2. `make TARGET=dk_led_rxcard_gw3a20 PHY_DLY=3000 TXC_SHIFTED=1 run`
   3. `make TARGET=dk_led_rxcard_gw3a20 PHY_DLY=2800 TXC_SHIFTED=1 run`
      (2 と 3 は「RX 遅延だけ PHY、TX は FPGA 側でずらす」の 2 通りの解釈)
   4. ping の応答はあるが取りこぼす / 受信エラーが出る場合は `RX_DELAY=40` (0.5 ns)、`RX_DELAY=80` (1 ns) を足す
