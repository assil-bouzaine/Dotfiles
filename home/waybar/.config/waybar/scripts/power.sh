#!/usr/bin/env bash
# Power profile for the bar's custom/power button (power-profiles-daemon).
#   power.sh           print the button's JSON (waybar's exec)
#   power.sh toggle    balanced <-> performance
# Balanced runs cooler, so the fan spins less; performance is snappier on the
# 120 Hz monitor. ppd keeps the choice across reboots. After a change,
# SIGRTMIN+10 makes waybar re-run the status (the module's "signal": 10).

profile=$(powerprofilesctl get 2>/dev/null)

case $1 in
toggle)
    [[ $profile == performance ]] && next=balanced || next=performance
    powerprofilesctl set "$next"
    "${0%/*}/bar-signal" 10   # not a bare pkill: see bar-signal
    ;;
*)
    if [[ $profile == performance ]]; then
        icon=$'\U000F04C5' other=balanced       # nf-md-speedometer
    else
        icon=$'\U000F0F85' other=performance    # nf-md-speedometer-medium
    fi
    printf '{"text": "%s", "class": "%s", "tooltip": "Power: %s\\nClick: switch to %s"}\n' \
        "$icon" "${profile:-unknown}" "${profile:-unknown}" "$other"
    ;;
esac
