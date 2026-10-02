# dvi_hub75 展示キット

HDMI で受けた映像の左上 128x128 を HUB75 パネル (64x64 × 4) に、音声を ΔΣ DAC に出すデモの展示用一式。
PC (Ubuntu、Xorg) の HDMI 出力を Tang Primer 25K につなぎ、動画を 128x128 で画面の左上に全画面再生する。

| ファイル | 内容 |
|---|---|
| `dvi_hub75_gamma2.2.fs` | 展示用ビットストリーム。色テーブルが最初からガンマ 2.2 (UART 不要) |
| `dvi_hub75.fs` | 同じデザインで色テーブルが恒等 (ガンマ 1.0) |
| `program.sh` | FPGA への書き込み (`--flash` でフラッシュへ) |
| `prepare.sh` | 動画を 128x128 / 30 fps / 48 kHz ステレオに変換して `videos/` に置く |
| `play.sh` | `videos/` の動画をループ再生 (`--pattern` でテストパターン + 1 kHz) |
| `status.sh` | UART で受信状態・音声状態を見る、ガンマを変える (`./status.sh gamma 1.8`) |
| `install-autostart.sh` | ログイン時に `play.sh` を自動起動し、画面のブランク / ロック / サスペンドを止める |
| `loopctl.py` | UART のホストツール (`eda/dvi_loopback/host`) |

## 接続

- PC の HDMI → Pmod DVI (pmod0)。PC 側は Xorg セッションで使う (このマシンは Wayland 無効化済み)
- HUB75 ベースボード → pmod1 + pmod2、パネル 4 枚 (上段 2 枚の右に下段 2 枚がチェーン)
- DDC / HPD → 40 ピンヘッダ 15 (SCL) / 16 (SDA) / 17 (HPD)、レベル変換経由
- 音声 → 40 ピンヘッダ 19 (L) / 20 (R) → RC LPF (1kΩ / 3.3nF / 10kΩ / 330pF / 1µF) → アンプのライン入力
- Tang Primer 25K の USB → PC (書き込み・UART)

## 手順

```sh
cd ~/exhibit/dvi_hub75
./program.sh                       # 書き込み (電源を切ると消える)。基板だけで起動させるなら ./program.sh --flash
./prepare.sh --fit ~/Videos/demo.mp4   # 動画を変換 (--fit: 全体を縮小して上下に黒帯。省略すると中央の正方形を切り出し。速い動きは --fps 60000/1001)
./play.sh                          # デスクトップの端末から実行。止めるときは再生ウィンドウで q
```

`play.sh` がやること:

1. `xrandr` の EDID 名 ("FPGA HDMI RX") で FPGA 側の出力を探し、1280x720@60 にする
2. PulseAudio の HDMI ポートのうち名前が "FPGA..." のものを既定の出力にする (音量 100%)
3. 画面のブランクを止め (`xset`)、その出力に全画面で 1280x720 の黒地の左上に 128x128 の動画を置いて再生する
   (全画面なので GNOME のトップバーやドックは載らない。RGB で渡すので色の間引きもない)

動画が 1 本ならそのままループ、複数なら連結して切れ目なくループする。

## デモ映像

`demos/gen_demos.py` (開発機で実行、numpy / Pillow) が 128x128・59.94 fps・30 秒の生成パターンを作る。
暗い背景にゆっくり動く柔らかい光で、どれも継ぎ目なくループする。

| 名前 | 内容 |
|---|---|
| `aurora` | 夜空にゆらめくオーロラ (緑 / 青緑 / 紫)、瞬く星、山の影 |
| `fireflies` | 暗い森のホタル。暖色と黄緑の光がゆっくり漂い明滅する |
| `lava` | ラバーランプ。オレンジ〜ピンクの塊がくっついたり離れたりする |
| `ripples` | 夜の水面に落ちる雨粒の波紋 |
| `sunset` | 夕日と海面のきらめき |
| `title` | "HDMI ↓ HUB75" / "Tang Primer 25K" / "128 × 128 LED" / "FPGA DVI / HDMI receiver" を順にフェード表示 |

```sh
python3 demos/gen_demos.py --out /tmp/demos --preview              # 開発機: .mkv (FFV1) と見本の PNG
./prepare.sh --fps 60000/1001 --gamma 1.6 --out demos /tmp/demos/*.mkv   # 展示機: demos/*.mp4 に変換 (パネル上でガンマ 1.6)
./play.sh demos/*.mp4                                              # 順に再生 (ループ)
```

## 調整・確認

- テストパターン: `./play.sh --pattern` (文字と色の位置でパネルの向き・チェーン順を確認、1 kHz で音を確認)
- 受信・音声の状態: `sudo modprobe ftdi_sio` のあと `./status.sh`
  (このマシンは ftdi_sio がブラックリストに入っているので、UART を使うときだけ読み込む。
   `L1`、`N 921600`、`fs 48000 Hz`、`running 1`、誤り 0 なら正常)
- ガンマ: `./status.sh gamma 1.8` / `./status.sh gamma identity` (書き込み直すと 2.2 に戻る)
- PC が FPGA を認識しない: 基板の S1 を押すと HPD を下げて EDID を読み直させる。HDMI ケーブルの抜き差しでもよい

## 自動起動 (任意)

```sh
./install-autostart.sh              # ~/.config/autostart に登録、ブランク / ロック / サスペンドを無効化
./install-autostart.sh --remove     # 元に戻す
```

ログイン画面で止まらないようにするには自動ログインが要る (要 sudo、`/etc/gdm3/custom.conf` の
`[daemon]` に `AutomaticLoginEnable=true` / `AutomaticLogin=kenta`)。基板を `--flash` で書いておけば、
電源投入だけで FPGA 側は動く。

## 注意

- このマシンの openFPGALoader は v0.12.1 (開発機は v0.13.1)。書き込めないときは開発機から `--flash` で書いておく
- `prepare.sh` は libx264 を使う (Ubuntu の ffmpeg で可)
- 生成元: `eda/dvi_hub75` (`make GAMMA=2.2` / `make`)
