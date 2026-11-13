#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# End-to-end: util/chromatic_cart_dump against the Verilator model for several cartridges,
# byte-compared with the model's ROM image. Usage: ./run_e2e.sh [work dir]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../../../util/chromatic_cart_dump/target/release/chromatic_cart_dump
work=${1:-$here/e2e_out}
mkdir -p "$work"
(cd "$here/../../../util/chromatic_cart_dump" && cargo build --release -q)
fail=0
# MBC ROM_CODE MBC1M BAD_HDR expect(ok|reject)
for c in "0 0 0 0 ok" "1 4 0 0 ok" "1 5 0 0 ok" "1 6 0 0 ok" "1 5 1 0 ok" "2 3 0 0 ok" "3 6 0 0 ok" "5 7 0 0 ok" "5 2 0 1 reject"; do
    set -- $c
    name=mbc$1_r$2_m$3_h$4
    make -s -C "$here" simexe MBC=$1 ROM_CODE=$2 MBC1M=$3 BAD_HDR=$4 >/dev/null
    exe=$here/obj_sim_$name/cart_sim
    rm -f "$work/$name.gb" "$work/$name.expected"
    if CART_SIM_ROMOUT="$work/$name.expected" "$tool" --sim "$exe" dump -o "$work/$name.gb" > "$work/$name.log" 2>&1; then
        r=ok
    else
        r=reject
    fi
    if [ "$5" = ok ] && [ "$r" = ok ] && cmp -s "$work/$name.gb" "$work/$name.expected"; then
        echo "PASS $name ($(stat -c %s "$work/$name.gb") bytes, $(grep -o '[0-9]* bus writes, [0-9]* violations' "$work/$name.log"))"
    elif [ "$5" = reject ] && [ "$r" = reject ] && grep -q "header checksum mismatch" "$work/$name.log"; then
        echo "PASS $name (refused: bad header checksum)"
    else
        echo "FAIL $name (expected $5, got $r), see $work/$name.log"; fail=1
    fi
done
exit $fail
