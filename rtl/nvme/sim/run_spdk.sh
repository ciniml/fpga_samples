#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
#
# Run SPDK's userspace NVMe/TCP initiator against the Verilator bridge.
# Everything is user mode: --no-huge, no root, no kernel NVMe driver.
#
#   ./run_spdk.sh [identify|perf|all] [port]
#
# SPDK_DIR points at an SPDK build tree (default: ~/repos/spdk).
set -u
MODE=${1:-all}
PORT=${2:-4420}
SPDK_DIR=${SPDK_DIR:-$HOME/repos/spdk}
DIR=$(cd "$(dirname "$0")" && pwd)

SUBNQN="nqn.2026-09.org.fugafuga:nvme:veryl-sim"
TRID="trtype:TCP adrfam:IPv4 traddr:127.0.0.1 trsvcid:$PORT subnqn:$SUBNQN"

IDENTIFY="$SPDK_DIR/build/bin/spdk_nvme_identify"
PERF="$SPDK_DIR/build/bin/spdk_nvme_perf"

for bin in "$IDENTIFY" "$PERF"; do
    [ -x "$bin" ] || { echo "not found: $bin (build SPDK first)"; exit 1; }
done

"$DIR"/obj_dir/nvme_tcp_bridge "$PORT" &
BRIDGE_PID=$!
trap 'kill $BRIDGE_PID 2>/dev/null' EXIT

for i in $(seq 50); do
    if (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then exec 3>&-; break; fi
    sleep 0.1
done

RC=0
if [ "$MODE" = identify ] || [ "$MODE" = all ]; then
    echo "=== spdk_nvme_identify ==="
    "$IDENTIFY" --no-huge -s 512 -r "$TRID" || RC=1
fi
if [ "$MODE" = perf ] || [ "$MODE" = all ]; then
    echo "=== spdk_nvme_perf (4KiB random R/W 50/50, QD4, 5s) ==="
    "$PERF" --no-huge -s 512 -r "$TRID" -o 4096 -q 4 -w randrw -M 50 -t 5 || RC=1
fi
exit $RC
