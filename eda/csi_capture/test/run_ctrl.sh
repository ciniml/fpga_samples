#!/bin/bash
# Simulate csi_ctrl (UART commands, I2C, auto init) with Verilator,
# for the init ROMs (SENSOR 0: IMX219, 1: OV5640 / Pcam 5C, 2: OV5640 720p30 lock).
set -e
cd "$(dirname "$0")"
S=../src/tangprimer25k
O=${OBJ_DIR:-obj_ctrl}
for sensor in 0 1 2; do
  verilator --binary --timing -j 8 --Mdir $O$sensor --top-module tb_csi_ctrl -GSENSOR=$sensor \
    -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE -Wno-UNUSEDSIGNAL -Wno-PINMISSING \
    -Wno-INITIALDLY -Wno-TIMESCALEMOD -Wno-BLKSEQ -Wno-MULTIDRIVEN -Wno-STMTDLY \
    ../../../rtl/uart/uart_tx.sv ../../../rtl/uart/uart_rx.sv \
    $S/i2c_reg16.sv $S/imx219_init_rom.sv $S/ov5640_init_rom.sv $S/ov5640_720p30_init_rom.sv $S/csi_ctrl.sv tb_csi_ctrl.sv
  $O$sensor/Vtb_csi_ctrl
done
