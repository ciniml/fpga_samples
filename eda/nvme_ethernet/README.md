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
- ネームスペース: BRAM 32KiB (64 ブロック × 512B)
- LED: [5]=ハートビート [4]=RX [3]=TX [2:1]=コネクション確立 (I/O, admin)
- S2 ボタン: リセット

## ビルドと書き込み

```console
$ make TARGET=tangnano9k_pmod GW_SH=~/gowin/1.9.10.03_edu/IDE/bin/gw_sh synthesis
$ make TARGET=tangnano9k_pmod run      # openFPGALoader で SRAM へ
```

リソース: Logic 80% (6,859/8,640)、BSRAM 89% (23/26)、
Fmax 51.5MHz @ 50MHz 制約 (両ターゲットともタイミングクローズ済み)。

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

同じ RTL は `rtl/nvme/sim` の TAP ブリッジ (`make eth_nvme`) で
シミュレーションでも検証済み (ping / smoke / SPDK identify・perf)。
