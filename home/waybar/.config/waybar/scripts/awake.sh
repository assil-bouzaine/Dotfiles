#!/usr/bin/env bash
# "Stay awake" for the bar's custom/awake button, SUPER + CTRL + I and the
# Arch menu's Toggle page (Omarchy's "Toggle locking on idle").
#   awake.sh          print the button's JSON (waybar's exec)
#   awake.sh toggle   on / off
#   awake.sh on|off   (autostart.lua runs `awake.sh on`: it's on after every login)
#   awake.sh state    print on / off
# On = a systemd idle inhibitor held by a background `sleep infinity`.
# hypridle honours it, so no lock, screen off or suspend while it's on.
# Closing the lid still suspends.

PIDF="$XDG_RUNTIME_DIR/stay-awake.pid"
ICON=$''   # Omarchy 4.5's stay-awake mug, both states (off is dimmed)

# The pid has to still be our systemd-inhibit: a stale file must never make
# `off` kill whatever process got that pid later.
is_on() {
    local pid
    pid=$(cat "$PIDF" 2>/dev/null) || return 1
    [[ $pid =~ ^[0-9]+$ ]] && [[ $(cat "/proc/$pid/comm" 2>/dev/null) == systemd-inhibit ]]
}

turn_on() {
    is_on && return
    setsid systemd-inhibit --what=idle --who="Stay awake" \
        --why="Bar toggle: no lock, screen off or sleep" sleep infinity \
        >/dev/null 2>&1 &
    echo $! >"$PIDF"
}

turn_off() {
    is_on && kill -- -"$(cat "$PIDF")" 2>/dev/null   # its whole process group
    rm -f "$PIDF"
}

changed() {
    sleep 0.1
    "${0%/*}/bar-signal" 11   # never a bare pkill: see bar-signal (it killed the bar at login)
}

case $1 in
toggle) if is_on; then turn_off; else turn_on; fi; changed ;;
on)     turn_on;  changed ;;
off)    turn_off; changed ;;
state)  is_on && echo on || echo off ;;
*)
    if is_on; then
        printf '{"text": "%s", "class": "on", "tooltip": "Stay awake: on\\nNo lock, screen off or sleep · Click: off"}\n' "$ICON"
    else
        printf '{"text": "%s", "class": "off", "tooltip": "Stay awake: off\\nLocks after 5 min, sleeps after 30 · Click: on"}\n' "$ICON"
    fi
    ;;
esac
