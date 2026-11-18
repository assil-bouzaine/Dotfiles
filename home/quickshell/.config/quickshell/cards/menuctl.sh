#!/usr/bin/env bash
# Helper for the Arch menu (MenuCard.qml).
#   menuctl.sh state [workspace-id]
# Prints one JSON line: the Toggle page's switches, uptime (s) and kernel.
# The switches ask the same scripts the bar buttons use.

bar=~/.config/waybar/scripts

is() { [[ $1 == "$2" ]] && echo true || echo false; }

case $1 in
state)
    floating=false
    if [[ $2 =~ ^[0-9]+$ ]] && grep -qx "$2 floating" "$XDG_RUNTIME_DIR/workspace-modes" 2>/dev/null; then
        floating=true   # see hypr/conf.d/workspace-modes.lua
    fi
    read -r up _ </proc/uptime
    printf '{"awake":%s,"nightlight":%s,"dnd":%s,"performance":%s,"floating":%s,"uptime":%d,"kernel":"%s"}\n' \
        "$(is "$("$bar/awake.sh" state)" on)" \
        "$(is "$("$bar/nightlight.sh" state)" on)" \
        "$(is "$(swaync-client -D 2>/dev/null)" true)" \
        "$(is "$(powerprofilesctl get 2>/dev/null)" performance)" \
        "$floating" "${up%.*}" "$(uname -r)"
    ;;
*)
    echo "usage: menuctl.sh state [workspace-id]" >&2
    exit 2
    ;;
esac
