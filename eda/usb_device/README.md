# usb_device — rtl/usb の USB 2.0 デバイスコアを Tang Primer 25K + Pmod USB で動かす

`rtl/usb` (Veryl 製 UTMI PHY + デバイスコア、HS/FS) を、TN710 USB2.0-RC 回路の Pmod USB 基板
(2 コネクタ: A = 受信側 3 差動対 + 終端制御、B = 送信対 + プルアップ + VBUS_DET) で実機評価する。

```
50MHz -> pll_usb (VCO 1200) -> 240MHz FCLK (IDES8/OSER8, 8 samples / 60MHz) + 60MHz PCLK
UsbDevice (EP0 + EP1 バルクループバック + ベンダリクエスト) --UTMI--> usb_phy_gowin (UsbPhy + IDES8/OSER8)
```

```sh
cd rtl/usb && veryl build          # (Makefile からも呼ぶ)
cd eda/usb_device
DISPLAY= QT_QPA_PLATFORM=offscreen make USB_PMOD_A=pmod2 USB_PMOD_B=pmod1 GW_SH=~/gowin/1.9.12/IDE/bin/gw_sh
make run USB_PMOD_A=pmod2 USB_PMOD_B=pmod1 OPENFPGA_LOADER_DEVICE_OVERRIDE="--busdev-num <bus:dev>"
python3 host/usb_status.py -p /dev/ttyUSB1      # 140ms ごとの状態フレーム (linestate/HS/configured/addr/frame/SOF/エラー計数)
python3 host/usb_echo.py                          # pyusb: ベンダリクエスト + EP1 バルクエコー (要 /dev/bus/usb の権限)
```

- `USB_PMOD_A` / `USB_PMOD_B` は Dock のシルク (pmod0 = 右 = F5 側、pmod1 = 中央 = A11 側、pmod2 = 左 = G11 側)。
  `src/tangprimer25k/pins.cst` はテンプレートで、project.tcl が `eda/targets/tangprimer25k/pmod_ports.csv` から
  ボールを引いて `pins_gen.cst` を生成する
- 受信 3 対は真 LVDS 入力 (`LVDS25`、オンチップ 100Ω OFF、終端は基板側)、送信対は LVCMOS33 トライステート 2 本 (SE0 のため)
- 60MHz 側の最悪パス (デバイスコア → ディスクリプタ ROM アドレス → SIE → ビットスタッフ) はスラック 0.009ns。不安定なら要パイプライン
- リセットの pclk → fclk (OSER8/IDES8 RESET) は false path

## 実機記録 (2026-09-29)

- Pmod A = pmod2、B = pmod1。書込直後、PC (Linux, xhci) に接続して **HS で列挙成功** (1209:0001 "USB PHY Sample"、
  addr 7、configured、hs=1)。一度 `can't read configurations, error -71` の後に成功
- SOF は 140ms あたり約 892 (≈ 6.4k/s、HS の 8000/s の 80%)、rxerr 計数は飽和 → HS 受信のビット位相は未調整
  (`usb_rx_dp` 対の IODELAY で追い込む余地)。VBUS_DET (pmod1 pin 3 = K11) は接続中も 0 を返す (要確認)
- FPGA 未コンフィグ時はホストから LS デバイスとして見える (TERM_RXDN の内部プルアップで D- が H になるため) →
  `device not accepting address` を吐くが無害
- HS のバルク: 8 B 100% / 64 B 90% / 512 B 25% とパケット長に比例して失敗、ベンダ OUT 50%。1 サンプル/ビットの HS 受信に
  位相追従が無く、±500ppm の周波数差で長いパケットの途中で位相を失うため (静的な位相調整では直らない)
- **FS 専用ビルド (`USB_FS_ONLY=1`) は最初列挙できなかった**。UART 経由のサンプルキャプチャ (`C` アーム / `S` 強制トリガ /
  `D` ダンプ / `R` USB コアのソフトリセット、`host/usb_capture.py`) で見ると、差動レシーバの FS 波形は 40 サンプル/ビットで
  きれいだが、単端コンパレータ (VREF 132mV) は J→K で 44ns の SE1、EOP の SE0 が割れる: 1.5k プルアップ付きの D+ の
  ホスト駆動 L レベル (約 0.1V) が VREF に近すぎる。→ `usb_phy_gowin` に `SE_FROM_DIFF=1` を追加: J/K は差動レシーバから、
  単端コンパレータは SE0 (24 サンプル多数決) の検出のみ。これで **FS は列挙・ベンダ IN/OUT・バルク 8〜2048 B とも 100%**
  (往復 0.53 MB/s)。HS は同条件で列挙は通るが、上記の位相追従問題は残る (set_configuration が失敗することもある)
- 状態表示 (`usb_status.py`) は開いた直後に OS バッファを捨てる (溜まった古いフレームを最新と誤読した)
- **HS 3 相 CDR (2026-09-29 実装、実機は未達)**: 3 系統の受信 (差動 dd、単端 D+/D− コンパレータ) に動的 IODELAY を入れ
  (`DYN_DLY=1`、UART `d`/`p`/`n` + 値で設定、`host/usb_dlyscan.py` で一致率を掃引)、dp/dn を dd に対し +1/3 / +2/3 UI 遅らせて
  24 サンプル/語 = 3 サンプル/ビットにし、`rtl/oscdr` の OsCdr (OSR=3) + BitGearbox + バイト FIFO で位相追従する
  `rtl/usb/gowin/usb_hs_cdr.v` (`HS_CDR=1`)。PHY には `i_rx_dd_valid` (語ストール) を追加。
  - 実測: dp/dn は dd より約 16 タップ (200 ps) 早い → 既定 dp=+72, dn=+127 タップ。一致率は整列で最大 91%
  - IODELAY は信号を遅らせるので、遅延を足した経路のサンプルはライン上で**前**の時刻: 時間順は [dn, dp, dd] (最初は逆順にしていて
    追従が逆方向に働いた)。OsCdr の OSR=3 対応 (argmin の 3 クラス化、dsel の mod OSR) も修正
  - `test/hs_cdr_tb.sv` (パケット + アイドル + ppm) で ±200 ppm 39〜40/40、`test/hs_cdr_replay.sv` は実機キャプチャ
    (`usb_capture.py` → `cap2hex.py`) を CDR モデルに再生し PID 検査で評価: 実機サンプルで 14/15
  - 実機: HS 列挙でアドレスまで進むが SOF 受信率 約 91%、ディスクリプタ/コンフィグで -71 が出て安定しない。
    残る誤りは単端コンパレータ (しきい値 132 mV) をデータサンプラに使う位相で起きており、3 サンプル/UI では
    エッジから 1/3 UI しか離れられないのが本質。次の一手: dd 側の IODELAY を追従させて常に差動レシーバで
    データを取る (1 UI 折返し時のビット重複処理が必要) か、Gowin IP 相当の TX Delay 方式の検討
- **IODELAY 追従ループ (2026-09-29、実機では効果なし)**: 3 系統の IODELAY をまとめて動かし、遷移が dn と dp の間に来る
  (= データは常に差動レシーバ) ように追従する `usb_hs_cdr` の `i_track_en` (UART `t` 1/0)。位相検出はまずコンパレータの
  早い/遅い投票、次に CDR の遷移ヒストグラムのクラス 0 / 2 の差で試した。シミュレーション (理想コンパレータ) では ±500 ppm で
  40/40 だが、実機ではどちらもタップが 0 に張り付き、SOF 受信率は追従 ON 5.8k/s < OFF 7.6k/s。
  原因は単端コンパレータ (しきい値 132 mV) の遷移が差動レシーバに対して極性ごとに前後にずれ、1 つのエッジが
  3 サンプル列の複数クラスに遷移として現れるため、ヒストグラムも投票も位相情報にならないこと。
  - 副産物: `dp==dd[k-1]` の一致率掃引で **IODELAY は 1 UI ≈ 144 タップ (約 14.5 ps/タップ、12.5 ではない)** と判明。
    オフセットを +60 / +108 (⅓ / ⅔ UI) に修正し、固定オフセットで SOF 受信率 95% (7.6k/8k)。dd のタップを増やす
    ほど受信率が落ちる (0: 7.1k、32: 7.5k、64: 6.4k、128: 4.7k) ので dd は小さいタップに置く
  - `usb_device_hs_stall` テスト: 受信語のストールを遅延としてモデル化し、PHY がストール (RxValid の抜け) を
    正しく扱うことを確認 (列挙・バルク PASS)。実機 HS のバルク失敗はストールが原因ではない
  - 現状の実機 HS: 列挙 OK (リトライあり)、ベンダ OUT 13/20、バルクは失敗 (Overflow / I/O error)。FS は 100%
- 次の課題: HS の位相追従。候補は差動レシーバ (rx_dd) と単端 D+ コンパレータの 2 系統に半 UI の IODELAY 差を付けた
  バンバン位相検出 + データ側 IODELAY の動的制御 (単体 IODELAY の動的モードは easycdr_bert で動作確認済み)

## HS 4 相オーバーサンプリング受信 (2026-09-29、実機で HS バルク達成)

EasyCDR と同じ方式に切り替えた: 差動レシーバを OSIDES32 (4 相 480 MHz FCLK + IODELAY 2 タップ = 3.84 Gsps、
8 サンプル/ビット) で受け、`rtl/oscdr` の OsCdr (OSR=8) で位相追従、ギアボックス→非同期 FIFO で 60 MHz UTMI へ
(`rtl/usb/gowin/usb_hs_os32.v`、`usb_phy_gowin` の `HS_OS32=1`)。480 MHz 4 相は 60 MHz pclk から
`pll_usb_os` (VCO 960) で作り (IDES8/OSER8 の 240 MHz と HCLK 群が衝突するため HS 直列経路をすべて 480 MHz 群へ)、
TX は各ビットを 2 回送る OSER8 (960 Mbps)。

結果: **HS 列挙・コントロール転送 200/200、512 B ループバック 200/200、EP1 ストリーミング 32 MB ビットパーフェクト
(片方向 ≈ 20 MB/s、往復 40 MB/s、`host/usb_stream.py`)**。全クロックでタイミング違反なし。

実機で確定した要点 (順に解決した):
- SE0 検出 (60 MHz 16 サンプル) の遅れで SYNC 全体がマスクされる → CDR をマスクせず走らせ、アイドル後は `i_reacq` で再捕捉
- 再捕捉ジャンプが SYNC 途中に当たりビット重複/欠落 → OsCdr `DLY` (抽出経路を捕捉遅延分だけ遅らせ SYNC 先頭から正位相)、
  argmin は目の中央を選ぶ重み付きコスト、クラス 0/7 のポインタ表現は「直近の連続」を選ぶ
- アイドル語を FIFO に積むと排出速度と同率で永久に溜まる → 有効語だけ書く。ウィンドウの閉じは CDR パイプライン長 (25 語) 後
- **SOF の EOP は 40 ビット長** (§7.1.13.2.2)、その後のリングダウンや他ポートのクロストークが差動レシーバに乗る →
  単端コンパレータを IDES8 (960 Msps) でスケルチにし (1 語先読み)、マスク中は直前レベルを保持 (K で終わるパケットの EOP を壊さない)
- 自分の送信 (ACK/DATA) がパイプライン遅延 (~250 ns) で tx_oe 解除後に受信されて SIE に見える → tx_oe を PCLK へ同期+12 語延長してマスク
- HS の SYNC 検出は 0 を 6 個以上要求 (ハブ短縮 12 ビットまで許容)、パケット内 400 ns 無入力でストール解除、EOP 後 2 語ブランク
- Gowin 合成は Veryl の配列 (`logic<W> [N]` を for で書く) を「RAM」として抽出し激遅なレジスタ RAM にする → packed `logic<N, W>` 一括代入
- 非同期 FIFO のグレイポインタは `syn_preserve` (wp_bin の組合せ関数に置換される)
- **応答ターンアラウンド**: 受信パイプライン込みで ~360 ns と 192 ビット時間 (400 ns) の限界付近。PHY TX が SYNC の前に 1 語 J を
  駆動していた (Sync 状態初回のアンダーラン処理) のを除去し、HS ガードを 1 クロックにしたら ACK 取りこぼしが消えた
- 送信側 60 MHz→PCLK FIFO は 2 語たまってから送出 (途中トライステート防止)、UsbPhyTx 入力にレジスタ段 (ROM→スタッファ経路)

デバッグ手段 (top.v / host/):
- `usb_log.py`: パケット単位ログ ('L')。自分宛以外のトークンと SOF は除外、TX の PID とタイムスタンプ付き。失敗直後に 'D'
- `usb_capture.py --on-error / --on-tx / --on-ping`: rxerror / 自送信 / 自分宛 PING をトリガにした 2048 語キャプチャ
- `CAP_OS=1` (`CAP_CMP=1`) ビルド: PCLK ドメインで OSIDES32 生サンプル/CDR ビット/コンパレータ IDES8 語をキャプチャ

### ソーク試験とアイ測定 (2026-09-29)

- `host/usb_soak.py`: EP1 ループバックを並行 write/read で回し続け、スループット・不一致・USB エラー・デバイス側計数を記録。
  `host/usb_stream.py` は 1 回分。`host/usb_eye.py` はアイ測定、`host/usb_log.py` はパケットログ
- **結果**: 片方向 21 MB/s (往復 42 MB/s)、USB レベルのエラー 0〜3 / 25 GB、再列挙なし。
  **ホストに見えないデータ化け** (CRC は両方向とも通る) が最初 31 回 / 33 GB (約 1 回/GB、ほぼ常に 512 B パケットの先頭バイトが
  ランダム値に化ける) → ベンダ要求で読める FIFO 書込/読出チェックサムで切り分け、**バルク FIFO (GW5A BSRAM) 内部**と確定。
  原因は書込ポートと読出ポートが同一番地を同じサイクルで叩く衝突 (アイドル中の読出番地 `rd_ptr + 前回長` = 次の OUT パケットの
  先頭番地)。読出番地をアイドル時 `rd_ptr-1` に固定し、OUT 受け入れ条件を「空き ≥ 2 パケット」(ガードバンド) にして
  衝突を構造的に排除 (FIFO 深さは 4096 に変更)。以後 先頭バイト化けは 0 だが、別種の化け (ブロック中程で 1〜3 バイト) が
  2〜7 回 / 25 GB 残る (未解決。チェックサムの整合も崩れるため FIFO 外の可能性あり)
- 送信側 60 MHz→PCLK FIFO は 8 段・見かけ占有 4 語で送出開始に変更 (配置替えで ACK 取りこぼしが再発したため)
- **アイ測定**: OSIDES32 の D 入力には外付け IODELAY を置けない (合成エラー) ため、IODELAY 掃引は不可。
  CDR を固定位相にする方式はパケットごとに位相がランダムなので使えない (どの位相でも一律 13.6% 不良 = UI の 86% が開いている、という粗い指標のみ)。
  採用したのは **SYNC 基準オフセットスキャン** (`usb_eye.py --ofs`: パケットごとに SYNC で捕捉した最良クラスに −4〜+3 のオフセットを足し、追従を止める):
  ハブ経由で毎秒 60 万個届く他デバイス宛 IN トークン (内容一定) の不良率で、**中心 ±2 クラス (5/8 UI ≈ 1.3 ns) でエラーゼロ、±3 で 4〜10%、±4 (エッジ) で 100%**。
  生サンプルではパケット内のエッジは隣接 2 クラス (≈260 ps) に収まる。バルク転送中は追従無しでは長パケットが位相ずれするので、スキャンはアイドル時に行うこと
- CDR 遷移ヒストグラム (`--hist`、捕捉位相基準) は SYNC 期間・末尾の扱いにより 5〜9% の床が乗る (シミュレーションでも同様) ので参考値
- PLL 動的位相シフト ('Z'、130 ps/ステップ) も実装したが、SYNC 捕捉が位相を吸収するため単独では意味がない
