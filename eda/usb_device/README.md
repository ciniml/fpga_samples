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
