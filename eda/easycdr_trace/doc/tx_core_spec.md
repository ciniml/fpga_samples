# easycdr_trace_tx — トレース送信コア仕様

`src/common/easycdr_trace_tx.v`(ラッパ)+ `trace_frontend.v`(サンプルクロック側)+ `trace_afifo.v`
+ `trace_link_tx.v`(リンククロック側)+ `trace_cdc.v` + `tx_link_core.v` + `rtl/displayport/src/encoder_8b10b.sv`

任意幅の信号を監視し、変化時にタイムスタンプ付きレコードを生成して、
EasyCDR受信IP(GW5A、10bit+Word Alignment+8B/10B Decoding構成)が
受けられる8b10bシンボル列を出力するファミリ非依存コアです。
デバイス依存部(PLL/OSER10/差動出力バッファ)はユーザー側で接続します。

## 1. インターフェース

| ポート | 方向 | 幅 | 説明 |
|---|---|---|---|
| `sclk` | in | 1 | **サンプルクロック**(監視対象デザインのクロック、または任意のクロック)。タイムスタンプと周期サンプリングの基準。`clk` と同一ネットでも可 |
| `srstn` | in | 1 | サンプル側の追加リセット(負論理、不要なら 1)。`rstn` と AND され `sclk` に同期化される |
| `sig` | in | WIDTH | 監視信号。`SYNC_STAGES=0` なら `sclk` 同期入力(遅延なし)、`2` なら非同期入力(内部2FF同期) |
| `clk` | in | 1 | リンクパラレルクロック = ラインレート/10(1Gbpsなら100MHz) |
| `rstn` | in | 1 | 非同期リセット(負論理)。両ドメインをリセットする。PLLロック後に解除すること |
| `i_*` 制御入力 | in | | すべて `clk` ドメイン。内部で `sclk` へ渡す(準静的値はハンドシェイク、`i_arm` はパルス同期) |
| `o_symbol` | out | 10 | 8b10bシンボル。**bit0が最初に送出**(OSER10のD0に直結) |
| `o_overflow` | out | 1 | レコードFIFO溢れでレコードを破棄したサイクルに1パルス(**`sclk` ドメイン**) |
| `o_armed` / `o_triggered` / `o_done` | out | 1 | TX トリガ状態(`clk` ドメイン、ハンドシェイク経由) |

## 2. パラメータ

| 名前 | 既定 | 制約 | 説明 |
|---|---|---|---|
| `WIDTH` | 16 | 8の倍数、≥8 | 監視信号幅。レコードのdata部=WIDTH/8バイト |
| `TS_BITS` | 24 | 8の倍数 | タイムスタンプ幅。24bit=10ns×2^24≈168msで一周 |
| `FIFO_AW` | 4 | ≥1 | レコードFIFO深さ=2^FIFO_AW |
| `FRAME_LEN` | 16 | ≥2 | コンマ(K28.5)挿入間隔(シンボル数) |
| `DESC_INTERVAL` | 131072 | 0=off | デスクリプタの定期送出間隔(`clk` サイクル) |
| `SYNC_STAGES` | 2 | 0 or ≥2 | `sig` の同期段数。0 = `sclk` 同期入力 |
| `HAS_PERIODIC` / `HAS_TRIGGER` | 1 | 0/1 | 周期サンプリング / TX トリガの論理を生成するか(0 で削除、入力は無視) |
| `FIFO_RAM` | "distributed" | "distributed" / "block" | レコード FIFO のメモリ種別(GW5A は "block") |
| `CFG_HASH` | 0 | 32 bit | 信号マップのハッシュ(`host/tracemap.py`)。デスクリプタ v2 の 4〜7 バイト目で配る |
| `TICK_LOG2` | 16 | 4〜24 | ティックレコード `[K28.7][ts]` の間隔 = 2^TICK_LOG2 sclk (27MHz で 2.4ms)。`i_tick_dis`=1 で停止 |

ポート追加(2026-09-17): `i_map_req`(1 パルス)、`i_map_len[7:0]`、`o_map_addr[7:0]`、`i_map_data[7:0]`(組合せ読出の
バイト ROM、`trace_map_rom` を `host/tracemap.py --rom` で生成)。不要なら `i_map_len=0` にする(送出しない)。

受信側(`trace_rx_decoder` / `trace_capture`)はレコード形式をデスクリプタから実行時に取る
(`MAX_WIDTH`=64 / `MAX_TS_BITS`=32 まで)。ホスト (UI / ctrl_test.py) も '?' の値に従うので、
送信側の `WIDTH` / `TS_BITS` を変えても受信側の再合成は不要。

## 3. リンク層とレコード形式

- ライン符号: ANSI 8b10b(DPエンコーダ流用、RD管理内蔵、Kコード全12種対応)
- フレーミング: `FRAME_LEN`シンボル毎に **K28.5**(コンマ)。EasyCDRの
  ワードアライメント対象(`define K_28_5`)
- アイドル: 送るものがないスロットは **K28.3** 充填
- レコード(バイトはすべてLSBファースト):

```
[K28.1] [ts byte0] ... [ts byte TS_BITS/8-1] [data byte0] ... [data byte WIDTH/8-1]
```

- **K28.2**: FIFO溢れ通知(1イベントにつき1回、次のレコードの前に送出)
- **K28.4**: デスクリプタ `[VER=02][WIDTH][TS_BITS][flags][CFG_HASH LE 4 バイト]` (8 バイト、DESC_INTERVAL 毎と要求時)。
  受信側は VER で長さを判断し、VER 1 (4 バイト) の旧送信機も受ける
- **K28.6**: 信号マップのテキスト `[LEN][LEN バイト]` (`i_map_req` の 1 パルスにつき 1 回、`i_map_len`/`o_map_addr`/`i_map_data`
  の ROM から読む。ROM は `host/tracemap.py --rom` が生成)
- **K28.7**: ティック `[ts バイト]` (データ無し)。有効中、2^TICK_LOG2 sclk ごとに送る (同じサイクルに
  データレコードがあればそちらに吸収)。受信側はこれで「最後の変化の後もトレースが続いていた」時刻を知り、
  波形の終端を最後のティックに置く。トリガの POST 計数には含めない。MODE bit2 `TICK_DIS` で停止
- コンマはレコード途中にも割り込みうる。受信デコーダはK28.5/K28.3を無視し、
  K28.1で再同期、K28.2でオーバーフローをフラグする

レコード長 = 1 + TS_BITS/8 + WIDTH/8 シンボル(16bit/24bit構成で6シンボル)。

## 4. 動作と内部構成

```
 sclk ドメイン (trace_frontend)          |  clk ドメイン (trace_link_tx)
 sig → [同期段] → 変化検出/無視マスク      |  非同期FIFO読出 → K28.1+ts+data シリアライズ
       → タイムスタンプ、周期、トリガFSM    |  → K28.2 (溢れ) / K28.4 デスクリプタ挿入
       → {ts, data} → trace_afifo (書込) --+→ (読出) → tx_link_core (コンマ/充填/8b10b)
 制御 (enable, mask, period, trig, post) ←-- trace_cdc_bus (ハンドシェイク) ←-- i_* 入力
 i_arm ←-- パルス同期。状態 flags + desc シーケンス --→ trace_cdc_bus --→ デスクリプタ
```

1. `sig` を(必要なら)同期 → 連続サンプルを比較(`chg_r`、**1段パイプライン**)
2. 変化があれば(リセット解除後の最初のサンプル、enable 立ち上がり、周期ヒット、トリガ一致も)
   `{ts, sig}` を非同期FIFOへ。FIFO満杯なら破棄し `o_overflow` パルス+K28.2を予約
   (溢れ通知は sclk→clk→sclk のトグルハンドシェイクで、1 エピソードにつき 1 個)
3. リンク側シリアライザがFIFOからレコードを取り出し、K28.1→tsバイト→dataバイトの順に
   1シンボル/サイクルで送出
4. `tx_link_core` がコンマ挿入・充填・8b10bエンコードを行う

タイムスタンプは変化を検出した `sclk` サイクルのカウント(Nano9K デモは 27MHz = 37.037ns)。
`SYNC_STAGES=0` なら実イベントから固定 2 サイクル、`2` なら固定 4 サイクル遅れた値になるが、
イベント間の相対時間は正確。周期サンプリングの `i_period` も `sclk` サイクル単位。

デスクリプタ要求 `i_desc_req` は一旦 `sclk` へ渡して状態が確定した後にシーケンス番号として
flags と同じハンドシェイク語で戻るため、ARM と DESC_REQ を同じフレームで書いても
デスクリプタは新しい状態を示す。

## 5. 帯域・レイテンシ

| 項目 | 値(16bit/24bit、1Gbps) |
|---|---|
| ペイロード帯域 | 800Mbps × 15/16 = 750Mbps(コンマ分を除く) |
| レコード送出時間 | 6シンボル = 60ns |
| 持続可能な最大イベントレート | 約16.7Mイベント/秒(1レコード/60ns) |
| 短時間バースト吸収 | FIFO 16レコード(`FIFO_AW=4`) — 毎サイクル変化する信号は最大16サイクル分 |
| 変化検出→線路出力 | 約5サイクル + OSER10(≈50〜60ns) |

毎サイクル変化する信号(例: 高速カウンタ)は6倍のレートで来るため
FIFOが溢れる。その場合は監視信号を間引くか、周期サンプリング化
(未実装)が必要。

## 6. クロッキング要件

- `clk` = ラインレート/10 を **OSER10のPCLK**、その5倍(ラインレート/2)を
  **FCLK**に供給(CLKDIV DIV_MODE="5"で生成可)
- `sclk` は `clk` と無関係でよい(非同期FIFOとハンドシェイクで分離)。SDC では両クロック間を
  false path / asynchronous group にする。`sclk` が極端に遅い(< 1MHz)場合、制御レジスタの
  連続書込(約 6µs 間隔)より遅れて反映されることがあるが、最終値は必ず届く
- 受信側EasyCDR(≤1Gbps構成)は ±5000ppm(@1Gbps)の周波数差を許容するので、
  送信側の水晶に合わせた近似レートで良い
  - 例: Tang Nano 9K 27MHz → rPLL 27×37/2 = 499.5MHz → **999Mbps**(-1000ppm)
- 送信側は受信側とクロックを共有しない(クロック配線不要)

## 7. デバイス依存部の接続例と注意

```verilog
easycdr_trace_tx #(.WIDTH(16), .TS_BITS(24), .SYNC_STAGES(0)) u_tx(
    .sclk(dut_clk), .srstn(1'b1), .sig(signals),          // 監視対象のクロックで取得
    .clk(pclk), .rstn(rstn), .o_symbol(sym), .o_overflow(),
    .i_enable(1'b1), .i_ignore_mask(0), .i_desc_req(1'b0), .i_periodic_en(1'b0), .i_change_dis(1'b0),
    .i_period(0), .i_arm(1'b0), .i_trig_mask(0), .i_trig_value(0), .i_post(0));
OSER10 u_ser(.Q(ser), .D0(sym[0]), ... .D9(sym[9]), .PCLK(pclk), .FCLK(fclk), .RESET(~rstn));
ELVDS_OBUF u_ob(.I(ser), .O(txp), .OB(txn));   // 3.3Vバンクはエミュレート差動(LVPECL33E等)
```

- **極性**: ツールは `_p` をペアのAサイドに置く。Aサイドが物理的に負側に
  配線されている場合(Tang Nano 9K pmod0など)は **OSER10のD入力で全ビット反転**して
  補正する。8b10bは極性反転に非耐性なので、逆極性ではロックしない
- **GW1N**: OSER出力はOBUFに直結必須(間にロジック不可)。よって反転はD入力側で行う
- **レコード FIFO のメモリ**: `FIFO_RAM` パラメータ。既定 `"distributed"` = SSRAM (RAM16、GW1N で 9 個。小さく配置の自由度が高い)、
  `"block"` = BSRAM (GW5A には分散 RAM が無いので必須、2 個)。読出は同期 (プリフェッチ) なのでどちらにも載る
- **GW1N タイミング**: 変化検出はパイプライン化済み。100MHzで
  タイミングクリーン(パイプラインなしでは16bit比較+FIFO WREで13.4nsとなり違反)

## 8. リソース(実測、Gowin 1.9.12)

| デザイン | LUT | ALU | FF | その他 |
|---|---|---|---|---|
| Tang Nano 9K TX(コア+デモ信号+rPLL+CLKDIV、2026-08 初版) | 168 | 73 | 156 | OSER10×1、rPLL×1、レコードFIFO(40bit×16) |
| Tang Nano 9K 送信側全体(サンプルクロック分離 + 周期/トリガ + Manchester 制御、2026-09-13) | 567 | 246 | 695 | 同上 + 非同期FIFO |
| 同、リセット専用構成 (CTRL_PULSE=1) | 283 | 58 | 241 | |
| Tang Primer 25K ホスト全体(EasyCDR RX+デコーダ+キャプチャ+TX+UART) | 1242 | 108 | 1262 | BSRAM 9(キャプチャ16Ki×9bit)、OSER10×1、PLLA×2 |

GW1NR-9では全体の約4%(Logic 295/8640)。コア単体はデモ信号分を差し引き
おおむね LUT 150 / FF 130 程度。`WIDTH`を増やすとFIFO幅・比較器・
同期段が線形に増える。

## 9. 制限事項

- 周期サンプリング (`i_periodic_en`/`i_period`、`i_change_dis`) と TX 側トリガ
  (`i_arm`/`i_trig_mask`/`i_trig_value`/`i_post`) は 2026-09 に追加。ホスト側トリガと併用可
- 単一チャネル群(1本の`sig`ベクタ、1 つのサンプルクロック)。複数ソースの多重化は未対応
- タイムスタンプの周回(24bitで168ms)はホスト側で補正していない
- 受信側EasyCDRの8b10bデコード構成はラインレート**≤1Gbps専用**
  (1Gbps超はBEYOND_1G/生データ構成となり本コアの8b10bレコードは使えない)

## 10. 受信側の対応モジュール

| モジュール | 役割 |
|---|---|
| EasyCDR IP(10bit+WORD_ALI+DECODE_8B10B、`K_28_5`) | シリアル→{Kフラグ,バイト} |
| `trace_rx_decoder` | K28.1同期、`{ts,data}`レコード復元(トリガ比較用) |
| `trace_capture` | リングバッファ、トリガ/プリトリガ、ホストコマンド(`S`/`T`/`A`/`D`) |
| `host/trace_view.py` | ダンプ取得、レコードデコード、トリガ位置表示、CSV |
