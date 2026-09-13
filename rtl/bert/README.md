# BERT コア (Veryl)

高速シリアルリンクのビット誤り率測定コア。パラレル化された送信ワード /
受信ワードを扱うのでファミリ非依存 (SerDes・OSER/IDES・EasyCDR などは
ユーザー側で接続)。`eda/easycdr_bert` が EasyCDR 1Gbps リンク向けの統合例。

```
 BertHost (clk_sys, バイトストリーム) ==toggle handshake==> BertCore (リンク並列クロック)
                                                          ├ PrbsGen  --> o_tx_data[TX_WIDTH]
                                                          ├ PrbsChk  <-- i_rx_data[RX_WIDTH] + valid
                                                          └ BertCounters (64bit bits/errs, unlocks, timer)
```

## モジュール

| モジュール | 内容 |
|---|---|
| `prbs_pkg` | PRBS7/9/15/23/31 (ITU-T O.150, Fibonacci 形 `s[n]=s[n-N]^s[n-T]`)、GenMode (PRBS/固定語/クロック/ゼロ) |
| `PrbsGen` | WIDTH ビット/クロック生成。bit0 が最初に線路へ (OSER D0)。固定 16bit 語はクロック境界をまたいで繰り返し。`i_inject` で次ワードの 1 ビット反転、`i_invert` |
| `PrbsChk` | 自己同期で 31bit 履歴を取り込み → `LOCK_WORDS` 連続無誤りでロック → ロック中は自走比較で**誤りを 1 回ずつ正確に計数**。1 ワードで `UNLOCK_BITS` 以上の誤りでロック解除 (そのワードは計数、パイプライン中の最大 2 ワードは非計数)。全ゼロ履歴は LFSR 不動点なので**ロック禁止** (無信号で偽ロックしない)。反転/ビット逆順の入力補正。3 段パイプライン (diff / popcount / FSM) |
| `BertCounters` | 64bit ビット数・誤り数、32bit アンロック回数。`i_snap` で全カウンタを同時にスナップショット (ホストは一貫した組を読める) |
| `BertCore` | 上記 + レジスタファイル (下表) + 経過時間カウンタ + RX 活性ウォッチドッグ |
| `BertHost` | バイトストリーム ⇄ レジスタ。`W a d`→`k`、`R a`→1B、`B a n`→nB、`I`→`"BERT"+ver` |

## レジスタマップ (BertCore)

| ADDR | 名前 | 内容 |
|---|---|---|
| 0x00 | CTRL | b0 TX_EN, b1 RX_EN, b2 CLEAR*, b3 SNAP*, b4 INJECT*, b5 RX_INVERT, b6 RX_BITREV, b7 TX_INVERT (*自己クリア) |
| 0x01 | TX_MODE | 0 PRBS / 1 固定語 / 2 クロック / 3 ゼロ |
| 0x02 / 0x03 | TX_SEL / RX_SEL | 0 PRBS7, 1 PRBS9, 2 PRBS15, 3 PRBS23, 4 PRBS31 |
| 0x04 / 0x05 | FIXED_L/H | 固定語 |
| 0x08 | STATUS | b0 locked, b1 RX 活性 (2^16 clk 以内に valid), b2 i_link_ok |
| 0x30 / 0x31 | EXT_CTRL0/1 | デバイス固有制御 (easycdr_bert: b0 CDR 凍結, b1 PLL PSDIR, b2 PSPULSE) |
| 0x32 | EXT_STATUS | デバイス固有状態 (easycdr_bert: b0 CDR lock, b2:1 位相, b7:4 スリップ数) |
| 0x10–0x17 | SNAP_BITS | 64bit LSB first |
| 0x18–0x1F | SNAP_ERRS | 64bit |
| 0x20–0x23 | SNAP_UNLOCKS | 32bit |
| 0x24–0x27 | SNAP_TIMER | CLEAR からのリンククロック数 / 256 (32bit、125MHz で 2.4 時間) |

## テスト

`veryl test` (Verilator): 8bit TX → 直列化 → 任意ビット位相で 16bit 化 (valid 50%、
ときに連続) → RX。ロック、無誤り、INJECT 5 回=5、線路 3bit 誤り=3、全 PRBS、
不一致パターンで非ロック、リンク断でアンロック 1 回・全ゼロ非ロック・復帰、
TX zero/clock で非ロック、反転、ビット逆順、位相 0/3/7/11。

## リソース (GW5A-25, 8bit TX / 16bit RX, `eda/easycdr_bert` 全体)

LUT 1008 / ALU 205 / FF 1019 (EasyCDR IP・UART 込み)。125MHz で setup +1.9ns。

## 制限

- 誤り計数はロック中のみ。BER が ~0.3 を超えるとロックできない (その場合は STATUS.locked=0 とアンロック回数で判断)
- RX ワード幅 > 31 (履歴長) は未対応
