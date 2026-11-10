#!/bin/bash
set -uo pipefail

data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}

systemctl --user stop kortex.service 2>/dev/null
kpackagetool6 --type Plasma/Applet --remove local.kortex
rm -f "$HOME/.local/bin/kortex-service" \
    "$config/systemd/user/kortex.service" \
    "$data/dbus-1/services/local.Kortex.service" \
    "$data/icons/hicolor/scalable/apps/local.kortex.svg"
systemctl --user daemon-reload
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig
