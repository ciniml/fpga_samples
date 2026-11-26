#!/bin/sh
# IspGbScale simulation (Verilator) + bit-exact check (Python).
set -e
cd "$(dirname "$0")"
T=$(pwd)
R=$(cd ..; pwd)
mkdir -p out
(cd "$R" && veryl build > "$T/out/veryl.log" 2>&1) || { cat out/veryl.log; exit 1; }
verilator --binary --timing -j 8 -Wno-fatal -Wno-lint -Wno-style --top-module tb_gb_scale -Mdir out/obj_gb_scale \
    "$R/isp_gamma.sv" "$R/isp_gb_scale.sv" "$T/tb_gb_scale.sv" > out/verilator_gb_scale.log 2>&1 \
    || { tail -30 out/verilator_gb_scale.log; exit 1; }
./out/obj_gb_scale/Vtb_gb_scale | tee out/sim_gb_scale.log | grep -v "^- " | tail -4
grep -q "TB PASS" out/sim_gb_scale.log
python3 -I "$T/gb_scale_ref.py" out/gb_scale.hex
