# HDMI出力有効化版デザイン

## 概要

Tang Nano 9Kに搭載されているHDMIコネクタからGOWIN DVI TX IPを使ってHDMI出力を行えるように変更したデザイン。

HDMIコネクタで使用している信号はComProc CPU Boardのボード上で使用している信号と一部共用されているので、ボードの機能が一部使用不可となっている。影響をうけるボードの機能は次の通り。

* 8x8マトリクスLED
* 7+1セグメントLED
* キャラクタ液晶

特にキャラクタ液晶はHDMIコネクタにケーブルを挿した状態だと物理的に干渉するので、ボードから取り外す必要がある。

## 合成の準備

### Tang Nano 9K向け

いくつかのGOWIN EDA付属のIPを使用している。現状GOWINのIPはスクリプトからIPのHDLファイルを再生成することができないので、IP定義ファイルからの再生成をGUIを操作して手動で行う必要がある。

`src/comprocboard_9k_ip` 以下にある3つのIPを復元する。

* dvi_tx
* gowin_clkdiv
* gowin_rpll

IPの復元はGOWIN EDAのGUI上の `Tools -> IP Core Generator` メニューから IP Core Generatorを開き、画面上部のボタンを押して各IPのディレクトリ下にある *.ipc ファイルを選択する。
その後、値を変更せずにOKを押すと、対象のIPのHDLファイルが生成される。

![IPCファイルの読み込み](./regenerate_ip.drawio.svg)

### Tang Primer 25K向け

Tang Primer 25K向けのデザインを試すには、Tang Primer 25K本体以外にSipeedのPmod DVIモジュールが必要となる。Pmod DVIモジュールは DE0 互換コネクタを手前に持ってきた状態 (Pmodコネクタを奥側にした状態) で一番右側のコネクタ (F5, G5のピンが含まれるコネクタ) に接続する。

Tang Nano 9K向けと同様に、`src/ip` 以下にある、 `gowin_pll` と `gowin_pll_27` を復元する。

その後、以下のコマンドでビットストリームを生成する。

```
$ make TARGET=tangprimer25k 
```
