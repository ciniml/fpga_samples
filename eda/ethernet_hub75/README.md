# ethernet_hub75 — Ethernet / UDP 映像入力 → HUB75 LED マトリクス (Veryl)

PC から UDP で送った映像 (RGB565) を受けて HUB75 パネルに表示する。RTL はすべて Veryl で書いた。
プロトコルは Chisel 版 (`eda/ethernet_video`、`EthernetVideoSystem`) と互換で、送信側は既存の
`util/udpvideosend` / `util/play_video.sh` をそのまま使う。

| ボード | PHY | パネル | 状態 |
|---|---|---|---|
| Tang Primer 20K (Dock) | RTL8201F、RMII 100M | HUB75 ×2 系統 (各 64x64 ×2 枚のチェーン) = 128x128 | シミュレーション・配置配線 OK、実機未確認 |
| DK_LED-RXCARD_GW3A-LV20UG324S_V2.1 (Arora III) | (回路図待ち) | (回路図待ち) | 未着手 (資料待ち) |

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
| | `RmiiRx` `RmiiTx` | RMII アダプタ (100M)。RGMII 等はここを差し替える |
| `rtl/hub75` | `Hub75Lanes` | `Hub75` (dvi_hub75 と共通) の BCM 走査をそのまま使い、データ側を N レーン + デュアルクロックのフレームバッファにしたもの。`Hub75` 自体は変更していない |
| `src/common` | `EthService` | ARP 応答、ICMP echo (TX FIFO に入る大きさまで)、UDP の振り分け。映像の送信元を覚えておき、表示切り替えのたびに ack を返す |
| | `UdpVideoWriter` | オフセット付きのバイト列 → 画素 → 色テーブル → レーン / アドレス。フレームの最終バイトで表示切り替えを要求する |
| | `EthernetHub75Core` | 上をつないだボード非依存のコア。クロックは PHY 受信 / PHY 送信 / システム / 表示の 4 系統 (同じでもよい) |
| `src/tangprimer20k` | `TangPrimer20kTop` | PLL (27 → 49.5 MHz)、リセット、RMII アダプタ、ピン、LED |

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
| 論理 | 2859 / 20736 (14%) — LUT 2442、ALU 249、SSRAM 28 |
| レジスタ | 1314 / 16173 (9%) |
| BSRAM | 44 / 46 — フレームバッファ 36 (レーンごとに 8K×2 bit ×9)、MAC の FIFO 8 (受信 8 KB、送信 2 KB) |
| Fmax | RMII 50 MHz 系 83.8 MHz、システム 49.5 MHz 系 81.6 MHz (違反なし) |
| パネルのリフレッシュ | 356 Hz (6 bit BCM、16.5 MHz、シミュレーションで測定) |

BSRAM はほぼ埋まっている。パネルを大きくするなら、BCM のビット数を落とすか、フレームバッファを RGB565 のまま持って
読み出し側で色テーブルを引く形にする必要がある。

## ビルド

```
cd eda/ethernet_hub75
make                     # TARGET=tangprimer20k (既定)。veryl build → Gowin の合成 / 配置配線
make run                 # openFPGALoader で SRAM に書き込み (make deploy でフラッシュ)
make sim                 # テストベンチ (Verilator)
```

gw_sh が PATH にないときは `make GW_SH="env LD_LIBRARY_PATH=$HOME/gowin/1.9.12.03/IDE/lib QT_QPA_PLATFORM=offscreen $HOME/gowin/1.9.12.03/IDE/bin/gw_sh"`
(1.9.12.03 の gw_sh は `IDE/lib` を先に読ませないと Qt のプラグインで落ちる)。

## シミュレーション

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

資料待ち。決まっていること:

- ターゲット定義は `eda/targets/dk_led_rxcard_gw3a20/target.mk` (Gowin 1.9.12.03 のみが GW3A-20A に対応)
- `EthernetHub75Core` はそのまま使い、ボード側で PHY アダプタ (受信カードは GbE / RGMII の見込み)、PLL (PLLB)、ピンを用意する
- GW3A の HUB75 向けハードブロックは GMT (Generic Matrix Transpose、プリミティブ `GMT_DB`) と見られる。
  `HUB75_IMPL=soft|gmt` で切り替えられるようにし、ソフト版との比較 (LUT / FF / BSRAM、リフレッシュ、階調、最大シフトクロック、
  最大パネルサイズ) をここに書く予定。使い方は UG311 が必要
