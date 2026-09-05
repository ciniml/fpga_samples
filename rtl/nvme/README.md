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
| `nvme_controller.veryl` | `NvmeController`: レジスタ + SQ/CQ キューエンジン + PRP データエンジン |
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
  SQ Head 付きで CQ へ書き戻し。割り込み 1 本 (CQ head ドアベルで解除)
- Create/Delete I/O SQ/CQ をローカル処理 (I/O キューは QID 1 の 1 組。
  SQ が残った状態の CQ 削除はエラー)、それ以外は `NvmeCore` へ転送
- PRP1/PRP2 のデータ転送 (ページ 4KiB 固定、PRP1 はページ内オフセット可)

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

注意点:
- SPDK は Identify CNS 03h (NS Identification Descriptor list) が
  エラーを返すとネームスペースを inactive 扱いにするため、コアは
  CNS 03h (EUI-64 + CSI デスクリプタ) を実装しています。
- SPDK のビルドは `./configure --without-nvme-cuse` +
  `make DPDKBUILD_FLAGS="-Dmax_numa_nodes=1"` (libnuma なしの場合)。
  libaio がない場合 spdk_nvme_identify/perf は
  `make -C app/spdk_nvme_identify BLOCKDEV_MODULES_PRIVATE_LIBS=` で
  個別にビルドできます。
