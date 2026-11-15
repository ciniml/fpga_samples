# cart_emu

[`../../eda/cart_emu`](../../eda/cart_emu/) (Tang Primer 25K を FPGA カートアダプタ上の MBC5 カートにする) のホストツールと L4 試験 ROM の生成。
UART は Dock の FT2232 インターフェース B (`--tty /dev/ttyUSB1`、1 Mbaud)。

```sh
cargo build --release
./target/release/cart_emu rom --logo-from dump.gb [--double] -o l4.gb   # 試験 ROM (ロゴはダンプから)
./target/release/cart_emu load l4.gb      # 応答を止めて ROM 書き込み・照合、RAM を 0xFF に、トレースを次の起動に設定、応答再開
./target/release/cart_emu clear           # カウンタを消してトレースを再設定
./target/release/cart_emu status --rom l4.gb | watch --rom l4.gb --every 60
./target/release/cart_emu trace [-n N] | arm [--at-reset] [--all] | ram -o out.sav | enable 0|1
```

64 KiB 以下の ROM なら試験 ROM 以外も読み込める (MBC5 として振る舞う。RAM は 8 KiB、バンク 0 のみ)。
