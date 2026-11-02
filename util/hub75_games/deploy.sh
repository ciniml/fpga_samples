#!/bin/sh
# Builds static (musl) binaries and installs them on the booth PC, then
# restarts its arcade service:  ./deploy.sh [host]   (default deltaflyer.local)
# The booth PC runs ~/exhibit/hub75_games/bin/arcade as the systemd user
# service hub75-arcade (enabled, linger on: it starts at boot).
set -e
host=${1:-deltaflyer.local}
cd "$(dirname "$0")"
cargo build --release --offline --target x86_64-unknown-linux-musl
bins=$(ls src/bin | sed "s/\.rs$//")
ssh "$host" mkdir -p exhibit/hub75_games/bin
(cd target/x86_64-unknown-linux-musl/release && rsync -a $bins "$host:exhibit/hub75_games/bin/")
rsync -a README.md "$host:exhibit/hub75_games/"
ssh "$host" systemctl --user restart hub75-arcade.service
echo "installed on $host, hub75-arcade restarted"
