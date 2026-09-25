# EasyCDR BERT (Tang Primer 25K)

ExtEasyCDR モジュール + USB-C ケーブルの 1Gbps リンク用ビット誤り率テスタ。
`rtl/bert` のコアを EasyCDR IP (生データ 16bit) と OSER8 に接続し、
ブラウザ (`host/bert.html`, Web Serial/WebUSB) から制御・表示する。

| 項目 | 内容 |
|---|---|
| TX | PrbsGen 8bit @125MHz → 非同期 FIFO → OSER8 (専用 PLL 500MHz, BANK1) → G7/G8 (pmod0 L1) |
| RX | G11/G10 (pmod2 L0) → **自前 CDR** (`oscdr_phy_gw5a.v`: TLVDS_IBUF → OSIDES32 (DELAY 0/21 **静的**、DYN_DLY_EN=FALSE 必須、DHCE ゲート) → `rtl/oscdr` OsCdr → ギアボックス) → PrbsChk。`USE_EASYCDR_IP=1 make -B synthesis` で純正 IP 版 (どちらも RX bit-reverse OFF) |
| アイスキャン | EXT_CTRL0 (0x30): bit0 = RX 位相凍結, bit1 = TX PLL PSDIR, bit2 = PSPULSE (125ps/パルス)。`host/eyescan.py` またはブラウザの Eye scan |
| ホスト | UART C3/B3 115200 → BertHost。ブラウザ UI は 1 秒毎に SNAP → 24 バイト読出し |
| 観測ピン | B2 = PRBS ロック、C2 = 誤りパルス (~8ms 引き伸ばし)、E1 = RX 活性 |

## 2 ボード構成 (Tang Nano 9K 送信源、別水晶)

`TARGET=tangnano9k_pmod` は PRBS7 を 999Mbps (27MHz 水晶 → rPLL 499.5MHz) で pmod0 L1 (26/25) に
送る TX 専用ビットストリーム (S2 で 1 ビット誤り注入、S1 でリセット)。モジュールを Nano9K pmod0 と
25K pmod2 に挿して USB-C で結ぶと、25K の自前 CDR が −1000 ppm のプレシオクロナス受信を行う
(約 4 スリップ / 1000 UI)。25K 側の TX (pmod0) は使わない。

## 使い方

```sh
cd rtl/bert && veryl build                 # 生成 .sv を合成が参照
cd eda/easycdr_bert
DISPLAY= QT_QPA_PLATFORM=offscreen make synthesis GW_SH=~/gowin/1.9.12/IDE/bin/gw_sh
make run [OPENFPGA_LOADER_DEVICE_OVERRIDE="--busdev-num <bus:dev>"]
```

### レート変種 (純正 IP 版のみ、`build/tangprimer25k_ip_<rate>/`)

GW5A-25 の GPIO 受信経路 (IDES 上限 1600Mbps、DS1103 Table 3-31) がどこまで持つかを BER で測る変種。
`make USE_EASYCDR_IP=1 RATE=<rate>`。RX 4 相 PLL と TX PLL (OSER8 FCLK) を同じ MDIV/ODIV で組み、
IP の `DELAY_1` (UI/4 のタップ数、12.5ps/段) と SDC を project.tcl のテーブルから生成する。

| RATE | 線速 | FCLK / pclk | PLL (50MHz 入力) | DELAY_1 |
|---|---|---|---|---|
| (既定) | 1.0 Gbps | 500 / 125 MHz | VCO 1000 (MDIV 20), ODIV 2 | 21 |
| `1200M` | 1.2 Gbps | 600 / 150 | VCO 1200 (MDIV 24), ODIV 2 | 18 |
| `1400M` | 1.4 Gbps | 700 / 175 | VCO 1400 (MDIV 28), ODIV 2 | 15 |
| `1487M5` | 1.4875 Gbps (1080p60 の 1.485 に +0.17%) | 743.75 / 185.9 | VCO 743.75 (MDIV 14 + 7/8), ODIV 1 | 14 |
| `1600M` | 1.6 Gbps (IDES の仕様上限、DP RBR 1.62 の −1%) | 800 / 200 | VCO 800 (MDIV 16), ODIV 1 | 13 |

- 4 相の 90° は PLLA の PE_FINE (VCO 周期 / 8) で ODIV 2 なら 4 ステップ、ODIV 1 なら 2 ステップ (ラッパで自動計算)
- **実機 BER (2026-09-26、25K 自己ループ pmod0→pmod2、USB-C ケーブル、`host/ber_run.py --dwell 30 --prbs 4`)**:

  | RATE | PRBS31 30 s | PRBS7 10 s | 備考 |
  |---|---|---|---|
  | 1G (IP) | 3.0e10 bit、誤り 0、アンロック 0 | — | 自前 CDR 版も誤り 0 |
  | 1200M | BER 1.5e-8 (誤り 526、アンロック 25) | 誤り 0 | 10 s ×2 でも 1.2e-8 / 9.4e-9 と再現 |
  | 1400M | BER 1.0e-2、アンロック 1.4e7 | BER 1.7e-2 | 実質リンク不成立 |
  | 1487M5 | BER 4.6e-2、ロックせず | — | |
  | 1600M | ロックせず (bit 計数ほぼ 0) | — | |

  → この経路 (GPIO + EasyCDR IP、DELAY_1 = UI/4 固定) は 1.2 Gbps が限界、1.4 Gbps 以上は使えない。
  1080p60 (1.485 Gbps) を GPIO で受けるにはこの構成では届かない (DELAY_1 の追い込みや TX 側ドライブ設定は未検討)。
- 合成結果 (2026-09-25): 1200M / 1400M / 1487M5 はタイミング違反なし (pclk Fmax 193MHz)。1600M は pclk 200MHz に
  対し IP 内ギアボックス −0.16ns、64bit 誤り計数器 −0.08ns が残る (BER 測定には支障ない程度だが要注意)。
  LED 状態ピンと PRBS の sel マルチプレクサは変種のためにパイプライン化した (bert_core/prbs_gen/prbs_chk の `sel_q`)
- 自前 CDR (`oscdr_phy_gw5a.v`) は 1Gbps 固定タップなので RATE との併用は project.tcl がエラーにする
- アイスキャン (`host/eyescan.py --step-ps`) の 1 ステップは VCO 周期 / 8: 1200M 104ps、1400M 89ps、1487M5 168ps、1600M 156ps
  (ただしアイスキャンは自前 CDR の位相凍結が前提なので IP 版では BER のみ)

Chrome/Edge で `host/bert.html` を開き Connect (Serial)。接続時に `I` で識別、
設定を Apply しカウンタをクリアして計測開始。表示: ロック、ビット数、誤り数、
BER、95% 信頼上限 (誤り 0 のとき 3/N)、アンロック回数、経過時間、累積 BER の
時系列 (誤り発生と非ロック区間をティック表示)。

- **Inject 1 error**: TX 側で 1 ビット反転 → errors が 1 増えれば計数経路が正しい
- ケーブルを抜くとロックが落ちアンロック回数が増える。全ゼロでは偽ロックしない
- TX invert / RX invert / RX bit-reverse でリンク極性・ビット順の実験ができる
- BER 1e-12 を 95% 信頼で言うには 3e12 ビット = 1Gbps で **50 分**

## アイスキャン

```sh
python3 host/eyescan.py --steps 24 --dwell 0.1 [--csv eye.csv]   # serial-bridge 経由
```
RX CDR を凍結し、TX PLLA の出力位相を 125ps ずつ進めながら各点の誤りを数える (終了後に戻す)。
実測: 8 ステップ周期 (= 1 UI) のバスタブ、開口 ≈ 0.5 UI。詳細と制約は `rtl/oscdr/README.md`。

## 次の候補

- CTLE / DRIVE の自動 A/B (要再合成のためビットストリーム変種で)
- 2 ボード構成 (別水晶) での ppm 差耐性測定
- 純正 IP と自前 CDR の BER 比較 (`USE_EASYCDR_IP` 変種)
