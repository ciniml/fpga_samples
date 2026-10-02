#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
#
# Start play.sh at desktop login (and keep the screen awake).
#   ./install-autostart.sh          install
#   ./install-autostart.sh --remove remove
set -eu
dir=$(cd "$(dirname "$0")" && pwd)
desk="$HOME/.config/autostart/dvi_hub75.desktop"
if [ "${1:-}" = "--remove" ]; then
    rm -f "$desk"
    gsettings reset org.gnome.desktop.session idle-delay
    gsettings reset org.gnome.desktop.screensaver lock-enabled
    gsettings reset org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
    echo "[autostart] removed"
    exit 0
fi
mkdir -p "$(dirname "$desk")"
cat >"$desk" <<EOT
[Desktop Entry]
Type=Application
Name=dvi_hub75 exhibit
Exec=bash -c 'sleep 5; "$dir/play.sh" >"$dir/play.log" 2>&1'
X-GNOME-Autostart-enabled=true
EOT
gsettings set org.gnome.desktop.session idle-delay 0
gsettings set org.gnome.desktop.screensaver lock-enabled false
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing'
echo "[autostart] $desk installed (screen blanking / lock / suspend disabled)"
