# chromatic_cart_bustest — カートリッジバスの試験マスタ (Chromatic)

カートリッジ側のハードウェア (FPGA カートアダプタ `gb_fpga_cart_de0` など) を試験するための Chromatic 用デザイン。
**本物のカート用ではない** (ROM の読み出しは [`../chromatic_cart_dump`](../chromatic_cart_dump/))。
対向の試験ターゲットは [`../cart_target`](../cart_target/) (Tang Primer 25K)、ホストは [`../../util/chromatic_bustest`](../../util/chromatic_bustest/)。

```
PC ─USB─ Chromatic: UsbDevice ─ BtCmd (+ BusTest, 64 KiB shadow) ─ TestBus ─ スロット
                                 └ CartPower                              │
                                                     gb_fpga_cart_de0 (4245A ×4)
PC ─UART (1 Mbaud)─ TP25K: CartTarget (RAM 64 KiB + 照合 + 計測)  ──── J3 ┘
```

- `make` / `make run` (SRAM)。USB は 1209:0001、vendor request 0x01 が `"GBBT"` (ROM 読み出しの `"GBCR"` と区別)
- **書き込み・静的駆動・試験の実行は、ハンドシェイクで試験ターゲットを確認するまで拒否する** (`rtl/chromatic/bt_cmd.veryl`)。
  0x2000 に乱数 4 バイトを書き、0x7FF0-0x7FF3 から `BtPkg::hs_answer` が返れば解錠。スロット電源が切れると施錠に戻る。
  本物のカートを挿していても、解錠されないのでランダムな書き込みは出ない (0x2000 はバンク番号の書き込みになるだけ)
- `TestBus` (`rtl/chromatic/test_bus.veryl`): サイクル長・サンプル点・/WR の位置を実行時に変えられるバスマスタと、全ピンを指定どおりに保持する静的モード
- `BusTest` (`rtl/chromatic/bus_test.veryl`): `BtPkg` の xorshift32 列 (FILL / VERIFY / MIX) を 1 サイクル 1 回で流し、読み出しを期待値と照合
- LED: 緑点滅 = USB 未接続、緑 = 待機、黄 = 通電中、青 = 通電・施錠、水色 = 解錠 (ターゲット確認済み)、白の点滅 = 試験中
- ビルド: LUT 使用率は ROM 読み出し版と同程度、clk60 Fmax 62.0 MHz / 60 MHz (2026-11-15)
