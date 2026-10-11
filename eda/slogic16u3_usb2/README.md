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

## HS (`make ... HS=1`, rtl/usb/gowin/usb_phy_gowin_sl.v)

```
pll_60m 60 MHz -> pll_hs960 (VCO 960) -> 960 MHz: IDES16 x3 / OSER16 FCLK, CLKDIV /8 = pclk 120 MHz
                                      -> 480 MHz: CLKDIV /8 = clk60 (UsbPhy + UsbDevice, HS_CAPABLE=1)
```

- dx 対 (K3/K2) は ELVDS_IOBUF (LVCMOS33D) 1 個: 送信 = OSER16、受信 = IOBUF の差動レシーバ -> IDES16。
  OSIDES32 は入力バッファ直結しか受け付けない (CK3001) ので、Gowin SoftPHY と同じ IDES16 を
  倍の FCLK 960 MHz (DDR 1.92 Gsps = 4 サンプル/ビット) で使い、OsCdr は SAMPLES 16 / OSR 4。
  比較器 (H3/H2、M2/M1) も IDES16 (スケルチ、SE0、FS の line state)。
- 送信は OSER16 で 1 ビット 4 回 (1.92 Gbps)。OSER16 にはトライステートが無いので OEN はファブリックの
  pclk レジスタから、OSER16 の遅延 (prim_sim で取り込みから約 1.9 pclk) に合わせて 2 pclk 遅らせ前後 1 語ずつ
  延長、駆動していない間はデータを最後のビットに保持。SE0 (FS の EOP) は dx 対を切って term 対を Low。
- pclk と clk60 は別の FCLK (960 / 480) の CLKDIV なので、起動ごとに約 1 ns (960 MHz の 1 周期) ずれることがある。
  usb_phy_gowin_p.v 流の「pclk のトグルを clk60 で取る」位相検出 (ph) は同じエッジのホールド競合になり、
  8 回中 2 回のロードで ph が反転して HS 受信が全滅した (チャープは通るが descriptor read -71)。
  clk60 のトグルを pclk の立ち下がりで取る方式に変えて 10/10 で列挙。
- タイミング: os_pclk Fmax 130.8 MHz (120)、clk60 63.1 MHz (60)。

### 実機記録 (2026-10-11、Linux xhci、DX=K)

- 480M で列挙 (1209:0001、bcdUSB 2.10、バルク 512 B)、SOF 約 8000/s、ロード 10 回連続で成功。
- `usb_echo.py` 8 / 64 / 512 / 1024 / 2048 B × 1000 回、2048 B × 10000 回すべて一致 (往復 11 MB/s)。
  その間の PHY 受信エラーは 5 (プロトコルの再送で回復)。
- 3584 B × 1000 回も一致 (往復 14 MB/s)。4096 B を一度に書くと、ループバック FIFO (4096 B、空きが 2 パケット以上の
  ときだけ OUT を受ける) に入りきらず、読み出す前に書き込みがタイムアウトする (試験方法の制限で、PHY とは無関係)。
