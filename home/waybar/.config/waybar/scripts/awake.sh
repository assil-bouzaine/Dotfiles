#!/usr/bin/env bash
# "Stay awake" for the bar's custom/awake button and SUPER + CTRL + I
# (Omarchy's "Toggle locking on idle").
#   awake.sh          print the button's JSON (waybar's exec)
#   awake.sh toggle   on / off
# On = a systemd idle inhibitor held by a background `sleep infinity`.
# hypridle honours it, so no lock, screen off or suspend while it's on.
# Closing the lid still suspends. Off again after a reboot.

PIDF="$XDG_RUNTIME_DIR/stay-awake.pid"

on() { [[ -f $PIDF ]] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }

case $1 in
toggle)
    if on; then
        kill -- -"$(cat "$PIDF")" 2>/dev/null   # its whole process group
        rm -f "$PIDF"
    else
        setsid systemd-inhibit --what=idle --who="Stay awake" \
            --why="Bar toggle: no lock, screen off or sleep" sleep infinity \
            >/dev/null 2>&1 &
        echo $! >"$PIDF"
    fi
    sleep 0.1
    pkill -RTMIN+11 -x waybar
    ;;
*)
    if on; then
        printf '{"text": "󰈈", "class": "on", "tooltip": "Stay awake: on\\nNo lock, screen off or sleep · Click: off"}\n'
    else
        printf '{"text": "󰈉", "class": "off", "tooltip": "Stay awake: off\\nLocks after 5 min, sleeps after 30 · Click: on"}\n'
    fi
    ;;
esac
