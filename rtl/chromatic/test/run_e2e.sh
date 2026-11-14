#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# End-to-end: util/chromatic_cart_dump against the Verilator model for several cartridges,
# byte-compared with the model's ROM image (dump) and RAM image (save). Usage: ./run_e2e.sh [work dir]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tool=$here/../../../util/chromatic_cart_dump/target/release/chromatic_cart_dump
work=${1:-$here/e2e_out}
mkdir -p "$work"
(cd "$here/../../../util/chromatic_cart_dump" && cargo build --release -q)
fail=0
# MBC ROM_CODE MBC1M BAD_HDR expect(ok|reject)
for c in "0 0 0 0 ok" "7 5 0 0 ok" "1 4 0 0 ok" "1 5 0 0 ok" "1 6 0 0 ok" "1 5 1 0 ok" "2 3 0 0 ok" "3 6 0 0 ok" "5 7 0 0 ok" "5 2 0 1 reject"; do
    set -- $c
    name=mbc$1_r$2_m$3_h$4_s0
    make -s -C "$here" simexe MBC=$1 ROM_CODE=$2 MBC1M=$3 BAD_HDR=$4 >/dev/null
    exe=$here/obj_sim_$name/cart_sim
    rm -f "$work/$name.gb" "$work/$name.expected"
    if CART_SIM_ROMOUT="$work/$name.expected" "$tool" --sim "$exe" dump -o "$work/$name.gb" > "$work/$name.log" 2>&1; then
        r=ok
    else
        r=reject
    fi
    if [ "$5" = ok ] && [ "$r" = ok ] && cmp -s "$work/$name.gb" "$work/$name.expected"; then
        echo "PASS $name ($(stat -c %s "$work/$name.gb") bytes, $(grep -o '[0-9]* bus writes, .* violations' "$work/$name.log"))"
    elif [ "$5" = reject ] && [ "$r" = reject ] && grep -q "header checksum mismatch" "$work/$name.log"; then
        echo "PASS $name (refused: bad header checksum)"
    else
        echo "FAIL $name (expected $5, got $r), see $work/$name.log"; fail=1
    fi
done
# save: MBC ROM_CODE RAM_CODE expect(ok|reject) [EEP_WORDS]
for c in "7 5 0 ok 128" "7 5 0 ok 256" "1 2 2 ok" "1 4 3 ok" "2 3 0 ok" "3 6 3 ok" "3 5 5 ok" "5 5 4 ok" "5 5 0 reject" "0 0 2 reject"; do
    set -- $c
    eep=${5:-128}
    name=mbc$1_r$2_m0_h0_s$3
    [ "$eep" = 128 ] || name=${name}_e$eep
    make -s -C "$here" simexe MBC=$1 ROM_CODE=$2 RAM_CODE=$3 EEP_WORDS=$eep >/dev/null
    exe=$here/obj_sim_$name/cart_sim
    rm -f "$work/$name.sav" "$work/$name.ram"
    if CART_SIM_RAMOUT="$work/$name.ram" "$tool" --sim "$exe" save -o "$work/$name.sav" > "$work/$name.save.log" 2>&1; then
        r=ok
    else
        r=reject
    fi
    if [ "$4" = ok ] && [ "$r" = ok ] && cmp -s "$work/$name.sav" "$work/$name.ram"; then
        echo "PASS save $name ($(stat -c %s "$work/$name.sav") bytes, $(grep -o '[0-9]* bus writes, [0-9]* RAM reads, [0-9]* violations' "$work/$name.save.log"))"
    elif [ "$4" = reject ] && [ "$r" = reject ] && grep -q "not supported\|declares no cartridge RAM" "$work/$name.save.log" && ! grep -q "VIOLATION\|rule violation\|ENABLED" "$work/$name.save.log"; then
        echo "PASS save $name (refused: $(grep -o 'error: .*' "$work/$name.save.log"))"
    else
        echo "FAIL save $name (expected $4, got $r), see $work/$name.save.log"; fail=1
    fi
done
exit $fail
