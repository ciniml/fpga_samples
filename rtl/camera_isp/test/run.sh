#!/bin/sh
# Camera pipeline simulation (Verilator) + bit-exact check (Python).
set -e
cd "$(dirname "$0")"
T=$(pwd)
R=$(cd ..; pwd)
mkdir -p out
(cd "$R" && veryl build > "$T/out/veryl.log" 2>&1) || { cat out/veryl.log; exit 1; }
verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style --top-module tb_isp -Mdir out/obj_dir \
    "$R/isp_video_timing.sv" "$R/isp_raw10_unpack.sv" "$R/isp_line_ring.sv" "$R/isp_gamma.sv" \
    "$R/isp_display.sv" "$R/isp_genlock.sv" "$T/tb_isp.sv" > out/verilator.log 2>&1 \
    || { tail -30 out/verilator.log; exit 1; }
./out/obj_dir/Vtb_isp | tee out/sim.log | grep -v "^- " | tail -8
grep -q "tb_isp: done" out/sim.log
python3 -I "$T/isp_ref.py" out 64 32 40 0x1A0 0x100 0x180 3
