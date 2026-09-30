# ddc_edid — HDMI/DVI sink side channel

市販の HDMI ソースを `rtl/dvi_in` につなぐための DDC (EDID) と HPD。

| モジュール | 内容 |
|---|---|
| `ddc_edid` | 読み出し専用 I2C ターゲット (7'h50)。ランダムリード / カレントアドレスリード / 256 で折り返す連続読み出し。書き込みはオフセット 1 バイトだけ ACK。E-DDC セグメント (7'h30) と HDCP (7'h3A) には応答しない。SCL は伸ばさない |
| `hpd_ctrl` | +5V をデバウンスし、+5V あり かつ `i_ready` のときだけ HPD を上げる。`i_replug` や +5V 断で最低 `HPD_LOW_MS` (既定 200ms、HDMI は 100ms 以上で EDID 変更を通知) Low |
| `edid_rom` / `edid_rom_1080p` | `gen_edid.py` が生成する 128 バイトの組み合わせ ROM (128〜255 はミラー)。`ddc_edid` の `EDID_1080P` で選ぶ |
| `edid_rom_hdmi` | `gen_edid.py --hdmi` が生成する 256 バイトの ROM (基本ブロック + CEA-861 拡張: 720p、2ch LPCM 音声、HDMI VSDB、RGB レンジ選択可)。`ddc_edid` の `EDID_HDMI` で選ぶ (`EDID_1080P` より優先) |

## EDID

`python3 gen_edid.py [--mode 720p|1080p] [--name "..."] [--bin edid.bin]` で `edid_rom.veryl` / `edid_rom_1080p.veryl` を再生成する。
`python3 gen_edid.py --hdmi --name "FPGA HDMI RX"` で `edid_rom_hdmi.veryl` を再生成する。

- EDID 1.3、基本ブロックのみ (CEA-861 拡張なし = HDMI VSDB なし)。ソースは DVI で送ってくるので、データアイランドを持たない映像を `dvi_in` がそのまま受けられる
- タイミングは推奨の 1 つだけ: 1280x720@60 (74.25MHz) か、`--mode 1080p` で 1920x1080@60 (148.5MHz、範囲制限 66–68kHz / 150MHz)。
  キャプチャ PLL が 1 つのピクセルクロック専用なので、Established/Standard timing は空
- sRGB、範囲制限 59–61Hz / 44–46kHz / 80MHz、製品名 "FPGA DVI RX"。製造者 ID "FPG" は PNP 登録 ID ではない
- `edid-decode --check` で conformity PASS を確認済み (720p / 1080p とも)

## 接続

- すべてボード上の常時動作クロック (例: 50MHz) で動かす。TMDS から作るピクセルクロックは HPD を上げる前には存在しない
- SCL/SDA はオープンドレイン。トップで `IOBUF` の I を 0、OEN を `!o_sda_oe` にする。SCL は入力だけでよい
- DDC はソース側で 5V にプルアップされる。GW5A は 5V トレラントではないので、レベル変換 (PCA9306 等) かクランプが必要
- HPD は 2.0V 以上で High。3.3V の GPIO から 1kΩ 程度を通して出せる
- +5V は分圧して `i_5v` に入れる
- TMDS は、受信側で 3.3V へ 50Ω 終端するのが HDMI の前提。FPGA 内蔵の 100Ω 差動終端だけでは、ソースによっては振幅が出ない、または Rx sense で出力を止める

## テスト

`veryl test` (Verilator)。

- `ddc_edid_read`: ワイヤード AND バス上の I2C マスタを 100kHz と 400kHz で動かす。全 128 バイト (ヘッダ / チェックサム / DTD)、カレントアドレスリード、折り返し、0x30/0x3A への NACK、書き込みデータへの NACK、フィルタより短い SCL/SDA スパイクを確認する
- `hpd_ctrl_seq`: デバウンス、最低 Low 時間、replug、ready
