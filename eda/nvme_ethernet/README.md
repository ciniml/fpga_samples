# nvme_ethernet — NVMe-oF (NVMe/TCP) ターゲット on Tang Nano 9K + LAN8720

`rtl/nvme` の NVMe-oF スタック (NvmeCore + NvmeTcpTarget + TcpEngine +
EthIpStack) を Tang Nano 9K + LAN8720 (RMII) に載せる実機プロジェクト。
全ロジックが PHY の 50MHz RMII クロックで動作します。

ターゲットは 2 種:

- **`tangnano9k_pmod` (推奨・現行配線)**: Tang Nano 9K Pmod ベース
  ボード + Pmod Ethernet アダプタ。Ethernet Pmod は右端の PORT2 に
  挿す (`eda/ethernet_video` の tangnano9k_pmod と同一配線):
  txclk=32, crs_dv=31, rxd0=57, rxd1=56, txd0=54, txd1=53, txen=55
  (MDIO/MDC 68/69 はジャンパ線用・本デザイン未使用)。
  リセットは button_s2 (ピン 84)
- `tangnano9k`: 旧・直配線 (eda/ethernet_icmp tangnano9k と同一)

- IP: **192.168.37.2** (ARP/ICMP echo 応答)
- NVMe/TCP: port **4420**、NQN `nqn.2026-09.org.fugafuga:nvme:veryl-sim`
- ネームスペース (tangnano9k_pmod): 内蔵 PSRAM ダイ 0 の 4MiB (8192 ブロック
  × 512B)。`PsramDwordCache` (512B ライトバックキャッシュ 1 ライン、BRAM) +
  `GowinPsram` (**54MHz**、27MHz 水晶から rPLL) で、NVMe 側は 50MHz のまま
  (トグル同期器 + 2 クロック BRAM で CDC)。tangnano9k ターゲットは
  従来どおり BRAM 32KiB
- LED: [5]=ハートビート [4]=RX [3]=TX [2:1]=コネクション確立 (I/O, admin)
  [0]=PSRAM 初期化完了
- リセット: 電源投入時のみ

## ビルドと書き込み

```console
$ make TARGET=tangnano9k_pmod GW_SH=~/gowin/1.9.10.03_edu/IDE/bin/gw_sh synthesis
$ make TARGET=tangnano9k_pmod run      # openFPGALoader で SRAM へ
```

リソース (tangnano9k_pmod, PSRAM 版): Logic 84%、BSRAM 35% (9/26)、
Fmax 50.14MHz @ 50MHz (RMII) / 77MHz @ 54MHz (PSRAM) (タイミングクローズ済み)。
書き込みは `openFPGALoader --busdev-num <bus:dev> --board tangnano9k
--write-sram ...` でケーブルを指定 (Primer 20K と同じ FT2232 のため。
`--detect` で GW1NR-9C を確認)。

## ホスト側 (すべてユーザーモード)

PC と LAN8720 を直結 (または同一セグメント) し、PC 側の NIC に
192.168.37.1/24 を付与:

```console
$ ping 192.168.37.2
$ cd rtl/nvme/sim && python3 smoke_host.py 4420 192.168.37.2
$ spdk_nvme_identify --no-huge -s 512 \
    -r 'trtype:TCP adrfam:IPv4 traddr:192.168.37.2 trsvcid:4420 subnqn:nqn.2026-09.org.fugafuga:nvme:veryl-sim'
$ spdk_nvme_perf --no-huge -s 512 -o 4096 -q 4 -w randrw -M 50 -t 10 \
    -r 'trtype:TCP adrfam:IPv4 traddr:192.168.37.2 trsvcid:4420 subnqn:nqn.2026-09.org.fugafuga:nvme:veryl-sim'
```

## 実機結果: PSRAM ネームスペース (2026-09-06)

`smoke_host.py` 全 PASS (連続再実行も含む)、`spdk_nvme_identify` OK
(8192 ブロック)。データ整合性は `rtl/nvme/sim/probe_host.py` (複数パターン
× サイズ × LBA を書いて読み戻す) で全一致 (TOTAL diffs 0)。
`spdk_nvme_perf` (8 秒、-M 50、PSRAM 54MHz):

| 条件 | IOPS | MiB/s | 平均レイテンシ |
|---|---|---|---|
| 4KiB randread QD1 | 330 | 1.29 | 3.03 ms |
| 4KiB randwrite QD1 | 270 | 1.05 | 3.71 ms |
| 4KiB randread QD4 | 469 | 1.83 | 8.54 ms |
| 4KiB randwrite QD4 | 305 | 1.19 | 13.1 ms |
| 4KiB randrw QD4 | 361 | 1.41 | 11.1 ms |
| 512B randread QD4 | 2636 | 1.29 | 1.52 ms |

BRAM 版 (下記、999 IOPS) より遅い。1 ブロック (512B) がキャッシュ 1 ライン
そのものなので、ランダムアクセスは毎回ライン入れ替え (クリーンなら 512B
フェッチ、ダーティなら書き戻し + フェッチ = 4〜8 バースト @ 54MHz) になる。
4KiB アクセスは 8 ブロック = 8 ライン全ミス。**律速はこのライン入れ替え
レイテンシ**なので、高速化にはラインを 4KiB (8 ブロック) に拡大して 4KiB
アクセスを 1 ミスにするのが次の一手。

### 検討して見送った TCP パイプライン化

MSS (1460B) 単位のセグメント化、アプリ TX のストリーム書き込み、PDU 末尾
フラッシュ信号、TX/RX リング拡大 (4KiB/8KiB) を試作したところ、単一
ストリームの数値は伸びた (一時 QD4 1500 IOPS) が、QD>1 と再接続で
不安定化 (タイムアウト回復で QD4 が 20 IOPS まで低下) したため revert。
安定性を優先し、TCP エンジンは検証済みのベースラインに戻してある。
再挑戦するならまず輻輳・再送まわりを sim で詰める必要がある。

### PSRAM 読み出しのタイミング (ブリングアップの罠)

- 81MHz では DQ の読み取りが 1 ビット (bit2) 単発でずれる現象が P&R の
  配置依存で発生 (単体の `psram_test` は通るのに、フルデザインだと共有
  クロックツリーの負荷で余裕がなくなる)。IODELAY (入力 2.5ns 遅延) と
  ラインバッファ BRAM の配置固定 (INS_LOC) で改善したが完全には消えず、
  **PSRAM を 54MHz に下げて読み取り余裕を確保**して解決 (probe 全一致)。
- キャッシュ導入時、コアが `wen/ren` を `i_mem_ready` でゲートして出すと
  ミスを検出できずデッドロック → 要求はゲートせず出し、メモリ側が ready の
  サイクルだけ実行する規約に。

## 実機結果: BRAM ネームスペース (2026-09-06, Tang Nano 9K Pmod + LAN8720, 100BASE-TX 直結)

- `ping 192.168.37.2`: 応答 OK
- `smoke_host.py`: 全チェック PASS (Connect / Property / Identify /
  I/O キューのライト・リード往復 / エラーステータス / Flush)
- `spdk_nvme_identify`: SN `VERYL-NVME-0001`、NSID 1 (64 ブロック) 列挙
- `spdk_nvme_perf` 4KiB randrw 50/50 QD4 10s: **999.8 IOPS / 3.91 MiB/s**
  (平均レイテンシ 4.0ms、シミュレーションの約 13 倍)

その後 Get Log Page (Error / SMART / Firmware Slot) と Get/Set Features
(FID 01h-0Fh のデフォルト値) を追加し、`get_feature(...) failed` /
`get log page failed` の警告は出なくなった (identify が SMART 温度・
FW スロット等まで表示する)。終了時の `CQ transport error -6` は SPDK の
切断処理のログで良性。

同じ RTL は `rtl/nvme/sim` の TAP ブリッジ (`make eth_nvme`) で
シミュレーションでも検証済み (ping / smoke / SPDK identify・perf)。

## ブリングアップで踏んだ罠 (rtl/nvme の設計メモも参照)

- ARP 応答 (42B) のランタフレーム → NIC が無言で破棄 (TAP シムは通す)
- シム用 TAP (192.168.37.1/24) が同一サブネットの経路を奪う → 実機時は down
- 可変インデックス配列要素へのビット部分代入 (`arr[i][7:0] <= x`) が
  合成で化ける → 要素単位の代入に統一
- キャッシュ導入時: コアが `wen/ren` を `i_mem_ready` でゲートして出すと、
  ミスを検出できずデッドロック → 要求はゲートせず出し、メモリ側が ready の
  サイクルだけ実行する規約に (デバッグ UART で `6601 1` を見て判明)
