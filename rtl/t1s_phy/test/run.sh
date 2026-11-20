#!/bin/sh
# Run one test of tb_t1s.veryl with Verilator directly (veryl test hides $display).
# usage: test/run.sh <test name, e.g. t1s_plca_3>   (run `veryl build` first)
set -e
cd "$(dirname "$0")/.."
T=${1:-t1s_csma_2}
OUT=${TMPDIR:-/tmp}/t1s_obj_$T
verilator --binary --timing +define+__veryl_test_t1sphy_${T}__ -Wno-fatal -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE \
    -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-PINMISSING -Wno-INITIALDLY -Wno-TIMESCALEMOD -Wno-UNUSEDPARAM \
    -Wno-REALCVT -Wno-UNSIGNED -Wno-MULTIDRIVEN --top-module $T --Mdir $OUT -o sim \
    t1s_pma_tx.sv t1s_pma_rx.sv t1s_pcs_tx.sv t1s_pcs_rx.sv t1s_plca.sv t1s_phy.sv t1s_bringup.sv \
    test/t1s_bus.sv test/t1s_mac_model.sv test/t1s_link_body.sv test/t1s_bringup_body.sv tb_t1s.sv >$OUT.log 2>&1 || { tail -30 $OUT.log; exit 1; }
$OUT/sim
