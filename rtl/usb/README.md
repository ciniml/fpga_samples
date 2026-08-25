# USB 2.0 PHY / ULPI / device sample (Veryl)

Gowin USB 2.0 SoftPHY IP (IPUG781) を参考に、同じ構成の USB 2.0 PHY コアと、
それを使う ULPI ラッパ・簡易デバイスコアを Veryl で実装したサンプルです。
Gowin IP と同様に UTMI (8bit/60MHz) と ULPI の両インターフェースを提供し、
HS (480Mbps) / FS (12Mbps) / LS (1.5Mbps) のペリフェラル動作をサポートします。

```
             +-------------+   UTMI   +---------+   8 samples/clk   +-----------+
 UsbDevice --|  UlpiLink   |==ULPI==>| UlpiPhy |===================| IDES8 /   |== D+/D-
   (SIE +    +-------------+          | (UsbPhy)|                   | OSER8     |
   EP0/EP1)  -------- UTMI ---------->+---------+                   +-----------+
```

## ファイル

| ファイル | 内容 |
|---|---|
| `usb_pkg.veryl` | UTMI/PID 定数、CRC5/CRC16 (LSB-first, 残差 0x06 / 0xB001) |
| `usb_phy_rx.veryl` | RX: サンプル取り込み (HS: 8 samples/clk, FS/LS: 5x/40x DPLL) → NRZI 復号 → SYNC 検出 → ビットアンスタッフ → バイト化。EOP は FS: SE0、HS: 意図的スタッフ違反 |
| `usb_phy_tx.veryl` | TX: SYNC/EOP 生成、ビットスタッフ、NRZI、直列化 (HS: 8bit/clk、FS/LS: ビット周期カウンタ)。OpMode RAW (チャープ K) 対応 |
| `usb_phy.veryl` | `UsbPhy`: UTMI 1.05 ペリフェラル PHY。バスターンアラウンド保護、終端制御出力 (pull-up / 45Ω) |
| `ulpi_phy.veryl` | `UlpiPhy`: ULPI 1.1 の PHY 側 (Gowin IP の Interface=ULPI 相当)。TXD CMD (Transmit/NOPID/RegWrite/RegRead)、RX CMD、レジスタ (Function/OTG/Interrupt/Scratch/Debug) |
| `ulpi_link.veryl` | `UlpiLink`: ULPI の Link 側。UTMI を提供し、外部 ULPI PHY (または `UlpiPhy`) を駆動 |
| `usb_sie.veryl` | `UsbSie`: パケット層 (PID 判定、トークン CRC5、DATA の CRC16 検証/生成、ハンドシェイク) |
| `usb_device.veryl` | `UsbDevice`: バス状態 (リセット検出、HS チャープハンドシェイク、サスペンド/レジューム)、EP0 標準リクエスト + ベンダリクエスト、EP1 バルクループバック (BRAM FIFO) |
| `usb_descriptor_rom.veryl` | ディスクリプタ ROM (Python で生成: device / config(FS,HS) / qualifier / strings) |
| `gowin/usb_phy_gowin.v` | Gowin TN710 の USB2.0-RC 回路 (差動 RX 対 + 単端コンパレータ ×2 + TX 対 + 終端/プルアップ) 向け TLVDS_IBUF/IDES8/OSER8 ラッパ (**未検証**、Gowin プリミティブモデルがないため) |
| `test/usb_host_bfm.sv` | ホスト BFM (SYNC/NRZI/スタッフ/EOP の符号化・復号、トークン/データ/ハンドシェイク) |
| `test/usb_phy_loopback_body.sv`, `test/usb_device_test_body.sv` | テスト本体 (HS/FS/LS、UTMI/ULPI で共用) |
| `tb_usb_phy.veryl`, `tb_ulpi.veryl`, `tb_usb_device.veryl` | `veryl test` のエントリ |

## シリアル側インターフェース

Gowin IP と同じく 60MHz クロックあたり 8 サンプル (480Msps) の並列インターフェースです
(`i_rx_dp/i_rx_dn[7:0]`, `o_tx_dp/o_tx_dn[7:0]`, `o_tx_oe`。bit 0 が最初のサンプル = IDES8 Q0 / OSER8 D0)。
受信は TN710 に合わせて 3 系統: `i_rx_dd` (差動レシーバ、HS データ)、`i_rx_dp/dn` (単端コンパレータ、LineState/FS/SE0)。
HS では 1 サンプル = 1 ビット、FS/LS ではサンプル 0 のみを使い (5x / 40x オーバーサンプル)、
TX は 8 サンプルすべてに同じ値を出します。FS/LS 専用なら `i_rx_dd = i_rx_dp` として通常の I/O に接続できます。

## テスト

```
cd rtl/usb
veryl test            # 全テスト (Verilator)
veryl test -t usb_device_hs
```

| テスト | 内容 |
|---|---|
| `usb_phy_{fs,hs,ls}_loopback` | ホスト BFM ⇄ `UsbPhy`: トークン/ハンドシェイク/0〜67 バイトデータ (all-1 でスタッフ)、スタッフ違反 → RxError、チャープ K |
| `ulpi_{fs,hs}_loopback` | 同上を UTMI → `UlpiLink` → `UlpiPhy` 経由で実行 |
| `ulpi_registers` | ULPI レジスタ R/W、set/clear エイリアス、Function Control による終端切替、LineState 変化時の RX CMD |
| `usb_device_fs` | FS ホストによるリセット (デバイスはチャープするが応答なし → FS)、列挙一式、ベンダリクエスト、バルクループバック (NAK/STALL/トグル/再送/FIFO フル/HALT)、SOF、他アドレス無視 |
| `usb_device_hs` | ハブのチャープ K-J 応答 → HS 移行、512 バイトバルク、PING を含む同一シーケンス |
| `usb_device_hs_ulpi` | HS シーケンスを `UsbDevice` → `UlpiLink` → `UlpiPhy` で実行 |

## デバイスの中身

- VID:PID = 0x1209:0x0001 (pid.codes のテスト用 ID、パラメータで変更可)、ベンダクラス (0xFF)、EP0 MPS 64
- EP1 OUT/IN バルク (FS 64 / HS 512 バイト): OUT で受けたデータをそのまま IN で返すループバック
- ベンダリクエスト: `bRequest=0x01` (IN, 4 バイト) で `i_vendor_status` を読み出し、`0x02` (OUT, wValue) で `o_vendor_reg` に書き込み
- 実機で Linux につないだ場合、`lsusb -v` で列挙され、pyusb 等でバルク転送のエコーを確認できる想定です

## 制限事項

- HS のビット位相調整 (Gowin IP の TX Delay に相当) は実装していません。1 サンプル/ビットなので RX ペアの IODELAY 等でアイ中心を合わせる必要があります
- HS EOP の後、8 ビット境界まで最大 7 ビット分レベルを保持します (OSER8 のトライステートがワード単位のため)
- ULPI: 拡張レジスタアドレス、キャリキット/6 ピンモード、ホスト/OTG 機能は非対応
- デバイス: OUT 方向のデータステージを持つ制御転送、インタラプト/アイソクロナス転送、リモートウェイクアップ、テストモードは非対応
- `gowin/usb_phy_gowin.v` は未検証です
