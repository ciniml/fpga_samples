# ブラウザ完結ホストツール (Web Serial / WebUSB) 設計メモ

`host/web/index.html` — 単一HTML、外部ライブラリなし。Chrome/Edge で
`file://` のまま開くか、任意の静的ホスティング (https) に置けば動作する。

## 1. 前提と方針

- FPGA側 (`trace_capture`) のホストIFは既に **バイトストリーム** (`h_rx/h_tx`
  valid/ready) に抽象化済みで、コマンドは `S` / `T mask val` / `A post` / `D`、
  応答は `K` とダンプ (2byte/entry)。**ブラウザ側もトランスポート層だけ差し替え、
  プロトコル/デコードは共通**にする (trace_view.py と同一ロジックの移植)
- 対応ブラウザ API:

| 経路 | ブラウザAPI | FPGA側 | 備考 |
|---|---|---|---|
| UART (BL616 / USB-UART) | **Web Serial** (`navigator.serial`) | 現状のまま (uart_rx/tx) | 追加実装ゼロ。Linux は `dialout` 権限のみ。Chrome/Edge/Opera 専用 (Firefox/Safari 非対応) |
| USB ベンダクラス (`rtl/usb` UsbDevice, VID 0x1209, EP1 bulk) | **WebUSB** (`navigator.usb`) | EP1 ループバックを `h_rx/h_tx` に接続 | Linux は udev ルール、Windows は WinUSB (WebUSB は Microsoft OS 2.0 descriptor で自動バインド可能) |
| USB CDC-ACM | Web Serial | CDC ディスクリプタ + 制御要求追加が必要 | OS 標準ドライバで tty になる利点。ただし **WebUSB はカーネルドライバが掴んだ IF を claim できない**ので、CDC にするなら Web Serial 一本 |

推奨: **UART=Web Serial、USB=WebUSB (ベンダクラスのまま)**。現行 USB コアを
最小改造で使え、ホスト OS ドライバ非依存 (Windows でも WinUSB 自動割当) で
「ブラウザ完結」を満たす。

## 2. ブラウザ側構成

```
+-------------------+   +---------------------+   +----------------------+
| SerialTransport   |   | UsbTransport        |   | (将来) MockTransport |
| readable/writable |   | transferIn/Out EP1  |   | 波形ファイル再生      |
+---------+---------+   +----------+----------+   +----------+-----------+
          +--------------------+---+----------------------------+
                               v
                    ByteQueue (read(n, progress, abort))
                               v
             capture(): T/A or S -> wait 'K' -> D -> read 2^ADDR_BITS*2 bytes
                               v
             decode(): K28.1 同期 / K28.2 溢れ / TS 周回補正 (絶対 ns)
                               v
        +----------------------+-----------------------+
        v                      v                       v
   Canvas 波形 (bit毎、       レコード表 (トリガ行     CSV / VCD エクスポート
   ホイール zoom / drag pan)   ハイライト、クリックで   (VCD は GTKWave 等で
                               波形センタリング)         そのまま開ける)
```

- 大容量対策: 表は最大 5000 行 (トリガ中心)、波形は可視範囲の先頭を二分探索して
  描画。16Ki エントリ (最大 ~2.7k レコード) なら余裕。ADDR_BITS=20 でも成立
- タイムスタンプ周回 (TS_BITS=24 → 168ms) はホスト側で **差分累積**して絶対時刻化
  (Python 版は未対応だった)。1周回以上イベントが無い区間は検出不能な点は変わらず
- `data` は BigInt で扱うので WIDTH=32/64 でも精度落ちなし

## 3. FPGA 側で必要な作業 (USB 経路)

1. `UsbDevice` の EP1 バルク FIFO をループバックから `h_rx (OUT側) / h_tx (IN側)` に分離
   - OUT: 受信バイト → `h_rx_valid/data` (50MHz `clk_sys` へ CDC。60MHz UTMI とは非同期)
   - IN: `h_tx_valid/data/ready` → IN FIFO。**ダンプ終端はショートパケット**
     (32KiB = 512B×64 でちょうど割り切れる → 最後に ZLP が必要。`trace_capture` の
     ダンプ完了フラグで ZLP 送出するか、ホストが要求サイズ分読めた時点で打ち切る。
     `index.html` は後者 = 期待バイト数で停止するので ZLP 無しでも動作する)
2. HS なら 480Mbps → 32KiB ダンプは <1ms。UART 115200 の 2.8 秒に対し実用上瞬時
3. Linux udev: `SUBSYSTEM=="usb", ATTR{idVendor}=="1209", ATTR{idProduct}=="0001", MODE="0666"`
4. Windows で自動的に WinUSB を当てるなら BOS + MS OS 2.0 descriptor を ROM に追加
   (無ければ Zadig で手動)

## 4. 制限 / 注意

- Web Serial / WebUSB とも **ユーザー操作 (クリック) 起点の `requestPort/requestDevice`** が必要。
  自動再接続は `navigator.serial.getPorts()` で許可済みポートを拾えば可能 (未実装)
- `file://` は Chrome では secure context 扱いなので動作するが、Firefox は両 API 非対応
- claude.ai の Artifact 等 iframe サンドボックス内では Permissions-Policy により
  `serial`/`usb` が使えないことがある → ローカルファイルか自前ホスティングで運用
- ダウンロード (CSV/VCD) は Blob URL 経由。ブラウザのダウンロード設定に従う
- 115200bps では 16Ki エントリのダンプに ~2.8 秒 (進捗バー表示)。921600/2M 変種は未実機確認

## 5. 次の候補

- [ ] USB コアの EP1 ↔ `h_rx/h_tx` 接続 + 実機で WebUSB 経路確認
- [ ] TX 側から**周期デスクリプタ** (K28.4 + WIDTH/TS_BITS/tick/version、~1ms 毎) を送出し、
      25K のデコーダでラッチ → ホストコマンド `?` で返して UI の手入力をなくす
      (TX は送信専用なので問い合わせ不可。先頭のみだとロック前に流れるため周期送出にする。
      `cap_valid` は K28.1/K28.2 以外の K コードを除外済みなのでバッファは汚れない)
- [x] 逆方向チャネル (ホスト → TX 側) のコア: `rtl/manchester` (Veryl) に実装・検証済み。
      ManchesterTx/Rx (バイト同期+パリティ、エッジ駆動受信、±10 % クロック偏差で PASS) +
      CtrlFrameRx (固定 4 バイト `[A5][ADDR][DATA][CRC8]`) + TraceCtrlRegs (CTRL/IGNORE_MASK)。
      受信側合計 113〜124 LUT / 77〜88 FF (GW1NR-9 実測)。物理層: 25K L1 (G7/G8) →
      ケーブルクロス → Nano9K L0 (pmod0 1/7, IOB ペア要確認)。全レーン AC 結合 (τ≈1ms)
      なので DC 不可、1〜5Mbps Manchester で常時トグル。
- [x] 25K 側: ManchesterTx (BIT_CYCLES=25 @50MHz = 2Mbps) を G7/G8 へ、`X len bytes` /
      `?` コマンドを trace_capture に追加。旧 8b10b デモTXと pll_tx_500m は撤去
- [x] Nano9K 側: TLVDS_IBUF (pin 28/27 = IOB11, CTRL_INVERT=1) → ManchesterRx (BIT_CYCLES=50
      @99.9MHz) → CtrlFrameRx → TraceCtrlRegs、`easycdr_trace_tx` に enable/ignore_mask/desc_req 追加
- [x] 周期デスクリプタ (K28.4, ~1.3ms) + 25K 側ラッチ + `?` 応答。デスクリプタのペイロードは
      `o_desc_busy` でキャプチャバッファから除外 (これを忘れるとバッファがデスクリプタで汚染される)
- [x] E2E 検証: eda/easycdr_trace/test/e2e_ctrl_tb.sv (Verilator) 全周回 12 チェック PASS
- [x] ブラウザUI: 接続時に `?` 自動取得でパラメータ自動設定、TX control 欄 (enable/mask/reset)
- [x] 実機確認 (2ボード + USB-C): ?応答、mask/enable/reset、CTRL_INVERT=1 正解、`Z` アボート追加 (2026-09-13)。25K の TX は pmod2 L1 (D10/D11) に移動
- [x] アーム中の解除: `Z` アボートコマンド (ST_WAIT でも受理) を追加。UI の Abort が送信
- [ ] 許可済みポートの自動再接続、連続キャプチャ (繰り返し S→D) モード
- [ ] 信号名ラベル (JSON で bit→名前) とバス表示 (複数 bit をまとめて 16進表示)
- [ ] 波形の Mock トランスポート (CSV 再読込) でオフライン閲覧
