#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
#
# Load the design into the Tang Primer 25K (exactly one board connected).
#
#   ./program.sh [bitstream.fs]           SRAM (lost at power-off)
#   ./program.sh --flash [bitstream.fs]   flash (the board starts with it)
#
# Default bitstream: dvi_hub75_gamma2.2.fs (colour tables start as gamma
# 2.2, no UART needed).
set -eu
cd "$(dirname "$0")"
mode=--write-sram
if [ "${1:-}" = "--flash" ]; then mode=--write-flash; shift; fi
fs="${1:-dvi_hub75_gamma2.2.fs}"
boards=$(lsusb | grep -c "0403:6010" || true)
if [ "$boards" != 1 ]; then
    echo "[program] expected one Tang Primer 25K (FTDI 0403:6010), found $boards" >&2
    lsusb | grep "0403:6010" >&2 || true
    exit 1
fi
bd=$(lsusb | grep "0403:6010" | awk '{printf "%d:%d", $2, $4}')
echo "[program] $fs -> board $bd ($mode)"
openFPGALoader --board tangprimer25k --busdev-num "$bd" $mode "$fs"
