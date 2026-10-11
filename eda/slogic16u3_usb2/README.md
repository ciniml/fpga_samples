# slogic16u3_usb2 — Sipeed SLogic16U3 の USB 2.0 を rtl/usb で動かす (現状: full speed)

SLogic16U3 (GW5AT-LV15MG132C1/I0) の USB-C の D+/D- は、Gowin USB 2.0 SoftPHY の "Single LVDS" 配線
(IPUG781) になっている。ピンは `eda/slogic16u3_probe` の調査で特定した。

| 信号 | ボール | 備考 |
|---|---|---|
| D+ | H3 (比較器、H2 = VREF)、K3、P2 | |
| D- | M2 (比較器、M1 = VREF)、K2、P1 | |
| dx / term の対 | K3/K2 と P2/P1 | どちらが dx かは未確定 (FS ではどちらでも動く) |
| 1.5k プルアップ | C14 | High で有効 |
| 125 MHz 発振器の OE | D14 | High で発振 (SerDes Q0 REFCLK0) |
| ACT LED 赤 | G14 | configured で点灯 |

```
D14=1 -> 125 MHz XO -> SerDes Q0 REFCLK0 -> Customized PHY (Q0 Ln0, GUI 生成, src/slogic16u3/serdes)
      -> tx_pcs_clkout 125 MHz -> pll_60m (PLLA VCO 1200) -> 60 MHz -> UsbDevice + UsbPhy (rtl/usb, HS_CAPABLE=0)
```

```sh
DISPLAY= QT_QPA_PLATFORM=offscreen make GW_SH=~/gowin/1.9.12.03/IDE/bin/gw_sh DX=K     # DX=K|P: dx 対の候補
~/repos/rust-dap/fpga-config/target/release/gowin-prog --cable dap sram build/slogic16u3_dxk/impl/pnr/slogic16u3_usb2.fs
python3 host/usb2_status.py [-w]                     # JTAG ER1 の状態 (clk60 実測、line state、addr、SOF ...)
python3 ../usb_device/host/usb_echo.py --bytes 2048 --rounds 100
```

- FS は 60 MHz で 1 サンプル/クロック (FS 1 ビット = 5 クロック) で足りるので、dx 対を LVCMOS33 の
  独立した 2 本の双方向ピンとして使い (J/K/SE0 を直接駆動、D+/D- を単端で読む)、term 対はトライステートのまま。
- GW5AT-15 の SerDes は静的設定を `.csr` で受け取る。gw_sh にはそのオプションが無いので、project.tcl は
  プロジェクトを作って `.gprj.user` に `RES.serdes.csr` を書き、子の gw_sh でそのプロジェクトを開いて run all する。
- 状態は GW_JTAG ER1 (IR 0x42) の読み出し専用 128 ビット (src/slogic16u3/jtag_status.v。TCK/TDI を内蔵発振器で
  オーバーサンプルする slogic16u3_probe と同じ方式)。

## 実機記録 (2026-10-11)

- clk60 は 59.96〜60.03 MHz (内蔵発振器 51.66 MHz 基準の測定)。
- **比較器の対 (H3/H2、M2/M1) は必ずポートとして宣言すること**。未使用ピンのままだと既定の弱プルアップが
  D+ と D- の両方を引き上げ、line state が SE1 のままホストが列挙できなかった。LVDS25 (PULL_MODE=NONE) の
  入力にして解決。
- DX=K、DX=P とも FS で列挙 (1209:0001 "USB PHY Sample")、SOF 約 1000/s、受信エラー 0。
  `usb_echo.py` のバルクループバック 8 / 64 / 512 / 2048 B × 100 回すべて OK (往復 0.53 MB/s)。
- 次: HS (dx 対を差動受信 + OSIDES32 で 4 相オーバーサンプル、送信は dx 対、終端は term 対)。
