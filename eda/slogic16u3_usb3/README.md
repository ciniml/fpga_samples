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
~/repos/rust-dap/fpga-config/target/release/gowin-prog --cable dap sram build/slogic16u3_usb3_ln0/impl/pnr/slogic16u3_usb3.fs
python3 host/usb3_status.py [-w]        # ER1: LTSSM 状態 / 遷移履歴、カウンタ、受信のデコードエラー
python3 host/usb3_trace.py              # ER2: U0 の PIPE 送受信 1024 語 (デスクランブルしてパケット表示)
python3 host/usb3_trace.py --hdr        # ER2: 送受信ヘッダパケットのログ (時刻付き 128 個)
python3 host/usb3_lanes.py [-w]         # SERDES_IP=serdes_4ln: レーンごとの signal_detect など
python3 host/usb3_ref_status.py [-w]    # REF=1: PIPE 統計
python3 host/usb3_prbs.py [-s 10]       # EP1 IN を PRBS15 送出に切り替えて帯域とバイト誤りを測る (ベンダ要求 0x02 で 0x0001)
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
| 32 ビット入口、**bMaxBurst 7 (IN バッファ 8 面)** | **362.0** | 300.1 | 192.9 |

最終構成で 60 秒 21.8 GB を 362.5 MB/s、バイト誤り 0、Recovery 0 回。

ホスト側を libusb 非同期転送にすると (`host/usb3_prbs_async.c`、転送を常に複数投入、C で全バイト照合)
**425.8 MB/s** (60 秒 25.5 GB、誤り 0、Recovery 0 回、CPU 3 %)。投入数 2 以上・転送長 64 KiB 以上で頭打ち
(1 本だけ / 16 KiB でも 413 / 419 MB/s)。リンク上限 (1024 B の DP 1 個 = ヘッダ 20 + データ 1036 シンボル、
SKP 込みで約 482 MB/s) の 88 %。

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
