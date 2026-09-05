#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
#
# Run SPDK's userspace VFIOUSER initiator against the vfio-user bridge.
# The RTL queue engine handles doorbells/rings/PRPs; SPDK talks to it
# like a PCIe NVMe controller. All user mode.
#
#   ./run_spdk_vfio.sh [identify|perf|all] [socket-dir]
set -u
MODE=${1:-all}
SOCK_DIR=${2:-/tmp/nvme-vfio-$$}
SPDK_DIR=${SPDK_DIR:-$HOME/repos/spdk}
DIR=$(cd "$(dirname "$0")" && pwd)

IDENTIFY="$SPDK_DIR/build/bin/spdk_nvme_identify"
PERF="$SPDK_DIR/build/bin/spdk_nvme_perf"
# a non-discovery subnqn keeps spdk_nvme_identify from asking for the
# discovery log page (which this NVM controller does not implement)
TRID="trtype:VFIOUSER traddr:$SOCK_DIR subnqn:nqn.2026-09.org.fugafuga:nvme:veryl-sim"

mkdir -p "$SOCK_DIR"
"$DIR"/obj_vfio/nvme_vfio_bridge "$SOCK_DIR" &
BRIDGE_PID=$!
trap 'kill $BRIDGE_PID 2>/dev/null; rm -rf "$SOCK_DIR"' EXIT

for i in $(seq 50); do
    [ -S "$SOCK_DIR/cntrl" ] && break
    sleep 0.1
done

RC=0
if [ "$MODE" = identify ] || [ "$MODE" = all ]; then
    echo "=== spdk_nvme_identify (vfio-user) ==="
    "$IDENTIFY" --no-huge -s 512 -r "$TRID" || RC=1
fi
if [ "$MODE" = perf ] || [ "$MODE" = all ]; then
    echo "=== spdk_nvme_perf (vfio-user, 4KiB randrw QD4, 5s) ==="
    "$PERF" --no-huge -s 512 -r "$TRID" -o 4096 -q 4 -w randrw -M 50 -t 5 || RC=1
    echo "=== spdk_nvme_perf (4 cores -> 4 I/O queue pairs) ==="
    "$PERF" --no-huge -s 512 -r "$TRID" -o 4096 -q 4 -w randrw -M 50 -t 5 -c 0xF || RC=1
fi
exit $RC
