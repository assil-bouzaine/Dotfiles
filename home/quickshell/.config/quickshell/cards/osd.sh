#!/usr/bin/env bash
# On-screen display for the brightness and volume keys (OsdCard.qml, option A).
#   osd.sh volume up | down | mute
#   osd.sh brightness up | down
# Changes the level the same way the keys always did, reads the new value
# back and shows the pill under the bar. The shell may not be running (first
# login, or Quickshell crashed); then the key still works, only the pill is
# missing.

set -u

pop() { qs ipc -c cards call osd pop "$1" "$2" "$3" >/dev/null 2>&1; }

volume() {
    case $1 in
    up)     wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+ ;;
    down)   wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
    mute)   wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    *)      echo "osd.sh: volume up|down|mute" >&2; exit 2 ;;
    esac

    # "Volume: 0.45" or "Volume: 0.45 [MUTED]"
    read -r _ level rest < <(wpctl get-volume @DEFAULT_AUDIO_SINK@)
    pct=$(awk -v l="$level" 'BEGIN { printf "%d", l * 100 + 0.5 }')
    muted=false
    [[ $rest == *MUTED* ]] && muted=true
    pop sound "$pct" "$muted"
}

brightness() {
    case $1 in
    up)     brightnessctl -d intel_backlight set +10% >/dev/null ;;
    down)   brightnessctl -d intel_backlight set 10%- >/dev/null ;;
    *)      echo "osd.sh: brightness up|down" >&2; exit 2 ;;
    esac

    cur=$(brightnessctl -d intel_backlight get)
    max=$(brightnessctl -d intel_backlight max)
    pct=$(( (cur * 100 + max / 2) / max ))
    pop light "$pct" false
}

case ${1:-} in
volume)     volume "${2:-}" ;;
brightness) brightness "${2:-}" ;;
*)          echo "usage: osd.sh volume up|down|mute | brightness up|down" >&2; exit 2 ;;
esac
