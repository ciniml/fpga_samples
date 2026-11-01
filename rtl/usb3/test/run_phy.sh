#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Soft USB 3.0 PHY datapath test (tb_usb3_phy.sv) with Verilator; run `veryl build` in rtl/usb3 first.
# Usage: test/run_phy.sh [work dir]   (runs the loopback with rclk faster and slower, several slips)
set -e
cd "$(dirname "$0")/.."
W=${1:-${TMPDIR:-/tmp}/usb3_phy_test}
mkdir -p "$W"
for cfg in "13 1 1000" "0 0 -1000" "27 1 -3000" "5 0 300"; do
    set -- $cfg
    verilator --binary --timing --timescale-override 1ns/1ps -Wno-fatal -Wno-lint -Wno-style --top-module tb_usb3_phy \
        -GSLIP=$1 -GINV=$2 -GRPPM=$3 --Mdir "$W/obj_$1_$2_$3" \
        usb3_phy_pkg.sv usb3_phy_tx.sv usb3_phy_rx.sv usb3_phy_eb.sv usb3_phy_ctl.sv test/tb_usb3_phy.sv >"$W/build_$1_$2_$3.log" 2>&1 \
        || { tail -20 "$W/build_$1_$2_$3.log"; exit 1; }
    "$W/obj_$1_$2_$3/Vtb_usb3_phy" | grep -v '^- '
done
verilator --binary --timing --timescale-override 1ns/1ps -Wno-fatal -Wno-lint -Wno-style --top-module tb_usb3_phy_ctl \
    --Mdir "$W/obj_ctl" usb3_phy_pkg.sv usb3_phy_ctl.sv test/tb_usb3_phy_ctl.sv >"$W/build_ctl.log" 2>&1 \
    || { tail -20 "$W/build_ctl.log"; exit 1; }
"$W/obj_ctl/Vtb_usb3_phy_ctl" | grep -v '^- '
