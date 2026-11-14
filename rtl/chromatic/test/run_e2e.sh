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
# flash cartridge (MBC5 + 2 MiB AMD flash, 256 KiB image): offset size overwrite expect(ok|reject)
make -s -C "$here" simexe MBC=5 ROM_CODE=3 FLASH=1 >/dev/null
exe=$here/obj_sim_mbc5_r3_m0_h0_s0_f/cart_sim
for c in "0x1F0000 4096 no ok" "0x100 70000 yes ok" "0x100 4096 no reject"; do
    set -- $c
    name=flash_$1_$2_$3
    python3 -c "import sys,random; random.seed(sys.argv[2]); open(sys.argv[1],'wb').write(bytes(random.randrange(256) for _ in range(int(sys.argv[2]))))" "$work/$name.img" "$2"
    rm -f "$work/$name.after" "$work/$name.rom"; rm -rf "$work/$name.bk"
    ow=; [ "$3" = yes ] && ow=--overwrite
    if CART_SIM_ROMOUT="$work/$name.rom" CART_SIM_FLASHOUT="$work/$name.after" "$tool" --sim "$exe" flash-write "$work/$name.img" --offset "$1" $ow --backup-dir "$work/$name.bk" > "$work/$name.log" 2>&1; then
        r=ok
    else
        r=reject
    fi
    # expected flash: the 256 KiB image padded with FF, with the written image on top (unless refused)
    python3 - "$work/$name.rom" "$work/$name.img" "$1" "$r" "$work/$name.expected" <<'PY'
import sys
rom = open(sys.argv[1], 'rb').read()
img = open(sys.argv[2], 'rb').read()
off = int(sys.argv[3], 0)
d = bytearray(rom + b'\xff' * (0x200000 - len(rom)))
if sys.argv[4] == 'ok':
    d[off:off + len(img)] = img
open(sys.argv[5], 'wb').write(d)
PY
    python3 -c "import sys; d=open(sys.argv[1],'rb').read(); open(sys.argv[2],'wb').write(d+b'\xff'*(0x200000-len(d)))" "$work/$name.rom" "$work/$name.before"
    bk_ok=no; cmp -s "$work/$name.bk/TESTCART_MBC5-flash-backup.bin" "$work/$name.before" && bk_ok=yes
    if [ "$r" = "$4" ] && cmp -s "$work/$name.after" "$work/$name.expected" && ! grep -q "VIOLATION\|rule violation" "$work/$name.log"; then
        echo "PASS $name ($r, backup $bk_ok, $(grep -o 'written .*' "$work/$name.log" | cut -c1-90)$(grep -o 'error: .*' "$work/$name.log"))"
    else
        echo "FAIL $name (expected $4, got $r), see $work/$name.log"; fail=1
    fi
done
exit $fail
