# Pmod 1 ポート版 USB 2.0 HS デバイス基板 — 設計検討

README.md の 2 ポート版 (TN710 Dual LVDS、11 I/O + VBUS 検出) を Pmod 1 ポート (8 I/O、差動対 4) に収める案。
Gowin USB 2.0 SoftPHY の **Single LVDS** 配線 (IPUG781 §3.2 図 3-2) をベースに、**D- 側の比較器を省いた 7 本**で
HS まで動かす。残る 1 本は VBUS 検出に使う。

状態:
- RTL (`rtl/usb/gowin/usb_phy_gowin_sl.v` の `CMP1=1`) は Sipeed SLogic16U3 で HS 実機確認済み (2026-10-12、§6)。
- 回路図と基板は未作成。Tang Primer 25K での動作も未確認。

## 1. 9 本 → 7 本にできる理由

Single LVDS の標準構成は 9 本。

| 用途 | 本数 | 役割 |
|---|---|---|
| dx 対 (LVCMOS33D 双方向) | 2 | HS/FS 送信 (OSER16) と差動受信 (IDES16) を 1 対で兼ねる |
| D+ 比較器 (D+ / VREF) | 2 | スケルチ、SE0、FS line state |
| D- 比較器 (D- / VREF) | 2 | 同上 |
| term_dp / term_dn | 2 | Low 駆動で HS 終端、FS の SE0 送信 |
| 1.5k プルアップ制御 | 1 | |

PHY を読むと、比較器 2 個を使っているのは次の 2 か所だけだった。

- HS スケルチ: `|cdp | |cdn` (どちらかが VREF を超えている)
- SE0 判定: `~cdp & ~cdn` (両方が VREF 未満)

D- 比較器が担っていた判定は、どれも次のように別の信号で置き換えられる。

| 場面 | 9 本版 | 7 本版 (CMP1) | 根拠 |
|---|---|---|---|
| HS スケルチ | D+ と D- の OR、2 語 (8 UI) の窓 | **D+ だけ**、OR の窓を 3 語 (48 サンプル = 12 UI) に拡大 | ビットスタッフィングにより、パケット中は遷移のない区間が最長 7 UI。D+ は 8 UI 以内に必ず一度 High になる |
| FS の SE0 と line state | 2 つの比較器の多数決 | **term ピンの LVCMOS33 入力** | FS 中は term ピンが Hi-Z で、FS の振幅は 0 / 3.3 V なので通常の閾値 (VIL 0.8 / VIH 2.0 V) で判定できる |
| チャープ (xcvrselect = HS、termselect = FS) | 比較器から J/K/SE0 | **SE0 を出さず、dx レシーバの J/K だけ** | ホストのチャープ (デバイス側に HS 終端がなく約 800 mV) は LVCMOS では Low に読め、SE0 と区別できない。`UsbDevice` の ChirpWait は K と J がそれぞれ 2.5 µs 続くのを待つだけ。FS ホストが SE0 を続けても、dx の出力は交互に変わらないので K-J の組にはならない |
| HS 中のリセットとサスペンド | スケルチ (3 ms 無信号) → HsRevert | 同じ | HsRevert 後は FS 終端に戻るので、LVCMOS 入力で SE0 か J かを判定する |

PHY はモードを UTMI の xcvrselect / termselect で知るので、`UsbDevice` 側の変更は不要。

### 検討して採らなかった案

- **プルアップを常時有効にする (8 本)**: ソフトコネクトができなくなる。また HS 中に D+ に約 49 mV の DC オフセットが乗り、仕様から外れる。
- **抵抗で D+ と D- の中点を作り、比較器 1 個で両線を見る**: FS アイドル時に D- を引き上げないよう各脚を 75 kΩ 以上にする必要があり、τ ≈ 375 ns と遅すぎて HS SYNC のスケルチに間に合わない。高速化のコンデンサは HS 線路の負荷になる。
- **SSTL 入力をバンクの VREF ピンで共用する**: VREF の下限が 130 mV まで下げられるか不明。そもそもバンクの VREF ボールは Pmod に出ていない。

## 2. 回路

```
 Type-C (USB2.0 only)                     Pmod 基板                                    FPGA (Pmod 1 ポート)
 VBUS ──┬─ 100k/22k ──────────────────────────────── VBUS_DET ─────────────────────── 10: LVCMOS33 in
        └─ 1uF
 CC1 ── 5.1k ── GND, CC2 ── 5.1k ── GND   (UFP: Rd)

 D+ ─┬─ ESD ─┬── Rs ──────────────────────────────── DX_P   ┐ 1/7: LVCMOS33D 双方向
 D- ─┼─ ESD ─┼── Rs ──────────────────────────────── DX_N   ┘      (送信 + 差動受信)
 90Ω │       ├──────────────────────────────────── CMP_P (D+) ┐ 2/8: LVDS25 入力
     │       │                       VREF ───────── CMP_N      ┘
     │       ├── Rt ──────────────────────────────── TERM_DP  ┐ 3/9: LVCMOS33 双方向
     │       ├── Rt ──────────────────────────────── TERM_DN  ┘      (Low = 45Ω 終端、Hi-Z = FS 入力)
     │       └── R1 1.5k ──────────────────────────── PULLUP   4: LVCMOS33 out (D+ のみ)
 VREF = 3.3V × R9/(R8+R9) ≈ 130 mV  (R8 1.8k, R9 75Ω, C1 1uF + 0.1uF)
```

2 ポート版との違いは次のとおり。

- dx 対は送受信を 1 対で兼ねる (IPUG781 Single)。2 ポート版の `USB_RX_D+/-` と `USB_TX_D+/-` が 1 対になる。
- D- 比較器 (`USB_RXDN_*`) を削除した。VREF は D+ 比較器の N 側だけに入る。
- term 対は出力専用ではなく、FS の受信入力も兼ねる。直列 Rt を通して読むが、入力はハイインピーダンスなので問題ない。

### 2.1 定数 (Arora-V、TN710 の値から出発)

SLogic16U3 の実装値は未確認 (回路図なし)。TN710 の Arora-V の値を初期値とし、HS の振幅を実測して詰める。

| 部品 | 値 | 役割 | 備考 |
|---|---|---|---|
| Rs (×2) | 100 Ω | dx 対の直列 | TN710 R6/R7 (Arora-V)。受信も同じ抵抗を通るが、入力はハイインピーダンス |
| Rt (×2) | 36 Ω | HS 終端 (ピン出力インピーダンス + Rt ≈ 45 Ω) | TN710 R2/R3 (Arora-V) |
| R1 | 1.5 kΩ | D+ プルアップ | |
| R8 / R9 | 1.8 kΩ / 75 Ω | VREF ≈ 130 mV | 比較器は 1 個 |
| C1 | 1 µF + 0.1 µF | VREF バイパス | 0.1 µF は CMP_N ピンの直近 |
| CC Rd | 5.1 kΩ ×2 | UFP 表示 | ないとホストが VBUS を出さない |
| VBUS 分圧 | 100 kΩ / 22 kΩ | 5 V → 0.9 V | LVCMOS33 入力、PULL_MODE=DOWN |
| ESD | TPD2E001 / USBLC6-2SC6 | | 低容量 |

IO 属性 (IPUG781、Arora-V) は次のとおり。

- dx: `LVCMOS33D DRIVE=8 DIFF_RESISTOR=OFF`
- term / プルアップ: `LVCMOS33 DRIVE=8`
- 比較器: `LVDS25 DIFF_RESISTOR=OFF`
- 全ピン `PULL_MODE=NONE`
- バンク電圧は 3.3 V

## 3. Pmod ピン割り当て

| Pmod | 信号 | 種別 | 条件 |
|---|---|---|---|
| 1 / 7 | DX_P / DX_N | LVCMOS33D 双方向 (ELVDS_IOBUF) | 差動対。エミュレート差動の出力と差動入力の両方が使える対 |
| 2 / 8 | CMP_P (D+) / CMP_N (VREF) | LVDS25 入力 (TLVDS_IBUF) | TRUE LVDS 入力対 |
| 3 / 9 | TERM_DP / TERM_DN | LVCMOS33 双方向 | 任意のピン (等長にする) |
| 4 | PULLUP | LVCMOS33 出力 | 任意 |
| 10 | VBUS_DET | LVCMOS33 入力 | 任意 (なくても動く) |
| 5,11 / 6,12 | GND / 3.3 V | | |

Tang Primer 25K の pmod2 (`targets/tangprimer25k/pmod_ports.csv`) に当てはめると次のようになる。

| 信号 | ボール | 実績 |
|---|---|---|
| DX_P / DX_N | G11 / G10 | 2 ポート版の `usb_rx_dp` (LVDS25 入力) として HS 動作済み |
| CMP_P / CMP_N | D11 / D10 | 2 ポート版の `usb_rxdp_p` (LVDS25) |
| TERM_DP / TERM_DN | B11 / B10 | 2 ポート版では D- 比較器 (LVDS25) の対。単端として使う |
| PULLUP | C11 | |
| VBUS_DET | C10 | |

- Arora-V には「隣接下位の差動対を空ける」制約がない (IPUG781 §3.2 の 5 は LittleBee/Arora のみ)。
- DX を G11/G10 にするには、この対が LVCMOS33D 出力 (エミュレート差動) にもなれる必要がある。25K の pmod1 では全 4 行を LVCMOS33D 出力として使った実績があるが (`dvi_out_tpg`、A11/A10 など)、pmod2 の G11/G10 を出力に使った例はまだない。合成で ELVDS_IOBUF が置けるかを先に確かめる。
- 960 MHz の FCLK (IDES16 / OSER16) が pmod2 のバンクの HCLK に届くかも、合成で確認する。2 ポート版 (`easycdr_trace` USB=1) は BANK6/7 の HCLK を 480 MHz 4 相で使っていた。
- GW1N (Nano 9K) と GW2A (Primer 20K) 向けの RTL はない。この PHY は IDES16 / OSER16 を 960 MHz で回す Arora-V 前提で、移植には FCLK と SerDes 比の作り直しが必要。

制約の例 (25K pmod2、未合成):

```
IO_LOC  "usb_dx"      G11,G10;
IO_PORT "usb_dx"      IO_TYPE=LVCMOS33D PULL_MODE=NONE DIFF_RESISTOR=OFF DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "usb_cmp_dp"  D11,D10;
IO_PORT "usb_cmp_dp"  IO_TYPE=LVDS25 PULL_MODE=NONE DIFF_RESISTOR=OFF BANK_VCCIO=3.3;
IO_LOC  "usb_term_dp" B11;
IO_PORT "usb_term_dp" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "usb_term_dn" B10;
IO_PORT "usb_term_dn" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "usb_pullup"  C11;
IO_PORT "usb_pullup"  IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=8 BANK_VCCIO=3.3;
IO_LOC  "vbus_det"    C10;
IO_PORT "vbus_det"    IO_TYPE=LVCMOS33 PULL_MODE=DOWN BANK_VCCIO=3.3;
```

## 4. RTL

`usb_phy_gowin_sl #(.CMP1(1))` を使う。接続例は `eda/slogic16u3_usb2/src/slogic16u3/top.v` の `USB_CMP1`。

- `usb_term_dp_o` / `usb_term_dn_o` (Low か Z) と `usb_term_dp_i` / `usb_term_dn_i` (パッドの読み戻し) を、トップの同じ inout ポートにつなぐ。
- `usb_rxdn_p_i` / `usb_rxdn_n_i` は定数でよい。CMP1 では D- の IBUF と IDES16 を generate で外している。
- クロックは SLogic と同じ構成: PLL VCO 960 → 960 MHz (IDES16/OSER16 FCLK、CLKDIV /8 = pclk 120 MHz) と 480 MHz (CLKDIV /8 = clk60)。
- SLogic で M2/M1 (D- 比較器) を入力として宣言したままにしているのは、基板上で D- につながっていて、未使用ピンの既定プルアップを避けるためだけ。Pmod 基板には D- 比較器自体がないので不要。

## 5. レイアウト指針 (2 ポート版 §5 との差分)

- 1 ポート幅に収める。コネクタ → ESD → 90 Ω 差動 → D+/D- の分岐点 → Rs / Rt / 比較器 / R1 をヘッダ直近に置く。
- Single では送受信が同じ dx 対を通る。ヘッダから FPGA までの未整合区間 (25K で約 30〜40 mm) のスタブは送信と受信の両方に効く。IPUG781 も Single は「伝送距離が短い場合向け」としている。分岐点から各抵抗までのスタブは 3 mm 以内にする。
- dx 対は等長、term の 2 本も等長にする (IPUG781 §3.2 の 4)。
- 比較器の N 側 (VREF) は、P 側 (D+) と対にして引く。

## 6. 実機確認 (SLogic16U3、2026-10-12)

SLogic16U3 の USB-C は Single LVDS 配線になっている。D+ = H3 (比較器) / K3 (dx) / P2 (term)、D- = M2 (比較器) / K2 (dx) / P1 (term)。
D- 比較器を使わない設定でビルドすれば、そのまま 7 本版の試験になる (`eda/slogic16u3_usb2`、`make HS=1 CMP1=1`、README の「7 ピン版」)。

| 項目 | 結果 |
|---|---|
| タイミング | os_pclk 154.1 MHz (要求 120)、clk60 67.5 MHz (60)。9 本版は 123.9 / 62.1 |
| 列挙 | Linux xhci で 480M (bcdUSB 2.10) |
| バルクループバック (`usb_echo.py`) | 8〜3584 B × 1000 回、2048 B × 10000 回すべて一致 (11〜15 MB/s) |
| 受信エラー | 長時間試験の通算 18 回。9 本版と同程度で、再送で回復 |
| SRAM 再ロード | 10/10 で HS 列挙とループバックに成功 |
| ホストからのポートリセット | 10/10 で HS に再列挙 (Hs → HsRevert → ChirpK の経路) |
| 9 本版 (CMP1=0) の回帰確認 | HS 列挙、2048 B × 1000 回一致 |

未確認の項目:

- FS 専用ホストやハブへの接続 (チャープなしで FS にとどまる経路)。
- サスペンドとレジューム (J の 3 ms 継続で Suspended、K で復帰)。
- Pmod 経由 (長いスタブ) での HS 品質。SLogic は FPGA 直近実装なので、この点は試験になっていない。
- 25K での IDES16 / OSER16 @ 960 MHz と ELVDS_IOBUF の配置。

## 7. リスク

| リスク | 影響 | 対策 |
|---|---|---|
| Pmod のスタブで HS 波形が劣化する (送受信とも 1 対) | HS 受信エラー、列挙失敗 | OsCdr (4 倍オーバーサンプル) で位相は追従する。PHY のトランジションヒストグラム (`o_hist`) でアイを確認する。だめなら FS で使う |
| D+ だけのスケルチ | パケット中にスケルチが閉じる | 窓 12 UI で、スタッフィングの最長 7 UI に対して余裕がある。SLogic で受信エラー増なし |
| チャープ中の SE0 抑止 | FS ホストで誤って HS に入る | 理屈の上では起きない (SE0 では dx が交互に変わらない)。FS 専用ハブで要確認 |
| term ピンの LVCMOS 閾値 | FS 信号の端で SE0 を誤検出 | SE0 は 50 ns の多数決 (9 本版と同じ窓)。FS の立ち上がり 4〜20 ns に対して十分 |
| SE0 送信は term ピンだけで作る | FS の EOP の立ち下がりが遅い | 9 本版と同じ方式で、SLogic の FS 列挙では問題なし |

## 8. ブリングアップ手順 (25K)

1. 9 本版の確認は不要。最初から `CMP1=1` で合成し、ELVDS_IOBUF / IDES16 / OSER16 が pmod2 に配置できるかを確かめる。
2. FS: `HS_CAPABLE=0` で列挙とバルクループバック。term ピン入力による SE0 判定の確認になる。
3. HS: `HS_CAPABLE=1`。チャープを経て 480M になるか、SOF の受信、バルクループバックの順に確認する。
4. 状態は SLogic と同じ JTAG ER1 方式か UART で出す。`o_mon_line` (term ピン入力) と `o_cmp_dbg` (D+ 比較器) を観測点にする。
