# serial-bridge — FPGA ホスト UI 用シリアルブリッジ Web サーバ (Rust)

シリアルポート (BL616 USB-UART など) を 1 本所有し、ブラウザ UI を配信して
プロトコル非依存の HTTP API でバイト列を中継する。UI (素の HTML/JS) は
`eda/easycdr_bert/host/bert.html` と `eda/easycdr_trace/host/web/index.html`
をビルド時に埋め込む (`include_str!`) ので、実行ファイル 1 個で完結する。

Web Serial / WebUSB と違いブラウザを選ばず (Firefox 可)、別マシンからも使える。
UI 側は `HttpTransport` (fetch) がトランスポート層を差し替えるだけで、
BERT / トレースのプロトコル処理はブラウザ側にそのまま残る。

```
ブラウザ (bert.html / index.html)  --HTTP JSON-->  serial-bridge  --UART-->  FPGA
   HttpTransport.write/read            /api/xfer     (serialport crate)
```

## ビルド / 起動

```sh
cd util/serial_bridge
cargo build --release
./target/release/serial-bridge -p /dev/ttyUSB2 -b 115200 -l 127.0.0.1:8080
# ブラウザで http://127.0.0.1:8080/  → /bert または /trace
```

`-p` を省略した場合は UI のポート選択 (`/api/ports` の一覧) から開く。
UI は `location.protocol` が http のときだけ「Connect (Server)」を表示し、
`file://` で開いた場合は従来どおり Web Serial / WebUSB ボタンだけになる。

## API

| メソッド | パス | 内容 |
|---|---|---|
| GET | `/`, `/bert`, `/trace` | 索引 / 埋め込み UI |
| GET | `/api/ports` | `[{name, kind}]` |
| GET | `/api/state` | `{open, port, baud}` |
| POST | `/api/open` | `{port, baud}` |
| POST | `/api/close` | |
| POST | `/api/flush` | 受信バッファ破棄。**進行中の xfer をキャンセル**する |
| POST | `/api/xfer` | `{write:[u8], read:n, timeout_ms}` → `{data:[u8], timeout:bool}` |

`xfer` は書き込み後、`read` バイト揃うか `timeout_ms` 経過まで読む。ポートは
Mutex で直列化され、読み待ちは blocking プールで行う (tokio ワーカを塞がない)。
トレースのトリガ待ち (`'K'` 応答) のような長い待ちは UI 側が `timeout_ms=600000`
で発行し、Abort 時に `/api/flush` で世代カウンタを進めて中断する。

## ロジックアナライザ (SLogic16U3、`/la`)

`eda/slogic16u3_la` のデザインを載せた SLogic16U3 (USB 1209:0001、レジスタ 0 = 0x01004C41) の
取り込みサーバも兼ねる (`src/la.rs`、USB は nusb)。ブラウザは 400 MB/s のストリームを受けず、
サーバがメモリ上に持つキャプチャから「画面に見える分」だけを問い合わせる。

```
SLogic16U3 ─USB3─ serial-bridge (la.rs)                     ─HTTP─ /la (la.html + wave.js)
                   1 MiB × 8 転送、ストリーム解析、グループごとのリング、
                   ソフトトリガ、256 サンプルごとの OR/AND とそのピラミッド
```

- 取り込み: 4 CH 800 MS/s 3 秒 (2.4 G サンプル、1.2 GB) を 400.6 MB/s でオーバーフローなし。
  要求から表示可能まで 4.0 秒 (確保と要約で約 1 秒)。表示問い合わせは 1 画面 0.5〜3.4 ms
- トリガ: 1 グループのチャネル条件 (CH ごとに X / 0 / 1 / R / F / E、全部が同じサンプルで成立)。
  プリトリガ分がたまってから有効になり、ポスト分で止まる。プリ分はリングで保持するので待ち時間に上限は無い
  (その間も 400 MB/s を受け続ける)。x = 0 がトリガ
- 位置: x = s × scale − offset。内部クロックは ns (両グループのサンプル 0 は同じ 1.25 ns 位置)、
  外部クロックはサンプル番号 (同じクロック入力・同じエッジの 2 グループは揃う)

| メソッド | パス | 内容 |
|---|---|---|
| GET | `/la`, `/wave.js` | LA UI、波形ビュー (トレースビューアと共通) |
| GET | `/api/la/device` | `{ok, id, status}` / `{ok:false, error}` |
| POST | `/api/la/capture` | `{a:{ch,clk,rate,skew,other_clk,test,thalf}, b:{..}, length_s, ext_samples, threshold_v, trigger:"16 文字", pre, mem_mb}` |
| POST | `/api/la/stop` | 停止 (トリガ待ちなら最新の分を残す) |
| GET | `/api/la/status` | `{state, msg, bytes, mbps, elapsed, samples, trig}` |
| GET | `/api/la/meta` | グループごとの ch / クロック / scale / offset / サンプル数 / フラグ、トリガ |
| GET | `/api/la/view?g&x0&x1&n` | バイナリ: ピクセルごとの (OR, AND)、1 ピクセル 2 サンプル未満ならサンプルそのもの |
| GET | `/api/la/find?g&x&dir&cond` | x の後 / 前で条件 (8 文字) に合う最初のサンプルの x |
| GET | `/api/la/vcd?x0&x1` | 範囲の VCD (CH0..15) |

`--ui-root <リポジトリ>` を付けると UI (bert.html / index.html / la.html / wave.js) をディスクから読む (編集時に再ビルド不要)。

## 注意

- 認証なし。`-l 0.0.0.0:...` で公開するなら信頼できるネットワーク内で
- UI を編集したら再ビルドが必要 (埋め込みのため。`--ui-root` なら不要)
- LA の取り込みはメモリを使う (既定上限 `mem_mb` 8192)。キャプチャは次の取り込みまで保持
