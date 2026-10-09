#!/bin/sh
# Launch the Gowin IDE GUI (1.9.12) on an X display (e.g. SSH X forwarding).
#
# Two workarounds for Ubuntu 24.04:
#  * The bundled Qt xcb plugin has RUNPATH $ORIGIN/../../lib (non-existent), so it
#    resolves the system Qt and the two mix -> abort. Putting IDE/lib first fixes it.
#  * The SerDes IP generator (bin/serdes_toml_to_csr.dist/*.bin, a frozen Python)
#    needs libffi.so.6, which Ubuntu 24.04 no longer ships. An alias directory
#    pointing the name at the system libffi.so.8 makes it run. Without it the
#    IP Core Generator shows an empty error dialog for every SerDes IP.
#
# Usage: gw_ide.sh [project.gprj]
GOWIN=${GOWIN:-$HOME/gowin/1.9.12/IDE}
ALIAS=${XDG_RUNTIME_DIR:-/tmp}/gowin_ffi_alias
mkdir -p "$ALIAS"
for so in /lib/x86_64-linux-gnu/libffi.so.8 /usr/lib/x86_64-linux-gnu/libffi.so.8; do
    [ -e "$so" ] && ln -sf "$so" "$ALIAS/libffi.so.6" && break
done
export DISPLAY=${DISPLAY:-localhost:10.0}
export LD_LIBRARY_PATH="$GOWIN/lib:$ALIAS${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$GOWIN/bin/gw_ide" "$@"
