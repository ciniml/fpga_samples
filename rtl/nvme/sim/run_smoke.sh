#!/bin/bash
# Start the bridge, run the Python smoke host against it, tear down.
set -u
PORT=${1:-4420}
DIR=$(cd "$(dirname "$0")" && pwd)

BRIDGE_BIN=${BRIDGE_BIN:-$DIR/obj_dir/nvme_tcp_bridge}
"$BRIDGE_BIN" "$PORT" &
BRIDGE_PID=$!
trap 'kill $BRIDGE_PID 2>/dev/null' EXIT

for i in $(seq 50); do
    if (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null; then exec 3>&-; break; fi
    sleep 0.1
done

python3 "$DIR"/smoke_host.py "$PORT"
RC=$?
exit $RC
