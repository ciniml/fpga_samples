# chromatic_cart_dump

ModRetro Chromatic + `eda/chromatic_cart_dump` で、挿したカートリッジの ROM とセーブデータ (読み出しのみ) を読み出すホストツール。
詳細 (FPGA 側の安全策、対応マッパー、プロトコル) は [`../../eda/chromatic_cart_dump/README.md`](../../eda/chromatic_cart_dump/README.md)。

```sh
cargo build --release
./target/release/chromatic_cart_dump status
./target/release/chromatic_cart_dump header
./target/release/chromatic_cart_dump dump [-o out.gb] [--verify] [--mapper mbc5] [--banks 128] [--mbc1m] [--force]
./target/release/chromatic_cart_dump save [-o out.sav] [--mapper mbc3] [--force]
# 実機の代わりに Verilator モデル (rtl/chromatic/test で make simexe)
./target/release/chromatic_cart_dump --sim ../../rtl/chromatic/test/obj_sim_mbc5_r5_m0_h0/cart_sim dump
```

USB は nusb (1209:0001、vendor request 0x01 が `"GBCR"` のデバイス、EP1 OUT/IN)。
