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

## 注意

- この実装は **未ビルド・未動作確認** (作成セッションでコマンド実行が使えなかった)。
  `cargo build` と、`/bert` で Connect (Server) → BERT 識別が返ることを確認すること
- 認証なし。`-l 0.0.0.0:...` で公開するなら信頼できるネットワーク内で
- UI を編集したら再ビルドが必要 (埋め込みのため)
