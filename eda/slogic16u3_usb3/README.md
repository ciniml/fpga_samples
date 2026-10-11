# slogic16u3_usb3 — Sipeed SLogic16U3 の USB 3.0 (SuperSpeed) を rtl/usb3 で動かす

状態 (2026-10-11): **SuperSpeed で動作**。1209:0001 "USB SS Sample" (5000M、bcdUSB 3.10) で列挙し、
EP1 ループバックで 1 GiB をストリーミング往復してデータ一致、片方向 51.5 MB/s (その間 Recovery 0 回)。
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
python3 host/usb3_prbs.py [-s 10]       # EP1 IN を PRBS15 送出に切り替えて帯域とバイト誤りを測る (ベンダ要求 0x02 bit0)
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

ホスト向け (IN) の帯域が SLogic の用途では重要。`o_vendor_reg` bit0 (ベンダ要求 0x02) で EP1 IN を PRBS15
(x^15 + x^14 + 1、1 バイト 8 ビット、先頭ビットが bit0) の送出に切り替え、`host/usb3_prbs.py` が全バイトを照合する。

| 読み出し要求 | 帯域 | 転送量 | バイト誤り |
|---|---|---|---|
| 1 MiB | 118.7 MB/s | 1187 MB | 0 |
| 64 KiB | 111.6 MB/s | 558 MB | 0 |
| 16 KiB | 96.0 MB/s | 480 MB | 0 |

Usb3Device の EP1 入口が 8 ビット (125 MHz × 1 バイト = 125 MB/s) で頭打ち。次は入口の 32 ビット化と bMaxBurst / IN バッファの拡大。
(参考: ループバックを送受信スレッドで同時に回すと片方向 51.5 MB/s、1 GiB 一致。)
