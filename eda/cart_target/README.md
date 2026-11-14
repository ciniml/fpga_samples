# cart_target — FPGA カートアダプタの試験ターゲット (Tang Primer 25K)

`gb_fpga_cart_de0` (modretro_chromatic/cartridge) に Tang Primer 25K Dock の J3 を挿し、カートリッジとして振る舞いながら
受けたバスサイクルを独立に照合する。マスタは Chromatic の [`../chromatic_cart_bustest`](../chromatic_cart_bustest/)、
ホストは [`../../util/chromatic_bustest`](../../util/chromatic_bustest/)。

```sh
make            # GW_SH が見つからなければ GW_SH=~/gowin/1.9.12.03/IDE/bin/gw_sh make
make run        # SRAM
```

- 50 MHz → PLLA → 100 MHz。UART は Dock の FT2232 インターフェース B (`/dev/ttyUSB1`、1 Mbaud 8N1)、C3 / B3
- ピン (J3): /RST 1、AUD_PWM 2、CLK 3、RST_DRV 4、/WR 5、/RD 6、/CS 7、D_DIR 8、/D_OE 9、D0-D7 13-20、A0-A7 21-28、A8-A15 31-38
  (D1 の B2 は I2C 兼用ピンなので `use_i2c_as_gpio`)
- `CartTarget` (`rtl/chromatic/cart_target.veryl`):
  - モード: 0 ID (ハンドシェイクに応答)、1 全域 RAM、2 カートと同じ範囲の RAM (0x0000-0x7FFF、/CS 付きの 0xA000-0xBFFF)、3 無応答 (ピン試験用)
  - 読み出し: /RD Low かつ応答する番地なら D_DIR = 1 で RAM の値を出す (応答開始を `dly` クロック遅らせられる)。書き込み: /WR の立ち上がりで保存
  - 照合: マスタと同じ `BtPkg` の列を生成し、サイクルごとにアドレス・データ・読み書きの別・/CS を比べ、ビットごとの誤りマスクを数える。
    /CS は「ストローブ中に一度でも Low だったか」で判定 (マスタは /RD と /CS を同じクロックで上げるので、最後のサンプルでは /CS が先に High になっていることがある)
  - 計測: ピンのスナップショット、PHI の周波数とデューティ (1 s 窓)、D の静的駆動、RST_DRV、VIN (AUD_PWM) の矩形波

## 検証結果 (2026-11-15、gb_fpga_cart_de0、JP2 開放、Chromatic 新基板)

| 項目 | 結果 |
|---|---|
| L0 静的導通 | A0-A15・/RD・/WR・/CS・PHI (本体→ターゲット)、D0-D7 (両方向)、/RST (RST_DRV で引く / 本体が引く) すべて追従 |
| PHI | 1,000,026 Hz、デューティ 50.2 % (本体の TestBus が 60 MHz / 60 で生成) |
| L1 1 µs サイクル | 全域・カート範囲とも FILL / VERIFY / MIX (100 万回) で、マスタの読み出し誤り 0、ターゲットの照合誤り 0 (アドレス・データ・/CS・読み書き) |
| L1 0.5 µs (CGB 倍速相当) | 同上、誤り 0 |
| L2 読み出し | /RD 立ち下がりからデータが本体ピンに届くまで 67〜83 ns (ターゲットの同期 20 ns、BSRAM、D_DIR の FET 反転、4245A ×2 を含む)。ターゲットの応答を 50 ns 遅らせると合格開始がちょうど 3 クロック (50 ns) 後ろへずれる |
| L2 書き込み | 133 ns サイクル (/WR Low 16.7 ns) まで全サイクルで正しく届いた |
| 長時間 | 0.5 µs サイクル、全域 MIX (ランダムな読み書き) 5,000 万回 × 20 回 = 10 億回 (約 9 分) で、両端とも誤り 0 |

シュムー (応答遅延 0、行 = サイクル長、列 = サンプル点 2 から、`.` 合格 / `X` 誤り):
```
 60  1000 ns |XXXXX.....................................................
 30   500 ns |XXXXX.......................
 16   267 ns |XXXXX.........
  8   133 ns |XXXXX.
```

- L1 の初回は「読み出しの /CS が出ていない」が約 1 割出た。原因は照合側で、/RD が上がる直前のサンプルで /CS を見ていたため (/CS と /RD の立ち上がりのずれは 1 ns 程度と見積もれる)。
  データは正しく返っていた (カート範囲の 0xA000-0xBFFF は /CS を見て応答するので、/CS は出ている)。判定をストローブ中の OR に直して全項目合格
- 未確認: AUD_PWM → VIN (Chromatic の CART_AUDIN N14 は cst に宣言していない)、Ioff (片側だけ電源のときの回り込み、テスタで要確認)、実機の CPU タイミング (TP25K を MBC5 カートにして公式ファームで起動する L4)
