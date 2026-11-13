#!/usr/bin/env bash
# Searchable cheat sheet of every Hyprland keybind (SUPER + /).
# Rows come straight from the live config via keybinds.lua, so there is
# nothing to keep in sync. Pressing the shortcut again closes it.

pkill -x rofi && exit 0

here="$(dirname "$(readlink -f "$0")")"

lua "$here/keybinds.lua" |
    rofi -dmenu -i -markup-rows -no-custom \
        -matching normal -sort false \
        -p "  Keybinds" \
        -theme "$here/keybinds.rasi" >/dev/null
exit 0
