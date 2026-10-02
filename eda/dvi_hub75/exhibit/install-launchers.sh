#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
#
# Desktop launchers (Activities / dock) and keyboard shortcuts for show.sh:
#   Ctrl+Alt+1 阪神高速  2 デモ  3 全部  4 テストパターン  5 停止
#
#   ./install-launchers.sh            install
#   ./install-launchers.sh --remove   remove
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
apps="$HOME/.local/share/applications"
base=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
schema=org.gnome.settings-daemon.plugins.media-keys
entries=("hanshin:阪神高速:1" "demos:デモ:2" "all:全部:3" "pattern:テストパターン:4" "stop:停止:5")

current=$(gsettings get $schema custom-keybindings)
# drop our own entries from the list (keep everything else)
others=$(python3 -c "
import ast, sys
cur = sys.argv[1].replace('@as ', '')
l = ast.literal_eval(cur) if cur.strip() else []
print([p for p in l if '/dvi-hub75-' not in p])" "$current")

if [ "${1:-}" = "--remove" ]; then
    for e in "${entries[@]}"; do
        mode=${e%%:*}
        rm -f "$apps/dvi_hub75-$mode.desktop"
        gsettings reset-recursively "$schema.custom-keybinding:$base/dvi-hub75-$mode/" 2>/dev/null || true
    done
    gsettings set $schema custom-keybindings "$others"
    echo "[launchers] removed"
    exit 0
fi

mkdir -p "$apps"
list=$(python3 -c "import ast,sys; print(ast.literal_eval(sys.argv[1]))" "$others")
for e in "${entries[@]}"; do
    IFS=: read -r mode label key <<<"$e"
    cat >"$apps/dvi_hub75-$mode.desktop" <<EOT
[Desktop Entry]
Type=Application
Name=HUB75: $label
Exec=$dir/show.sh $mode
Icon=video-display
Terminal=false
Categories=AudioVideo;
EOT
    path="$base/dvi-hub75-$mode/"
    gsettings set "$schema.custom-keybinding:$path" name "HUB75: $label"
    gsettings set "$schema.custom-keybinding:$path" command "$dir/show.sh $mode"
    gsettings set "$schema.custom-keybinding:$path" binding "<Primary><Alt>$key"
    list=$(python3 -c "import ast,sys; l=ast.literal_eval(sys.argv[1]); l.append(sys.argv[2]); print(l)" "$list" "$path")
done
gsettings set $schema custom-keybindings "$list"
echo "[launchers] installed: Activities -> 'HUB75: ...', Ctrl+Alt+1..5"
