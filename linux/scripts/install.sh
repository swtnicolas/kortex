#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}
binary=$HOME/.local/bin/kortex-service
icon=$repo/assets/icon/AppIcon.svg
[[ -f $icon ]] || icon=$repo/../assets/icon/AppIcon.svg

if [[ -f $repo/service/Cargo.toml ]]; then
    cargo build --release --manifest-path "$repo/service/Cargo.toml"
fi

install -Dm755 "$repo/service/target/release/kortex-service" "$binary"
install -Dm644 "$repo/service/kortex.service" "$config/systemd/user/kortex.service"
install -Dm644 /dev/stdin "$data/dbus-1/services/local.Kortex.service" <<EOF
[D-BUS Service]
Name=local.Kortex
Exec=$binary
SystemdService=kortex.service
EOF
install -Dm644 "$icon" "$data/icons/hicolor/scalable/apps/local.kortex.svg"

systemctl --user daemon-reload
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig
systemctl --user try-restart kortex.service

if kpackagetool6 --type Plasma/Applet --show local.kortex >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --upgrade "$repo/plasmoid"
    echo "Plasmoid upgraded: run 'systemctl --user restart plasma-plasmashell' to load it."
else
    kpackagetool6 --type Plasma/Applet --install "$repo/plasmoid"
    echo "Plasmoid installed: add Kortex to a panel from 'Add Widgets'."
fi
