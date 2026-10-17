#!/bin/bash
# Simulate csi_ctrl (UART commands, I2C, auto init) with Verilator.
set -e
cd "$(dirname "$0")"
S=../src/tangprimer25k
O=${OBJ_DIR:-obj_ctrl}
verilator --binary --timing -j 8 --Mdir $O --top-module tb_csi_ctrl \
  -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE -Wno-UNUSEDSIGNAL -Wno-PINMISSING \
  -Wno-INITIALDLY -Wno-TIMESCALEMOD -Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-STMTDLY \
  ../../../rtl/uart/uart_tx.sv ../../../rtl/uart/uart_rx.sv \
  $S/i2c_reg16.sv $S/imx219_init_rom.sv $S/csi_ctrl.sv tb_csi_ctrl.sv
$O/Vtb_csi_ctrl
