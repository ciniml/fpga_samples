#!/bin/sh
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# ModRetro Chromatic: FPGA flash backup / restore / pre-deploy checks over the on-board GWU2X bridge.
#   chromatic_flash.sh detect
#   chromatic_flash.sh backup [file]
#   chromatic_flash.sh check <bitstream.fs>      (CONFIRM_FLASH=yes, a backup must exist)
#   chromatic_flash.sh restore <backup.bin>      (CONFIRM_FLASH=yes)
# The console must be powered on (power switch ON) and connected over USB-C.
set -eu

OFL=${OPENFPGALOADER:-openFPGALoader}
CABLE="--cable gwu2x"
BACKUP_DIR=${CHROMATIC_BACKUP_DIR:-$HOME/chromatic-backups}
# Bitstream area of the configuration flash. The official image is about 0xE0000 bytes.
DUMP_SIZE=${CHROMATIC_FLASH_DUMP_SIZE:-1048576}
PART=GW5A-EV25UG256

die() { echo "chromatic_flash: $*" >&2; exit 1; }

detect() {
    out=$($OFL $CABLE --detect 2>&1) || true
    echo "$out"
    echo "$out" | grep -q "GW5A-25" || die "GW5A-25 not found: console on (power switch ON), USB-C connected, udev rules?"
}

confirm() {
    [ "${CONFIRM_FLASH:-}" = "yes" ] || die "this writes the console's FPGA flash. Re-run with CONFIRM_FLASH=yes (restore: see eda/targets/chromatic/README.md)"
}

have_backup() {
    ls "$BACKUP_DIR"/chromatic_flash_*.bin >/dev/null 2>&1
}

cmd=${1:-}
case "$cmd" in
detect)
    detect
    ;;
backup)
    detect
    mkdir -p "$BACKUP_DIR"
    f=${2:-$BACKUP_DIR/chromatic_flash_$(date +%Y%m%d_%H%M%S).bin}
    [ -e "$f" ] && die "$f exists"
    $OFL $CABLE --dump-flash --file-size "$DUMP_SIZE" "$f"
    [ "$(stat -c %s "$f")" -eq "$DUMP_SIZE" ] || die "dump size mismatch"
    if [ -z "$(tr -d '\377' < "$f" | head -c 1)" ]; then
        rm -f "$f"; die "dump is all 0xFF, discarded"
    fi
    # read twice: the backup is only trusted when both reads agree
    t=$f.verify
    $OFL $CABLE --dump-flash --file-size "$DUMP_SIZE" "$t"
    cmp -s "$f" "$t" || { rm -f "$t"; die "two reads differ, keep $f only for inspection"; }
    rm -f "$t"
    echo "backup: $f"
    sha256sum "$f"
    ;;
check)
    fs=${2:-}
    [ -f "$fs" ] || die "bitstream $fs not found"
    head -20 "$fs" | grep -q "^//Part Number: *$PART" || die "$fs is not a $PART bitstream"
    confirm
    have_backup || die "no backup in $BACKUP_DIR: run 'make chromatic-backup' first"
    detect
    echo "flash write allowed: $fs (backups in $BACKUP_DIR)"
    ;;
restore)
    f=${2:-}
    [ -f "$f" ] || die "give the backup file: make chromatic-restore BACKUP=<file> CONFIRM_FLASH=yes"
    [ "$(stat -c %s "$f")" -eq "$DUMP_SIZE" ] || die "$f is not a $DUMP_SIZE-byte backup"
    confirm
    detect
    $OFL $CABLE --write-flash --file-type bin --verify --reset "$f"
    ;;
*)
    sed -n '2,10p' "$0"
    exit 1
    ;;
esac
