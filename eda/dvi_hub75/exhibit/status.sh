#!/bin/bash
# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
# Distributed under the Boost Software License, Version 1.0.
#    (See accompanying file LICENSE_1_0.txt or copy at
#          https://www.boost.org/LICENSE_1_0.txt)
#
# Board status over the USB-UART (needs the ftdi_sio driver:
# sudo modprobe ftdi_sio).
#
#   ./status.sh            video + HDMI audio status for 5 s
#   ./status.sh gamma 2.0  other loopctl.py commands (gamma <g>, gamma identity, ...)
set -eu
cd "$(dirname "$0")"
port=$(ls /dev/serial/by-id/*USB_Debugger*if01* 2>/dev/null | head -1 || true)
[ -n "$port" ] || { echo "[status] no USB-UART: sudo modprobe ftdi_sio (and check the USB cable)" >&2; exit 1; }
if [ $# -eq 0 ]; then
    python3 loopctl.py --port "$port" status 3
    python3 loopctl.py --port "$port" audio 3
else
    python3 loopctl.py --port "$port" "$@"
fi
