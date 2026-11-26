# chromatic_bustest

FPGA カートアダプタの試験 (Chromatic: [`eda/chromatic_cart_bustest`](../../eda/chromatic_cart_bustest/) ⇔ アダプタ ⇔
Tang Primer 25K: [`eda/cart_target`](../../eda/cart_target/))。両端が同じ xorshift32 列 (`rtl/chromatic/bt_pkg.veryl`) で
バスサイクルを独立に照合するので、誤りを向き (本体→カート / カート→本体) と信号線まで切り分けられる。

```sh
cargo build --release
./target/release/chromatic_bustest status
./target/release/chromatic_bustest pins                 # L0: 静的導通 (全 28 本 + /RST、両方向)
./target/release/chromatic_bustest suite                # L0 + PHI + L1 (1 µs / 0.5 µs、全域 / カート範囲、FILL / VERIFY / MIX)
./target/release/chromatic_bustest shmoo --dly 0,5,10   # L2: サイクル長 × サンプル点 × ターゲット応答遅延
./target/release/chromatic_bustest run --op mix --count 50000000 --timing 30,27,14,26
# モデル (rtl/chromatic/test/bt で make simexe): 両端とアダプタのモデルを Verilator で
./target/release/chromatic_bustest --sim ../../rtl/chromatic/test/bt/obj_bt/bt_sim suite --mix 20000
```

- モデルの PHI の表示は参考値 (計測窓 1 ms に対して実時間で待つため)
- ターゲットの UART は `--tty` (既定 `/dev/ttyUSB1`)、`--baud` (既定 1000000)
- `run` は 1 回の応答待ちが 60 s まで。それ以上の回数は分けて流す
- MIX は直前の FILL で本体の影メモリとターゲットの RAM がそろっている前提 (`suite` は FILL → VERIFY → MIX の順)。
  モデルは `run` ごとに起動し直すので、VERIFY は `suite` で試す
- Chromatic 上で ROM 読み出しの Web UI (`chromatic_cart_dump serve`) を動かしていると USB を取り合うので止めておく
