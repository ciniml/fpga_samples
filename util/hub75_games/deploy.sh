#!/bin/sh
# Builds static (musl) binaries for the host's CPU and installs them, then
# (re)starts its arcade service:  ./deploy.sh [host]   (default deltaflyer.local)
# x86_64 (the booth mini PC) and aarch64 (Raspberry Pi 4, 64-bit OS): the
# CPU is asked over ssh. The host runs ~/exhibit/hub75_games/bin/arcade as
# the systemd user service hub75-arcade (tools/hub75-arcade.service,
# installed and enabled here the first time; linger on: it starts at boot).
set -e
host=${1:-deltaflyer.local}
cd "$(dirname "$0")"
arch=$(ssh "$host" uname -m)
case $arch in
    x86_64) target=x86_64-unknown-linux-musl ;;
    aarch64) target=aarch64-unknown-linux-musl ;;
    *) echo "$host: $arch is not supported (x86_64 / aarch64)"; exit 1 ;;
esac
cargo build --release --offline --target $target
bins=$(ls src/bin | sed "s/\.rs$//")
ssh "$host" mkdir -p exhibit/hub75_games/bin .config/systemd/user
(cd target/$target/release && rsync -a $bins "$host:exhibit/hub75_games/bin/")
rsync -a README.md "$host:exhibit/hub75_games/"
rsync -a tools/hub75-arcade.service "$host:.config/systemd/user/"
ssh "$host" 'systemctl --user daemon-reload && systemctl --user enable -q hub75-arcade.service &&
    systemctl --user restart hub75-arcade.service &&
    { [ "$(loginctl show-user "$USER" -p Linger --value)" = yes ] || loginctl enable-linger ||
      echo "linger is off: the arcade starts only after a login (sudo loginctl enable-linger $USER)"; }'
echo "installed on $host ($arch), hub75-arcade restarted"
