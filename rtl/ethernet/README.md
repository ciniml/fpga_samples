# 100M Ethernet MAC

## 概要

100M Ethernet PHYを使って、PL上でEthernet通信を行うためのコアです。

このデザインは株式会社フィックスターズ Tech Blog の記事(https://proc-cpuinfo.fixstars.com/2020/05/alveo-u50-10g-ethernet/) で説明されている10G MAC IPを参考に作られています。
オリジナルのリポジトリは https://github.com/fixstars/xg_mac です。

## 動作環境

以下のボードで動作確認を行っています。

* EBAZ4205
* Tang Nano 9K + LAN8720
* Tang Primer 20K (RTL8211)

## ライセンス

ほとんどオリジナルの10G Ethrenet MACのコードは残っていませんが、一部プロジェクト復元周りのスクリプトやFIFOのRTLを使っています。
10G Ethernet MAC IP自体は3条項BSDライセンスで公開されていますので、本プロジェクトのデザインも3条項BSDライセンスとします。

詳しくは本ディレクトリに含まれている `LICENSE` ファイルを確認してください。