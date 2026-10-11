# slogic16u3_usb3 — Sipeed SLogic16U3 の USB 3.0 (SuperSpeed) を rtl/usb3 で動かす

状態 (2026-10-11): **SuperSpeed で列挙する** (1209:0001 "USB SS Sample"、5000M) が不安定
(転送で -71 → リセット / 再列挙)。安定化中。

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
~/repos/rust-dap/fpga-config/target/release/gowin-prog --cable dap sram build/slogic16u3_usb3_ln0/impl/pnr/slogic16u3_usb3.fs
python3 host/usb3_status.py [-w] [-c]   # ER1: LTSSM 状態 / 遷移履歴、Polling 区間の受信統計、Polling.Config の受信語
python3 host/usb3_trace.py              # ER2: U0 の PIPE 送受信 1024 語 (デスクランブルしてパケット表示)
python3 host/usb3_trace.py --hdr        # ER2: 送受信ヘッダパケットのログ (時刻付き 128 個)
python3 host/usb3_lanes.py [-w]         # SERDES_IP=serdes_4ln: レーンごとの signal_detect など
python3 host/usb3_ref_status.py [-w]    # REF=1: PIPE 統計
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
