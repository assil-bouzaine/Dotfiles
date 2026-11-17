#!/usr/bin/env bash
# Night light for the bar's custom/nightlight button, done by hyprsunset.
#   nightlight.sh            print the button's JSON (waybar's exec)
#   nightlight.sh toggle     start / stop hyprsunset
#   nightlight.sh warmer     -500K (scroll up), cooler: +500K (scroll down)
# The temperature is kept in $XDG_RUNTIME_DIR/waybar-nightlight, so it
# survives toggles (not reboots). After a change, SIGRTMIN+9 makes waybar
# re-run the status (the module's "signal": 9).

STATE="$XDG_RUNTIME_DIR/waybar-nightlight"
DEFAULT=4000 MIN=2500 MAX=6500 STEP=500

temp=$(cat "$STATE" 2>/dev/null)
[[ $temp =~ ^[0-9]+$ ]] || temp=$DEFAULT

running() { pgrep -x hyprsunset >/dev/null; }

refresh() {
    sleep 0.1   # let hyprsunset start / exit before waybar asks
    pkill -RTMIN+9 -x waybar
}

case $1 in
toggle)
    if running; then
        pkill -x hyprsunset
    else
        # setsid: keep it running when waybar restarts
        setsid -f hyprsunset -t "$temp" >/dev/null 2>&1
    fi
    refresh
    ;;
warmer|cooler)
    [[ $1 == warmer ]] && temp=$((temp - STEP)) || temp=$((temp + STEP))
    temp=$(( temp < MIN ? MIN : temp > MAX ? MAX : temp ))
    echo "$temp" > "$STATE"
    if running; then
        hyprctl hyprsunset temperature "$temp" >/dev/null
    fi
    refresh
    ;;
*)
    if running; then
        printf '{"text": "󰖔", "class": "on", "tooltip": "Night light on · %sK\\nClick: off · Scroll: warmer / cooler"}\n' "$temp"
    else
        printf '{"text": "󰖔", "class": "off", "tooltip": "Night light off (%sK when on)\\nClick: on · Scroll: warmer / cooler"}\n' "$temp"
    fi
    ;;
esac
