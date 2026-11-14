# nvme — トランスポート非依存 NVMe コマンド処理コア

PCIe を使わずに NVMe のコマンド実行部分だけを切り出したサンプルです。
トランスポート (PCIe, シリアルブリッジ, テストベンチなど) からは
SQE (Submission Queue Entry) をストリームで受け取り、コマンドを解釈して
バッキングメモリ (BRAM 想定) を読み書きし、コンプリーションを返します。

## 構成

| ファイル | 内容 |
|---|---|
| `nvme_pkg.veryl` | オペコード・ステータスコード定数 (NVMe Base Spec 1.4) |
| `nvme_core.veryl` | `NvmeCore` 本体 (トランスポート非依存のコマンド実行) |
| `nvme_controller.veryl` | `NvmeController`: レジスタ + SQ/CQ キューエンジン + PRP データエンジン (PCIe 型) |
| `nvme_tcp_pkg.veryl` / `nvme_tcp_target.veryl` | `NvmeTcpTarget`: NVMe/TCP (NVMe-oF) ターゲットの RTL 実装 |
| `nvme_pcie_ep.veryl` / `nvme_pcie_top.veryl` | `NvmePcieEp`: Gowin PCIe IP の TLP インタフェースと `NvmeController` の橋渡し、`NvmePcieTop`: 両者をまとめた PCIe NVMe エンドポイント |
| `tb_nvme_*.veryl` / `test/*.sv` | テスト (`veryl test`) |

## インタフェース (すべて valid/ready ハンドシェイク)

- **SQE 入力**: 64 バイトの SQE を DW0 から 16 dword のストリームで投入。
  `i_sq_is_admin` (DW0 と同時にサンプル) で Admin / I/O コマンドを区別する。
  キュー機構 (ドアベル, SQ/CQ リング, Phase Tag, SQ Head) はトランスポート側の責務。
- **コンプリーション**: `{CID, Status Field (CQE DW3[31:17]), CQE DW0}`。
  CQE の組み立てはトランスポート側で行う。
- **データ**: h2c (Write ペイロード) / c2h (Read・Identify ペイロード, `last` 付き) の
  2 本の dword ストリーム。PRP/SGL の解釈はトランスポート側の責務で、
  コアは転送長ぶんのストリームを流すだけ。エラー完了時はデータフェーズなし。
- **バッキングメモリ**: dword アドレスの同期 RAM ポート (書き込みストローブ +
  読み出しレイテンシ 1 サイクル)。容量は `LBA_COUNT` (512 バイトブロック数) で指定。

## 対応コマンド

- Admin: Identify (CNS 00h Namespace / 01h Controller / 02h Active NS List、各 4096 バイト)、
  Set/Get Features (Number of Queues / Volatile Write Cache のみ、実質 no-op)
- NVM: Read (02h) / Write (01h) / Flush (00h, no-op)
- ネームスペースは NSID=1 の 1 個、LBA サイズ 512 バイト固定

エラーは DNR 付き Generic Command Status
(Invalid Opcode / Invalid Field / Invalid Namespace / LBA Out of Range) を返します。
MDTS = 8KiB (Identify で通知) なので PRP ベースのトランスポートでも
PRP リストは不要です (PRP1 + PRP2 で足りる)。

## NvmeController — キュー機構の RTL 化

`NvmeController` は `NvmeCore` に PCIe 型コントローラの機構を被せたラッパです:

- コントローラレジスタ (CAP/VS/INTMS/INTMC/CC/CSTS/AQA/ASQ/ACQ) と
  1000h からのドアベル (DSTRD=0)
- ホストメモリ上の SQ から SQE をフェッチし、CQE を Phase Tag /
  SQ Head 付きで CQ へ書き戻し
- I/O キューは最大 4 組 (QID 1..4、`NUM_IO_QUEUES`)。ペンディングの
  SQ 間はラウンドロビン調停 (admin 優先)。SQ は任意の作成済み CQ に
  完了を返せる。Create/Delete I/O SQ/CQ と Number of Queues feature を
  ローカル処理 (SQ が残った状態の CQ 削除は Invalid Queue Deletion)、
  それ以外は `NvmeCore` へ転送
- MSI-X 相当の割り込みベクタ 8 本 (`o_irq_vec`): Create I/O CQ の IV を
  CQ ごとに保持し、未消費エントリがある間レベルアサート (CQ head
  ドアベルで解除)。admin CQ はベクタ 0。`o_irq` はレガシー 1 本
  (INTMS bit0 でマスク)
- PRP1/PRP2 のデータ転送 (ページ 4KiB 固定、PRP1 はページ内オフセット可)。
  PRP1 にオフセットがある 8KiB 転送は 3 ページにまたがるため PRP2 が
  PRP リストを指す: コマンド開始前にリストの 2 エントリを読む
- Asynchronous Event Request は完了させずに保持する (報告するイベントが
  ないコントローラとしての正しい振る舞い。即エラー完了にすると SPDK の
  終了処理と競合して "cpl does not map to outstanding cmd" になる)
- DMA アドレスはレジスタ出力 (1 ステート前に準備し、dword ごとに進める)

ホストメモリへは 32-bit 単発アクセスの DMA マスタポート
(valid/ready + 読み出しは rvalid) で接続します。テスト
(`test/nvme_controller_test_body.sv`) はホストメモリ・リング・
ドアベル・Phase ポーリングまでホスト側を完全にモデルして、
8KiB の PRP1+PRP2 ラウンドトリップ、CQ の位相反転、削除順エラー、
割り込みの挙動を確認します。

## テスト

```console
$ veryl test
```

テストベンチがトランスポート役 (SQE 投入、c2h ランダムバックプレッシャ、
h2c 供給、完了受信) と RAM モデルを担当し、Identify の内容、Write→Read の
ラウンドトリップ (最終ブロック含む)、各エラーパスを確認します。

## SPDK との接続 (`sim/`)

`sim/nvme_tcp_bridge.cpp` は Verilator 化した `NvmeCore` に NVMe/TCP
(NVMe-oF) ターゲットを被せたブリッジです。すべてユーザー空間で動作し、
カーネルの NVMe ドライバは使いません。トランスポートの責務
(ICReq/ICResp 交渉、Fabrics Connect / Property Get/Set、Keep Alive、
R2T によるライトデータ収集、CQE 組み立て、Identify Controller の
fabrics 固有フィールドのパッチ) をブリッジが担当し、NVMe コマンド本体は
RTL シミュレーションへ SQE + h2c/c2h ストリームとして転送します。

```console
$ cd sim
$ make          # obj_dir/nvme_tcp_bridge をビルド
$ make smoke    # Python 製の最小 NVMe/TCP ホストでスモークテスト
$ make run      # ポート 4420 で待ち受け (SPDK から接続する場合)
```

SPDK からは NVMe/TCP イニシエータで接続します。すべて非 root・
hugepages 不要 (`--no-huge`) で動作します:

```console
$ ./run_spdk.sh identify   # spdk_nvme_identify を実行
$ ./run_spdk.sh perf       # spdk_nvme_perf (4KiB randrw QD4) を実行
```

手動で実行する場合:

```console
$ spdk_nvme_identify --no-huge -s 512 \
    -r 'trtype:TCP adrfam:IPv4 traddr:127.0.0.1 trsvcid:4420 subnqn:nqn.2026-09.org.fugafuga:nvme:veryl-sim'
```

動作確認済み (SPDK 25.x / Verilator 5.022): identify がコントローラ/
ネームスペースを正しく列挙し、perf が 4KiB random R/W 50/50 QD4 で
約 5,000 IOPS (RTL シミュレーション上) を完走します。

## NvmeTcpTarget — NVMe/TCP ターゲットの RTL 化 (Ethernet ボード向け)

`NvmeTcpTarget` は NVMe/TCP ターゲットの PDU 層をすべて RTL にしたもの
です。境界は「コネクションごとの生 TCP バイトストリーム」(8bit
valid/ready × 2 本: admin + I/O キュー。NVMe/TCP はキューごとに 1 TCP
コネクション) で、下位の TCP はシミュレーションではソケットポンプ
(`sim/nvme_tcp_rtl_bridge.cpp`、NVMe ロジックなし)、実機では FPGA の
TCP エンジンが担います。

- ICReq/ICResp (ダイジェスト無効、MAXH2CDATA=128KiB)、Fabrics
  Connect / Property Get/Set、Keep Alive、AER 保留
- 受信は 2 コネクションをバイト単位でインターリーブ処理 (1 バイト/
  サイクル)。SQE は共有 FIFO (64 スロット、BRAM 4KiB) へ
- ライトは R2T フローで、H2CData ペイロードを `NvmeCore` の h2c へ
  直結 — パイプライン化されたコマンドが先行してもデータバッファ不要。
  CAP.MQES=15 (キュー深さ 16) が FIFO のデッドロックフリーを保証
- リード/Identify は c2h から単一の C2HData PDU (LAST 付き) へ直結。
  Identify Controller の fabrics 固有フィールド (CNTLID/KAS/MAXCMD/
  SGLS/SUBNQN/IOCCSZ 等) は dword インデックスでオンザフライパッチ

```console
$ cd sim && make tcp_rtl
$ BRIDGE_BIN=$PWD/obj_tcp/nvme_tcp_rtl_bridge ./run_smoke.sh
$ BRIDGE_BIN=$PWD/obj_tcp/nvme_tcp_rtl_bridge ./run_spdk.sh all
```

SPDK identify/perf が RTL ターゲットに対して完走します (性能は
1 バイト/サイクル処理なりですが、Tang Nano 9K + 100M PHY の回線速度
には十分)。

## Ethernet フルスタック (`eth_ip.veryl` / `tcp_engine.veryl`)

実機 (Tang Nano 9K + LAN8720, RMII) に載せる Ethernet 側の RTL:

- `EthIpStack`: ARP 応答 + ICMP エコー (2KiB フレームバッファ 1 面)
- `TcpEngine`: TCP-lite — port 4420 の passive open × 2 コネクション、
  SYN-ACK で MSS=1460 通知、受信は in-order のみ (2KiB FIFO の空きを
  ウィンドウ広告、ドレイン時にウィンドウ更新 ACK)、送信は 2KiB リング
  兼 Go-back-N 再送バッファ、IP/TCP チェックサムは 2 パス生成
  (RX 側 TCP チェックサム検証は省略 — FCS で保護)
- `EthTxMux`: フレーム境界の TX アービタ

検証は実カーネル相手 (TAP): `sim/eth_nvme_top.sv` (実 MAC + 全スタック
+ NVMe ターゲット) を `make eth_nvme` でビルドし、
`ping` / `smoke_host.py 4420 192.168.37.2` / SPDK identify・perf
(`traddr:192.168.37.2`) がすべて RMII ピンレベルシミュレーションを
通ります。

yosys 概算では NVMe+IP+TCP 合計 ~9k LUT 相当と Tang Nano 9K (8.6k) を
やや超過するため、実機化には TCP エンジンの 32-bit 演算削減などの
最適化パス (または Tang Primer 20K) が必要です。

### vfio-user 接続 (キュー機構まで RTL で検証)

`sim/nvme_vfio_bridge.cpp` は `NvmeController` を vfio-user の PCI
デバイス (クラスコード 010802h) として公開します。NVMe/TCP ブリッジと
違い、ブリッジに NVMe のロジックはありません: BAR0 アクセスは CSR
ポートへ、ドアベルページ (BAR0+1000h) は共有メモリの sparse mmap を
ポーリングして RTL へ、SQE/CQE/PRP は RTL の DMA ポートからクライアント
の DMA マップ済みメモリへ (`VFU_SGL_DIRECT_ACCESS` 必須 — SPDK の
クライアントはキューポーリング中にサーバ発の DMA メッセージへ応答
しない)。SPDK の VFIOUSER イニシエータが本物のリング/ドアベル/PRP で
RTL を叩きます。こちらも全ユーザー空間・hugepages 不要です。

```console
$ make vfio      # VFU_PREFIX は既定で ~/opt/vfu (libvfio-user の install prefix)
$ ./run_spdk_vfio.sh all
```

`spdk_nvme_perf -c 0xF` で 4 コア = 4 I/O キューペアが作られ、
ラウンドロビン調停まで実ホストで検証できます (各コアの IOPS が
均等になります)。

### 依存パッケージ / ビルド手順

```console
$ sudo apt-get install libnuma-dev libaio-dev libjson-c-dev libcmocka-dev \
    meson ninja-build python3-jinja2 python3-yaml python3-tabulate python3-pyelftools
# libvfio-user (Ubuntu パッケージなし)
$ git clone https://github.com/nutanix/libvfio-user && cd libvfio-user
$ meson setup build --prefix=$HOME/opt/vfu -Ddefault_library=static
$ meson compile -C build && meson install -C build
# SPDK
$ git clone --recurse-submodules https://github.com/spdk/spdk && cd spdk
$ ./configure --with-vfio-user --without-nvme-cuse --disable-tests --disable-unit-tests
$ make -j$(nproc)
```

注意点:
- SPDK は Identify CNS 03h (NS Identification Descriptor list) が
  エラーを返すとネームスペースを inactive 扱いにするため、コアは
  CNS 03h (EUI-64 + CSI デスクリプタ) を実装しています。
- SPDK はシャットダウン時に CSTS.SHST (bits 3:2) をポーリングします。
- SPDK のビルドは `./configure --without-nvme-cuse` +
  `make DPDKBUILD_FLAGS="-Dmax_numa_nodes=1"` (libnuma なしの場合)。
  libaio がない場合 spdk_nvme_identify/perf は
  `make -C app/spdk_nvme_identify BLOCKDEV_MODULES_PRIVATE_LIBS=` で
  個別にビルドできます。

## PCIe エンドポイント (`NvmePcieEp` / `NvmePcieTop`)

Tang Mega 138K (GW5AST) の PCI Express ハード IP (Gowin PCI Express
Controller, IPUG1020) のトランザクション層インタフェースに `NvmeController`
を載せたものです。コンフィグ空間は IP 側が処理し、ユーザ側には 256 ビット
(8 dword) のビートで TLP が流れます (dword 0 が `data[255:224]`、
`valid[7]` が dword 0、ヘッダの直後に詰めてペイロード、受け手の `wait` が
Low のサイクルで転送)。

- 受信: BAR0 宛 MWr → CSR 書き込み (ドアベル含む、1 dword/サイクル)、
  BAR0 宛 MRd → CSR 読み出しを CplD で返す (4 dword まで、それ以上は CA、
  他 BAR は UR)、自分の DMA 読み出しへの CplD → 読み出しバッファ。
  到着順に処理するのでレジスタ読み出しが先行する書き込みを追い越さない。
  入口はスキッドバッファで `o_rx_wait` はレジスタ出力
- 送信: コントローラの 32 ビット DMA ポートを TLP 化。書き込みは連続
  アドレスを 1 つの MWr に結合 (最大 128B = 最小 MPS、4KiB 境界は跨がない、
  WR_IDLE サイクル静止・読み出し前・CplD 送出前にフラッシュ)。読み出しは
  要求 dword から 64B ブロック末尾までを 1 回の MRd で先読みし、各 dword は
  1 回だけ消費、書き込みが来たら破棄 (前のコマンドのデータを古いまま返さない)
- MSI: ベクタのレベルが立ち上がったとき、および CQ head ドアベル後も
  残っているときに要求。結合中の CQE 書き込みが IP に渡るまで待つ
  (MSI が CQE を追い越さない)
- ペイロード dword のバイト順は IPUG1020 に記載がないためパラメータ
  `DATA_BSWAP` にしてある。実機で BAR0+08h (VS) が 00010400h でなく
  00040100h に読めたら反転する

### 検証環境

コアの外側 (TLP のやりとりとホスト) を段階的に検証できるようにしています。

| レベル | 内容 | コマンド |
|---|---|---|
| 1. SV テストベンチ | IP の BFM (ランダム wait/ギャップ、MSI ack) + ルートコンプレックス (4GiB 超アドレス含むホストメモリ、MRd/MWr による MMIO)。全送信 TLP をルール検査 | `veryl test` (`nvme_pcie`, `nvme_pcie_bswap`) |
| 2. SPDK (vfio-user, TLP レベル) | `sim/pcie_tl_model.h` (IP + RC モデル) を被せた Verilator モデルを vfio-user サーバとして公開し、SPDK のユーザ空間ドライバで identify / perf / bdevperf verify | `cd sim && make pcie_vfio && ./run_spdk_pcie.sh all` |
| 3. QEMU ゲスト | QEMU の vfio-user-pci で同じサーバをゲストの PCI バスに挿し、Linux カーネルの nvme ドライバ (MSI, block I/O, O_DIRECT の PRP リスト) と SPDK の PCIe ドライバ (vfio-pci) で検証 | `sim/qemu/run_qemu.sh` |
| 4. 実機 | Tang Mega 138K Dock を別ホストの PCIe スロットに挿し、SSH 越しにレベル 3 と同じテスト | `eda/nvme_pcie` (README 参照) |

レベル 2/3 のサーバ (`obj_pcie/nvme_pcie_vfio`) のオプション:
`--tlp-log FILE` (デコード済み TLP を 1 行ずつ、サイクル付き)、
`--tlp-log-data N` (ログに出すペイロード dword 数)、`--fst FILE`
(`make pcie_vfio TRACE=1` でビルドした場合の波形)、`--rx-gap N` /
`--tx-wait N` (% でバックプレッシャを注入)、`--cpl-latency N`、
`--strict` (TLP ルール違反で abort)、`--trap-doorbells`
(ドアベルも MMIO コールバック経由にして順序を厳密化)。
`run_spdk_pcie.sh` は `TLP_LOG=/path` でログを取れます。

TLP ログの例:

```
     27330 EP->RC MRd64 addr=0x2000040d0600 len=16 req=1800 tag=19 be=f/f
     27338 RC->EP CplD cpl=0000 req=1800 tag=19 SC bc=64 la=00 len=16 data=00bb000c 00000000 ...
     27409 EP->RC MWr64 addr=0x2000040d6180 len=4 req=1800 tag=00 be=f/f data=00000000 00000000 00000019 800300bb
     27520 RC->EP MWr32 addr=0xfe001000 len=1 req=0000 tag=00 be=f/0 bar=01 data=0000001b
```

#### QEMU ゲスト (`sim/qemu`)

- QEMU 10.1 以降が必要 (vfio-user クライアント)。10.1.0 には
  `vfio-user-pci` に `x-pci-class-code` プロパティが無く、クラスコードが
  0 で上書きされるバグがある → `sim/qemu/patches/` のパッチを当ててビルド
  (`../configure --prefix=$HOME/opt/qemu --target-list=x86_64-softmmu --enable-virtfs`)。
  既定のパスは `~/opt/qemu/bin/qemu-system-x86_64` (`QEMU=` で変更)
- ゲストはホストと同じ版のカーネル (`KERNEL=`, 既定 `~/opt/guest/vmlinuz`)
  をホストのルートを 9p で読み取り専用マウントして動かす。モジュールは
  ホストの `/lib/modules` をそのまま使い、SPDK などホストのバイナリが
  そのまま動く。Ubuntu の `/boot/vmlinuz-*` は一般ユーザが読めないので
  同じ版の `linux-image-unsigned-<ver>` を archive.ubuntu.com から取って
  `dpkg-deb -x` で取り出す
- `/dev/kvm` に書けなければ TCG で動く (起動 10 秒程度、テスト全体 1 分弱)
- `run_qemu.sh [script]` は既定で `guest_nvme_test.sh` (kernel → SPDK) を
  実行し、ログ (`console.log`, `tlp.log`, `bridge.log`) を `$OUT` に残す。
  `run_qemu.sh shell` で対話シェル
- `guest_nvme_test.sh` は実機ホストでもそのまま動く (IOMMU の有無で
  vfio-pci の no-IOMMU モードを切り替え、22c2:1100 の関数だけを付け替える)
