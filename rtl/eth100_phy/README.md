# eth100_phy — トランスレス直結 100BASE-TX PHY コア (Veryl)

外付け PHY チップを使わず、LVDS 入力 2 個 (しきい値 ±th の比較器) と LVCMOS 出力 2 本だけで
100BASE-TX を送受信するコア。基板と回路は `eda/pmod_100base_tx/README.md`。

```
 MII(ニブル, 5clk 毎) → Eth100Tx: J/K・4B5B・T/R → スクランブラ → MLT-3 → TX_P/TX_N
 比較器 A,B (4 サンプル/クロック) → Eth100Rx: c=A^B → OsCdr → NRZI → デスクランブラ → J/K → 5B4B → ニブル
 Eth100FlpTx / Eth100FlpRx: FLP バースト送受信、Eth100An: 調停 (100TX FD/HD、パラレル検出)
 Eth100Phy: 上記 + しきい値 PWM ×2
```

- クロックは 125 MHz 1 系統 (1 シンボル/クロック)。受信の周波数差は CDR の 0〜2 ビット/クロックで吸収
- `c = A ^ B` は MLT-3 の NRZI 波形そのもの (遷移ごとに A/B の片方だけが反転する)
- OsCdr は `rtl/oscdr` (SV モジュールとして参照、`FRAC=4`: 1 ワード 1 シンボルのため)
- 送出順・多項式の向き・FLP ビット順は送受信で対称なので、ループバック試験では検出できない。
  実機で市販スイッチと確認すること (eda 側 README §5)

テスト: `veryl test` (Verilator、`test/eth100_link_body.sv` + 線路モデル `test/eth100_chan.sv`)。
結果の一覧は eda 側 README §5.1。veryl test は失敗時に `$display` を出さないので、デバッグ時は
Verilator を直接 (`--binary --timing`) 回す。
