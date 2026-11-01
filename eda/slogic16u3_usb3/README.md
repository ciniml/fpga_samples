# slogic16u3_usb3 — Sipeed SLogic16U3 の USB 3.0 (SuperSpeed) を rtl/usb3 で動かす

状態 (2026-10-11): **SuperSpeed で動作**。1209:0001 "USB SS Sample" (5000M、bcdUSB 3.10) で列挙し、
EP1 IN (デバイス → ホスト) は PRBS で 362 MB/s・21.8 GB 誤り 0、ループバックの送受信同時 1 GiB 一致 (下記)。
FPGA をロードし直すと、ホストが前のデバイスとしてリセットを試み "device firmware changed" → 切断 → 再列挙を
1 回経て列挙する (ディスクリプタは 200 回読んで常に同一。電源投入から繋ぐ通常の使い方では起きない見込み)。

| 信号 | ボール | 備考 |
|---|---|---|
| SS RX (VL162 から) | A2 / A1 = Q0 LN0 RXP / RXM | 4 レーンを 5 Gb/s 受信にして LFPS の来るレーンを特定 (`SERDES_IP=serdes_4ln`) |
| SS TX | B3 / C3 = Q0 LN0 TXP / TXM | U0 まで行くので LN0 で確定 |
| 参照クロック | A8 / A7 = Q0 REFCLK0 | 125 MHz 発振器、D14 = OE |
| Type-C の向き | — | VL162 が自動で切り替える (裏返しても LN0 に LFPS が来る、FPGA 側の制御なし) |

```
D14=1 -> 125 MHz XO -> Q0 REFCLK0 -> USB 3.0 PHY IP (GUI 生成、src/slogic16u3/usb3_ln0: Q0 Lane0, QPLL0, 5 Gb/s,
         PIPE 32 bit / pclk 125 MHz) -> Usb3Top (LTSSM / link) + Usb3Device (EP1 ループバック)
内蔵発振器 ~51.66 MHz -> pll_ref125 -> PHY の ref_clk (IP 内では未使用: 合成で net が消える)
```

```sh
DISPLAY= QT_QPA_PLATFORM=offscreen make GW_SH=~/gowin/1.9.12.03/IDE/bin/gw_sh            # USB 3.0 デバイス (top.v)
make ... SERDES_IP=serdes_4ln     # レーン特定用 (top_lanes.v、Customized PHY 4 レーン)
make ... REF=1                    # 切り分け用: Gowin のリファレンスコントローラを同じ PHY で (top_ref.v)
make ... PLACE_OPT=3 PNR_EXTRA="serdesRetiming=1" TAG=sr   # PnR オプション (下記「タイミング」)
make ... TRACE=1 [TRACE_INVERT=1] # EasyCDR トレース送信 (UART ピン、下記。受信側では未確認)
make ... TAP=1 [TAP_UPAR=1]       # PHY 境界の観測 (TAP_UPAR: quad 側の DRP バス) (phy_tap.v、下記「USB 3.0 PHY IP の境界の観測」)
make ... OWNPHY=1 NOARB=1 PLACE_OPT=3 PNR_EXTRA="serdesRetiming=1" TAG=sr  # 自作 PHY、upar アービタなし (Gowin の暗号化 IP なし)
make ... OWNPHY=1 NOARB=1 QCSR=1 QCSR_STATIC=none  # さらに quad の静的設定もファブリックから (CSR ファイルは空、下記「CSR の自作」)
python3 csr/check_csr.py                # csr/gw5at15_csr.py と Gowin の toml→CSR ツールの突き合わせ
python3 host/quad_reg.py read 0x808238  # (NOARB=1) quad のレジスタを USB 越しに読み書き / csr: CSR の全アドレスを読み戻し
make ... OWNPHY=1 PLACE_OPT=4 PNR_EXTRA="serdesRetiming=1" TAG=sr  # 自作 PHY (usb3_softphy.v + rtl/usb3 usb3_phy_*) で Gowin の PHY ソフト IP を置き換え (下記)
~/repos/rust-dap/fpga-config/target/release/gowin-prog --cable dap sram build/slogic16u3_usb3_ln0/impl/pnr/slogic16u3_usb3.fs
python3 host/usb3_status.py [-w]        # ER1: LTSSM 状態 / 遷移履歴、カウンタ、受信のデコードエラー
python3 host/usb3_trace.py              # ER2: U0 の PIPE 送受信 1024 語 (デスクランブルしてパケット表示)
python3 host/usb3_trace.py --hdr        # ER2: 送受信ヘッダパケットのログ (時刻付き 128 個)
python3 host/usb3_lanes.py [-w]         # SERDES_IP=serdes_4ln: レーンごとの signal_detect など
python3 host/usb3_ref_status.py [-w]    # REF=1: PIPE 統計
python3 host/usb3_prbs.py [-s 10]       # EP1 IN を PRBS15 送出に切り替えて帯域とバイト誤りを測る (ベンダ要求 0x02 で 0x0001)
python3 host/usb3_phytap.py status|arm-log|log|arm-win|win   # TAP=1: DRP / 状態ログと送信データの窓
```

- `REF=1` は `eda/targets/tangconsole60k/doc/gowin_usb3_ref` (Gowin の GW5AT-60 用リファレンス、このリポジトリの
  ソースではない) をビルドディレクトリにコピーし、BSRAM に収めるため EP1 を 4 KiB にした
  `src/slogic16u3/ref_override/usb3_macro_define.v` で差し替えて使う。リンク確立 (SuperSpeed として認識) まで行くことで
  ボード / PHY 側の正常を確認した。
- JTAG ER2 は書き込み可 (jtag_status.v): 最上位ビットを立てて index を書いたスキャンの次のスキャンでその項目が読める。
- U0 のトレースはスクランブルされているので、ホスト側でアイドル (スクランブルされた 0) から LFSR 状態を総当たりで
  求めてデスクランブルする。

## 実機で見つかった rtl/usb3 の不具合 (シミュレーションの PIPE ホストモデルでは出なかった)

1. **Gowin USB 3.0 PHY は P0 の LFPS 指示 (TxElecIdle=1 + TxDetectRx=1) で LFPS を出さない**。ホストが Polling.LFPS から
   抜けず (受信側 RxElecIdle が LFPS のデューティ ~10% でしか解除されない) → Polling.LFPS は P2 (TxElecIdle=0) で送り、
   Polling.RxEQ の前に P0 に移る (`POLL_LFPS_P2`)。Gowin のリファレンスも同じ。送る回数もリファレンスに合わせ 27 / 受信後 10。
2. Polling.Configuration に入った後もホストは TS1 を 16 個以上送ってくる。8 連続受信フラグが TS1 でラッチしてしまい
   TS2 を待てず 12 ms で Disabled → Configuration 系の状態では TS2 だけでラッチする。
3. SET_ADDRESS の STATUS に対する ACK を新アドレスから送っていた → 送信要求時のアドレスを保持して使う。
4. STATUS に対する ACK の SeqNum が 0 で、xHC (ハブ越し) が SET_ADDRESS を -71 で失敗させた → EP0 で次に期待する
   OUT データパケットのシーケンス番号 (SETUP だけなら 1) にする (リファレンスと同じ)。

そのほか: PHY の RxElecIdle は P0 でデータを受けている間も 1 のまま (当てにならない)。GW5AT-15 (C1) では rtl/usb3 が
125 MHz に約 0.3 ns 届かない (TNS -8.6 ns / 50 端点、要対策)。

## 安定化で見つかった不具合 (続き)

5. タイムアウトフラグ (tmo_r) が新しい状態の 1 クロック目に前の状態の値を持っていた: U0 に 12 ms 以上いた後の
   Recovery.Active が即座に eSS.Inactive へ落ち、Hot Reset のたびに切断 → 状態変化直後はマスク。
6. **Gowin PHY はパケットの途中にも RxValid=0 の語を挟む** (エラスティックバッファ)。Usb3RxFifo はそれを空の語として
   窓に入れ、パーサが DPP のデータとして読んで CRC エラー (PIPE には正しい DPP が届いていた) → 空きでは窓を保持して
   パーサを止める (`o_adv` / `i_adv`、6 クロック以上続く空きだけ空の語で前進)。
7. Polling.LFPS の「2 回連続受信」を一度成立したら保持 (相手は自分の条件で先に LFPS を止める)。
8. SeqNum 31 → 0 の折り返しで `hp_seq == seq_in + 1` が幅拡張で不一致になり 32 回目の IN が -71 → `as 5`。

rtl/usb3 のテスト: `veryl test` は include_files のテスト本体を全テストの暗黙トップとして走らせるため、
どれかの終了で他が途中終了して空振り PASS していた (framer テストは窓幅が古いまま一度も走っていなかった)。
本体を `RUN` パラメータでゲートし `$finish` で終わる形にし、ホストモデルに RxValid の欠落 (97 語ごと 1 語、
389 語ごと 2 語) を入れ、SeqNum 折り返しの IN 試験を追加。上の 6 と 8 は修正前の RTL で実際に失敗することを確認済み。

## タイミング

GW5AT-15 (C1) では rtl/usb3 が 125 MHz にぎりぎりで、結果が PnR オプションと配置の偶然に強く依存する
(同じ設定でも RTL の小変更で ±15 MHz ぶれる)。`PLACE_OPT` / `ROUTE_OPT` / `PNR_EXTRA` / `TAG` で変種を並行ビルドし、
pclk が 125 MHz を満たしたものを使う (実績: place 3 + serdesRetiming=1 など)。並行ビルドの前に rtl/usb3 で
`veryl build` と生成 .sv の `touch` を済ませること (各 make が veryl build を呼び合って止まる)。

## EasyCDR トレース (TRACE=1、受信未確認)

UART_TX / UART_RX (F14 / E14、JTAG コネクタ) を LVCMOS33D の擬似差動ペアにして、rtl/trace の送信 IP で 1 Gb/s 8b10b を
出す (pclk の 64 ビット: LTSSM、送受信ヘッダの要約、DPP エラー、リセットなど、`maps/slogic16u3_usb3.map`)。
境界スキャンでピンのトグルは確認したが、Pmod EasyCDR 経由の Tang Primer 25K (eda/easycdr_trace) ではカンマが
一つも受からなかった (経路か 25K 受信側か未切り分け)。

## EP1 IN の帯域 (PRBS15)

ホスト向け (IN) の帯域が SLogic の用途では重要。`o_vendor_reg` = 0x0001 (ベンダ要求 0x02) で EP1 IN を PRBS15
(x^15 + x^14 + 1、1 バイト 8 ビット、先頭ビットが bit0、32 ビット/クロックで生成) の送出に切り替え、
`host/usb3_prbs.py` が全バイトを照合する。

| 構成 | 読み出し要求 1 MiB | 64 KiB | 16 KiB |
|---|---|---|---|
| 8 ビット入口、bMaxBurst 0 | 118.7 MB/s | 111.6 | 96.0 |
| 32 ビット入口 (`i_txw_*`)、bMaxBurst 0 | 233.2 | 205.7 | 150.1 |
| 32 ビット入口、bMaxBurst 7 (IN バッファ 8 面) | 362.0 | 300.1 | 192.9 |
| 32 ビット入口、**bMaxBurst 15 (IN バッファ 16 面)** | **376.0** | 308.8 | 202.6 |

最終構成で 60 秒 21.8 GB を 362.5 MB/s、バイト誤り 0、Recovery 0 回。

ホスト側を libusb 非同期転送にすると (`host/usb3_prbs_async.c`、転送を常に複数投入、C で全バイト照合)、
bMaxBurst 7 で 425.8 MB/s、**bMaxBurst 15 で 446.3 MB/s** (120 秒 53.5 GB、誤り 0、Recovery 0 回、CPU 3 %)。
投入数 2 以上・転送長 64 KiB 以上で頭打ち。

律速は xHC のバースト単位: ACK の NumP は 1 パケットごとに減るだけで (16→15→…→0)、0 になってから
次の NumP = 16 の ACK が来る。その間 (約 1.9 µs) リンクは空く。DP は 2.13〜2.16 µs 間隔で詰まっている
(1024 B の DP 1 個 = ヘッダ 20 + データ 1036 シンボル、SKP 込みのリンク上限は約 482 MB/s)。
8 パケット単位で 19.0 µs ごと (430 MB/s)、16 パケット単位で 36.4 µs ごと (450 MB/s)。
bMaxBurst は 15 が上限なので、これ以上はホスト側次第。

    cc -O2 -o host/usb3_prbs_async host/usb3_prbs_async.c -lusb-1.0
    host/usb3_prbs_async -s 10 -q 4 -b 1048576     # -n で照合なし (usbfs の上限で投入総量は 16 MB まで)照合なしの読み出しだけなら 383 MB/s
(Python の同期読み出し、ハブ経由)。ループバックは 8〜3072 B × 200 回、送受信同時の 1 GiB が一致 (片方向 53.8 MB/s)。

バースト化で見つけた不具合 (いずれもシミュレーションに再現テストを追加、修正前の RTL で失敗することを確認):
- 応答の受け渡し口が埋まっていると応答 (EP1 OUT の ACK など) を捨てていた → 2 段の応答キュー。
- NRDY 後、ERDY に続くホストの ACK を待たずに残っていた NumP でデータを送っていた → NRDY で許可数を 0。
- 短いパケット / ZLP の後も同じバーストで送り続けていた (ホストは転送を終えて捨てる) → それが ACK されるまで停止 (`in_stop`)。
  EOB は 0 のまま: xHC は EOB = 1 を「データ無し」と扱い ERDY を待つ (次の読み出しが始まらなかった)。
- ACK 処理と DP 送出が同じクロックに重なると `in_nsent` の更新が後勝ちで ACK 分の減算が消え、SeqNum が 1 つ飛んで停止
  → ACK を処理したクロックは送らない (デバイス内部状態をヘッダログに混ぜて記録するリングモード (トレースモード 3) で特定)。
- `flush` (短いパケットの送出) が一度立つとリセットまで立ちっぱなしで、以後は 1 クロックの空きで短いパケットを作っていた。
- NumP = 0 の ACK で送信中のパケットを送り直す規則は誤り (xHC はその後も受け取る。帯域が 25 % 落ちた)。

デバッグ用に Usb3Device は `o_dbg_event` (EP1 IN の ACK 無視 / Retry / 応答喪失 / SeqNum 飛び) と
`o_dbg_strobe` / `o_dbg_state` (EP1 IN の内部状態) を出す。

## USB 3.0 PHY IP の境界の観測 (TAP=1)

自作 PHY に向けて、Gowin の USB 3.0 PHY ソフト IP (`USB3_0_PHY_Top`、暗号化) と GTR12 quad の間の配線を観測する。
IP の中身は見ない。`project.tcl` がビルド時に `serdes.v` の写しを作り、平文の内部配線を `SerDes_Top` の
`TAP_o` / `TAP_clk_o` に出す。`phy_tap.v` が IP の DRP チャネルの読み書きと状態変化のログ (1024 件、LTSSM 状態で
開始条件を付けられる)、quad に書く送信データの窓 (1024 語) を取り、ER2 で読む。

静的設定 (CSR) について:
- `IDE/bin/serdes_toml_to_csr.dist/serdes_toml_to_csr_15k.bin --comment -o <絶対パス.csr> <絶対パス.toml>` で
  `usb3_ln0/serdes_tmp.toml` から `serdes.csr` がバイト一致で再生成でき、各書き込みにレジスタ群名が付く
  (`usb3_phytap.py log --names` に渡す)。
- USB 3.0 PHY の toml に USB 専用のキーは無い。Customized PHY と同じキーで、20 ビット・ギア 1:2・QPLL0・
  quad の 8b10b / ワード整列 / CTC はすべてバイパス (`cfg_fpcs` 0x809068 = 0x1FF)。USB の機能はすべて IP と実行時の
  DRP 操作による。
- quad の制御ピン (`FABRIC_LN0_CTRL_I` / `PD_I` / `RATE_I`) は GND 固定、`FABRIC_LN0_RXDET_RESULT` は IP に
  つながっていない。

実機 (2026-11-01、ホストのポートを disable → enable して再接続) で分かったこと:
- クロック (合成でのネット統合と実測): 送信データ = pclk = PCS TX クロック (124.9 MHz)、受信 FIFO の読み出し =
  CDR 再生クロック (124.6 MHz、IP 内のエラスティックバッファで pclk へ)、DRP = quad の常時クロック (約 56 MHz)。
- 起動後と U0 の間、IP は DRP を操作しない。
- **LFPS 送信**: 送信データで全 1 × 4 語 / 全 0 × 4 語 (320 ビット = 64 ns、15.6 MHz) の方形波を作り、
  ドライバの入り切りを DRP `0x8003a4` で行う (TxElecIdle の立ち下がりから約 0.41 µs で 7、立ち上がりで 1)。
  TxElecIdle が下りると `tx_vld` を 34 語 (約 270 ns) 落としてから方形波を流す。電気的アイドル中のデータは 0x2AA。
- **Rx.Detect**: TxDetectRx で `0x80033f` ← 0x03000000、quad の `rxdet_result` が約 1.8 µs 1 になる、
  約 4.7 µs で `0x80033f` ← 0、`0x808b34` を読む (0x02000003) → RxStatus = 3 と PhyStatus。
- **Rx.Detect 後 (P2)**: `0x808238` ← 0、`0x8082d8` ← 0 → 0x110。**P0 への移行**: `0x8003a4` ← 7、
  `0x808238` ← 0x805、`0x8082d8` ← 0 → 0x110 (CSR の初期値は `0x808238` = 0xB00)。その約 57 µs 後に `0x004031` を読む。
- 相手の LFPS は `rxelecidle_o` (1 = 信号あり) に出る。その約 0.4 µs 前に `astat` の bit5 が立つ。
- P0 に入ってからも方形波が約 34 語続き、その後 8b10b 済みのシンボル (10 ビット × 4) になる。

未観測: 受信側 (quad からの生 10 ビット、IP の整列・8b10b 復号・エラスティックバッファ)、`0x808b34` / `0x004031` の
ビットの意味、P1 / P3 (U1〜U3)。Polling.RxEQ では rtl/usb3 の LTSSM が RxPolarity を頻繁に切り替えている
(ログが埋まる。D21.5 判定の追い込み)。

## 自作 USB 3.0 PHY (OWNPHY=1)

Gowin の USB 3.0 PHY ソフト IP (`USB3_0_PHY_Top`、暗号化) を自作の PHY に置き換える。`project.tcl` が `serdes.v` の写しで
`USB3_0_PHY_Top_inst` のモジュールを `usb3_softphy` (同じポート + IP が使っていない quad の `rxdet_result`) に替える。
GTR12 quad、CSR、upar アービタは GUI 生成のまま (quad の 8b10b / 整列 / CTC はバイパスの設定)。

| 部品 | クロック | 内容 |
|---|---|---|
| `Usb3PhyTx` (rtl/usb3) | pclk (= PCS TX) | 4 シンボル/クロックの 8b/10b (RD を組み合わせで連鎖)、LFPS は全 1 × 4 語 / 全 0 × 4 語の方形波、アイドルは 1010… |
| `Usb3PhyRx` | 再生クロック (PCS RX) | 極性反転、40 ビット位置でのカンマ探索 (位置 mod 10 が境界、ずれは 2 回連続で追従)、復号 (誤りは EDB、状態 4 / 7)、速すぎるとき SKP の組を除去 |
| `Usb3PhyEb` | 再生 → pclk | 16 語の非同期 FIFO。8 語たまってから読み始め、3 語以下で 1 クロック休む (PipeRxDataValid = 0) |
| `Usb3PhyCtl` | pclk | 電力状態変化と受信側検出の PhyStatus / RxStatus、RxElecIdle |
| `Usb3PhyDrp` | DRP | TAP=1 で見た DRP 操作 (ドライバ入切 `0x8003a4`、検出 `0x80033f` / `0x808b34`、P0 移行 `0x808238` / `0x8082d8`) |

- RxElecIdle は P0 でも、正しい 8b/10b の語を受けている間は 1 にする。rtl/usb3 の LTSSM は RxElecIdle 0 が 20 ms 続くと
  Warm Reset とみなす (Gowin の PHY は P0 の間ずっと 1)。最初これをせず、U0 に入っては 20 ms で RxDetect に戻っていた。
- シミュレーション: `rtl/usb3/test/run_phy.sh` (Verilator)。8b/10b の全符号 (両 RD) の往復、送信 → ビットずれ・極性反転 →
  受信 → エラスティックバッファのループバック (受信側 ±300〜3000 ppm)、制御部と DRP 手順。

実機 (2026-11-01、`OWNPHY=1 TAP=1`、ハブ経由): **SuperSpeed で列挙** (1209:0001、5000M)、U0 で安定。EP1 IN の PRBS
382 MB/s・3.8 GB 誤り 0、ループバックの送受信同時 1 GiB 一致 (片方向 52.5 MB/s、DPP CRC エラー 0、Recovery 0)。
Gowin の PHY のときと同等。合成は PHY 部分 (IP + アービタ) が LUT 2,312 / FF 1,175 → 自作で全体 LUT 9,254 (62 %)、
pclk 125 MHz をすべて満たした (IP 版は -0.1 ns 前後)。リンク確立の途中で復号エラー 44 / 不一致 624 (U0 では増えない)。

TAP なし (`OWNPHY=1`) は配置次第で pclk が 107〜124 MHz にぶれる (遅いのは rtl/usb3 の LTSSM / デバイス部)。
`PLACE_OPT=4` が 124.1 MHz (4 端点、TNS -0.18 ns) で、実機で列挙、PRBS 379.5 MB/s 誤り 0、ループバック 1 GiB 一致、
Hot Reset (usbreset) 20 回すべて再列挙してループバック一致。place 3 (+ serdesRetiming / replicate_resources) は 115〜119 MHz。
**`PLACE_OPT=4 PNR_EXTRA="serdesRetiming=1"` で 125.15 MHz (違反なし)** — これを使う。実機で同じ試験 (PRBS 379.9 MB/s 誤り 0、
1 GiB 一致、Hot Reset 20/20) を通った。

ハブのポートを disable → enable して 5 回再接続 (Rx.Detect からやり直し): 5 回とも 5000M で再列挙し、その後のループバック
3 KiB × 50 が一致。その間にリセットのカウンタが 150、復号エラーが約 4.7 万増えた (ポート無効中の雑音と、有効化時の
Warm Reset と見ているが、Gowin の PHY と比べてはいない)。

未確認: U1〜U3 (P1 / P3)、SSC の大きいホスト、上の 2 つのカウンタの増え方が Gowin の PHY と同じか。

### upar アービタの除去 (NOARB=1)

`upar_arbiter` (最大 4 チャネルの DRP を quad の `GTR12_UPARA` 1 本にまとめる。中身は暗号化) も外せた。
- ラッパの平文部分: `drp_clk_o` = `upar_clk_i` (quad の `q0_fabric_cm_life_clk_o`) の素通し、`upar_rst_o` /
  `upar_bus_width_o` / `drp_resp_o` は 0 固定。
- `TAP=1 TAP_UPAR=1` で quad 側のバスを見た (Gowin の PHY のまま): アドレス・データはチャネル 0 と同じ、手順も同じ
  (書き込みは wren を ready まで保持し ready の次で落とす、応答まで約 5 クロック。読み出しは rden 保持 → ready → 次のクロックで
  rdvld とデータ)。
- `NOARB=1` は `serdes.v` の写しからアービタのインスタンスを除き、自作 PHY の DRP を `upar_*_s` に直結、`upar_rst` /
  `upar_bus_width` を 0 にする。SDC の drp_clk は `q0_fabric_cm_life_clk_o` に付け替える。
- 合成後のネットリストに暗号化ブロックは 0。Gowin のものは GTR12 (ハードマクロ) と CSR (GUI の toml から生成) だけ。
- 自作 PHY の受信出力 (PipeRxData / K / Valid / RxStatus / PhyStatus) は 1 段レジスタを入れた (エラスティックバッファの
  読み出しからリンク層のデスクランブラまでが 1 クロックに収まっていなかった)。
- pclk は配置次第で 97〜126 MHz。`PLACE_OPT=3 PNR_EXTRA="serdesRetiming=1"` が 125.9 MHz (違反なし)。遅いのは rtl/usb3 の
  パーサ / LTSSM / デバイス部 (いずれも -0.6 ns 前後)。
- 実機: 列挙 5000M、PRBS 379.7 MB/s 誤り 0、ループバック 1 GiB 一致 (片方向 51.8 MB/s)、Hot Reset 20/20。
  LUT 8,476 (57 %)、FF 4,898。
- ポートの disable → enable による再接続 5 回: 5 回とも 5000M で再列挙。リセットのカウンタが 150、復号エラーが約 6.3 万増えた
  (アービタありの OWNPHY と同程度)。その後も PRBS 誤り 0、1 GiB 一致、Hot Reset 20/20 (このときは別ジョブでホストの負荷が
  高く、PRBS 300〜317 MB/s、ループバック 38.6 MB/s だった)。
- rtl/usb3 の遅いパスを直した後 (2026-11-01): 既定 (PnR オプションなし) を含む 5 通りの配置がすべて 125 MHz を満たす
  (125.0〜129.9 MHz、違反なし。LUT 8,345 / FF 4,973)。直したのは次の 4 か所:
  - LTSSM: 状態に入るときの処理 (Polling バーストのカウンタ、RxPolarity / スクランブル無効のクリア、U0 の入り方) を次状態の
    判定から外した (状態の外で常時クリア、または Rx.Detect.Active でクリア)。PowerDown の変更は状態が変わった次のクロック。
  - パーサ: 読み出し位置ごとの「最初の HPSTART / LCSTART / COM×4」を前のクロックで求めてレジスタに置く。ヘッダの
    CRC-16 と TS の判定は、選んだワードを 1 段レジスタに入れてから (CRC-32 と同じ)。
  - デバイス: 送信要求を 1 段レジスタに入れてからリンクへ渡す (応答が 1 クロック遅れる)。
  実機 (p3_r2 + serdesRetiming、129.9 MHz): PRBS 381.3 MB/s 誤り 0、1 GiB 一致 (52.8 MB/s)、Hot Reset 20/20。
  libusb 非同期 (`host/usb3_prbs_async.c`、キュー 4 × 1 MiB) で 447.4 MB/s、60 秒 26.8 GB 誤り 0 (Gowin の PHY のときの
  446.3 MB/s と同じ。上の 381 MB/s は Python の同期読み出し)。

## CSR の自作 (csr/、QCSR=1)

quad の静的設定 (PnR に渡す CSR ファイル) は `upar_write_driver(アドレス, 値)` 256 行の書き込み列で、読み出しや
待ちは含まない。アドレスはバイト単位、値は 32 ビット語のアドレス下位 2 ビットのバイトレーンに置く (`0x800224` ← 0x41、
`0x800225` ← 0x4100 …。TAP=1 で見た実行時の書き込みも同じ)。
- `csr/gw5at15_csr.py`: この設計の書き込み列 (`csr/q0_ln0_base.csr`、Gowin の --comment のレジスタ群名付き) に、
  toml のキーを 1 つずつ変えて見つけたフィールドを当てて出力する。8b10b / ワード整列 / CTC (`cfg_fpcs`)、極性、信号検出の
  閾値、DC 結合、手動の受信イコライザ (`0x8082d0` boost / `0x8082d4` att / `0x8003a2`)、手動の送信 FFE (`0x808234`
  txlev / `0x808238` c1・cm / `0x8082d8`)。Gowin の PHY が P0 に入るときに書く `0x808238` ← 0x805 は FFE (c1 8、
  cm 5 = de-emphasis) と分かった。`csr/check_csr.py` で 19 通りの設定が Gowin のツールの出力とバイト一致。
- `host/quad_reg.py` (NOARB=1 のビルド): ベンダ要求 0x03 / 0x04 → top.v → `quad_drp_mux.v` (アービタの代わり、
  PHY のアクセスと 1 つずつ交互) で quad のレジスタを読み書き。リンク中に CSR の 231 アドレスを読み戻すと 230 が
  書いた値のまま (違う 1 つは PHY が実行時に書く `0x808238`)。
- 実行時の書き込みは効く: リンク中に手動イコライザの att を 0 にするとデコードエラーと Recovery が続く。
  `0x8003a7` ← 0x60000000 (手動イコライザの切り替え) だけでもリンクが落ちる。極性ビット (`0x809008`) はリンク中に
  書いても変化なし (quad の PCS 側の処理で、バイパス中は効かないと見ている)。
- `QCSR=1`: `gw5at15_csr.py --verilog` の ROM を `quad_drp_mux.v` がコンフィグ直後に書く (PHY の DRP より先)。
  `QCSR_STATIC=none` で CSR ファイルを空にしても (Gowin の静的設定なし) 実機で列挙 5000M、PRBS 381 MB/s 誤り 0、
  1 GiB 一致、Hot Reset 20/20、非同期 447.4 MB/s、再ロード 5/5。SRAM の再ロードで quad のレジスタは消える
  (ROM に無いレジスタに書いた値が 0 に戻る) ので、前のビットストリームの設定が残って動いているのではない。
- 書いた直後に PHY を動かすと、最初の Rx.Detect が続けて失敗して eSS.Disabled を一度通る (RxElecIdle が数万回
  ばたつく、書き込みの間を空けても同じ)。CSR ファイルなら quad はビットストリームのロード中 (約 3 秒) に設定される
  ので、QCSR=1 では PHY の開始を約 0.65 s 遅らせた (top.v) — これで Disabled は出なくなった。
- 電源を全部切って入れ直した後 (フラッシュの設計が先に起動し、その後 SRAM ロード) も同じ試験が通った (列挙 5000M、
  PRBS 384.7 MB/s 誤り 0、非同期 447.4 MB/s、1 GiB 一致、Hot Reset 20/20)。USB ケーブルの抜き差しからも復帰する。
- フラッシュから直接起動 (2026-11-01): q2 の位流の次アドレスを 0x800000 にして (`../slogic16u3_la/host/mkdfu.py`)
  公式 DFU で 0x0 に書き、電源を全部切って入れ直すと、コンフィグから 12 秒で 5000M で列挙 (Disabled なし)。
  PRBS 376.8 MB/s 誤り 0、1 GiB 一致、Hot Reset 20/20、非同期 447.4 MB/s。CSR ファイル無しで電源投入から動く。
  書き込み前の 0x0 / 0x800000 は `~/fpga-dumps/slogic16u3_before_qcsr_20261101/` (以前の USB3 設計、DFU は 10/12 と同一)。
- 未確認: `QCSR_STATIC=top` (top.* の 7 行だけ残す)。
