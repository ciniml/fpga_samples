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

## Web UI

```sh
./target/release/chromatic_cart_dump serve            # http://<この PC の IP>:8095/ (--bind で変更)
```

- 画面: 本体の状態 (1 秒ごと)、ヘッダ、「ROM をダンプ」「セーブを読む」、進捗、結果 (CRC32 / SHA-1)、ダンプ一覧 (ダウンロード)、ログ
- 「FPGA に書き込む (SRAM)」: 電源を入れ直して公式イメージに戻ったあとに、`openFPGALoader --cable gwu2x <bitstream>` で
  リーダーのデザインを SRAM に書き込む (フラッシュには書かない)。ビットストリームの既定は
  `eda/chromatic_cart_dump/build/chromatic/impl/pnr/chromatic_cart_dump.fs` (`--bitstream` で変更)
- 保存先は `~/chromatic-dumps` (`--out`)。同名で中身が違えば `<タイトル>-2.gbc` のように番号を付け、同一なら上書きしない
- 認証はない。LAN 内の誰でも読み出しとダウンロードができる (カートへの書き込みは FPGA 側で不可能)。
  外に出したくなければ `--bind 127.0.0.1:8095`
- サーバーが USB を 1 秒ごとに開くので、`serve` の動作中は CLI の他のコマンドと同時に使わない
- `--sim <cart_sim>` でも動く (操作ごとにモデルを起動し直す。FPGA 書き込みは不可)

USB は nusb (1209:0001、vendor request 0x01 が `"GBCR"` のデバイス、EP1 OUT/IN)。
