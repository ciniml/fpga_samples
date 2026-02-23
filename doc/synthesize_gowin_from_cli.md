# GOWIN FPGA向けデザインのコマンドラインからの合成

## 概要

FPGAの開発において、初期のデザインの設計にはGUIを用いることもありますが、繰り返しの試行錯誤にはCLIを用いたバッチによる合成処理がよく用いられます。
中国GOWIN社が自社のFPGA向け開発環境として提供しているGOWIN EDAでもGUIによる合成処理に加えて、CLIからの合成処理に対応しています。

本稿では、GOWIN EDAを使ったデザインの合成手順について説明します。

## GOWIN EDAのCLI **gw_sh**

GOWIN EDAにはGUI環境 `gw_ide` のほかに、CLIのバッチ処理ツール `gw_sh` が付属しています。
`gw_sh` の使い方は、 Gowin Software User Guide (SUG100) [^1] の第8章 Tcl Commands に記載されています。

`gw_sh` は Tclで記述したスクリプトを実行し、合成処理を行います。
以下のコマンドで `gw_sh` の引数に指定したスクリプトを実行します。

```shell
gw_sh <tcl script>
```

[^1]: Gowin Software User Guide (SUG100-3.7E) https://www.gowinsemi.com/en/support/database/14/

## gw_sh の基本的なコマンド

### 合成のためのスクリプトの基本構成

```tcl
set_device <device part>

set_option -output_base_name <project name>
set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -print_all_synthesis_warning 1
set_option -top_module top

# pin options
#set_option -use_sspi_as_gpio 1
#set_option -use_done_as_gpio 1
#set_option -use_ready_as_gpio 1

add_file -type verilog module1.sv
add_file -type verilog module2.sv

add_file -type cst pins.cst
add_file -type sdc timing.sdc

run all
```

### set_device

対象のデバイスを設定します。

```tcl
set_device <part number>
```

```tcl
set_device GW2AR-LV18QN88C8/I7
```

## Pmodの形状

<img src="./pmod_specification.drawio.svg" width="50%" align="right" alt="Pmodの形状および配置"/>

Pmod規格に準拠したモジュールは、2.54mmピッチの1x6 もしくは 2x6 のピンヘッダ・ピンソケットを用いて接続します。
基板の端面にライトアングルのコネクタが配置されます。
モジュール側基板の最大幅が規定されているため、隣り合うPmodモジュールが物理的に干渉しないようになっています。
また、Pmod基板を接続する親基板に複数コネクタを並べる場合は、コネクタの間隔が規定されています。
これにより、1つのPmodコネクタだけでは信号線が足りない場合、複数のPmodコネクタを使用するモジュールを作成可能です。

<br clear="right"/>
<div style="page-break-after: always;"></div>

## Pmodの信号

1x6のPmodコネクタには、信号線4本、電源1本、GND1本が接続されています。
2x6のPmodコネクタは、1x6のPmodコネクタ2つ分と等価です。つまり、信号線8本、電源2本、GND2本が接続されます。

2x6のコネクタの場合、電源は2本接続されますが、それぞれ個別の電源を供給することは想定されておらず、大抵のボードでは両方とも3.3Vが供給されます。

信号線は基本的には自由に使用できますが、よく使われるインターフェースに関しては、標準のピン配置が規定されていますので、準拠しておくとモジュール間の互換性が高まります。
`[]` で囲まれているピンはオプションであり、使用しない場合はGPIOとして使えます。

| ピン番号 | 信号名 | 向き   | Type1 (GPIO) | Type2A (SPI) | Type3A (UART) | Type5A (H-Bridge) | Type6A (I2C) | Type7 (I2S)   |
| -------: | :----- | :----- | :----------- | :----------- | :------------ | :---------------- | :----------- | :------------ |
|        1 | IO1    | In/Out | -            | CS(Out)      | CTS(In)       | DIR1(Out)         | [INT(In)]    | LRCLK(Out)    |
|        2 | IO2    | In/Out | [PWM(Out)]   | MOSI(Out)    | TXD(Out)      | EN1(Out)          | [RESET(In)]  | DAC Data(Out) |
|        3 | IO3    | In/Out | -            | MISO(In)     | RXD(In)       | S1A(In)           | SCL(In/Out)  | ADC Data(In)  |
|        4 | IO4    | In/Out | -            | SCK(Out)     | RTS(Out)      | S1B(In)           | SDA(In/Out)  | BCLK(Out)     |
|        5 | GND    |        |              |              |               |                   |              |               |
|        6 | VCC    |        |              |              |               |                   |              |               |
|        7 | IO5    | In/Out | -            | [INT(In)]    | [INT(In)]     | DIR2(Out)         |              |               |
|        8 | IO6    | In/Out | [PWM(Out)]   | [RESET(Out)] | [RESET(Out)]  | EN2(Out)          |              |               |
|        9 | IO7    | In/Out | -            | [CS2(Out)]   | -             | S2A(In)           |              | [MCLK(Out)]   |
|       10 | IO8    | In/Out | -            | [CS3(Out)]   | -             | S2B(In)           |              |               |
|       11 | GND    |        |              |              |               |                   |              |               |
|       12 | VCC    |        |              |              |               |                   |              |               |

## Pmodの部品

Pmodモジュールを作るにあたって必要なのは、2.54mmピッチの2x6ライトアングル・ピンヘッダです。
また、Pmodモジュールを接続できる親ボードには、2.54mmピッチの2x6ライトアングル・ピンソケットが必要です。
いずれも秋月電子通商などで入手できます。

| 値                                     | 購入元                                                    | 備考          |
| :------------------------------------- | --------------------------------------------------------- | ------------- |
| 2x6 2.54mm ライトアングル ピンヘッダ   | [秋月電子 C-00148](https://akizukidenshi.com/catalog/g/gC-00148/) | 2x6で分割する |
| 2x6 2.54mm ライトアングル ピンソケット | [秋月電子 C-16795](https://akizukidenshi.com/catalog/g/gC-16795/) |               |

<div style="page-break-after: always;"></div>

## 実装例

筆者が作成した各種Pmod互換モジュールの設計データ (KiCadプロジェクト、ガーバーデータ) をGitHubで公開しています。
[https://github.com/ciniml/TangFPGAExtensions/](https://github.com/ciniml/TangFPGAExtensions/)

### TangNano9K用 Pmodベース基板

<img src="./TangNano9K_board_3d.png" width="33%"  align="right"/>

SipeedのFPGAボード **Tang Nano 9K** にPmodモジュールを接続できるようにするためのベースボードです。
基板上面に3つのPmodコネクタを搭載しています。電源電圧・IO電圧は 3.3V です。

<br clear="right"/>

### TangPrimer20K用 Pmod拡張基板

<img src="./TangPrimer20K_board_3d.png" width="33%" align="right"/>

SipeedのFPGAボード **Tang Primer 20K** + Dock基板の基板上部には、Pmodと電気的に互換性のあるピン配置のコネクタが4つ実装されていますが、
コネクタの向きや位置、間隔などの機械的な互換性がありません。

TangPrimer20K用 Pmod拡張基板は、前述のTang Primer 20KのDock上のコネクタをPmod互換の配置に変換するための基板です。
この拡張基板により、Pmod互換のモジュールを接続可能となります。電源電圧・IO電圧は3.3Vです。

<br clear="right"/>

### 8x8 LEDマトリクス Pmod基板

<img src="./Pmod_MatrixLED_board_3d.png" width="16%" align="right"/>

秋月電子通商で購入可能なOptosupplyの8x8マトリクスLED OSL641501-AXA のPmod互換モジュールです。Pmodコネクタを2ポート使用します。

FPGA等から8x8マトリクスLEDの表示をダイナミック点灯により制御できます。

<br clear="right"/>

<div style="page-break-after: always;"></div>

### HUB75接続 Pmod基板

HUB75とよばれるLEDマトリクス・モジュールを接続するための Pmod互換モジュールです。 Pmodコネクタを2ポート使用します。

### デバッグ用 Pmod 中継基板

<img src="./Pmod_Debug_board_3d.png" width="16%" align="right"/>

Pmod互換モジュールと親基板の間に接続し、Pmodの信号をロジック・アナライザ等で観測しやすくするための基板です。

<br clear="right"/>

#

* Pmodモジュール作成のすすめ
* 初版: 2023年11月12日
* 初出: 技術書典15
* 発行: Kenta IDA
* 著者: Kenta IDA
* 連絡先: fuga@fugafuga.org
* Twitter: @ciniml
* GitHub: https://github.com/ciniml/