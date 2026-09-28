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
