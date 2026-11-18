#!/usr/bin/env bash
# Night light for the bar's custom/nightlight button and the Arch menu's
# Toggle page, done by hyprsunset.
#   nightlight.sh            print the button's JSON (waybar's exec)
#   nightlight.sh toggle     on / off (also: on, off)
#   nightlight.sh state      print on / off
#   nightlight.sh warmer     -250K (scroll up), cooler: +250K (scroll down)
#
# Gentle by default: 5000K (it was 4000K, a strong orange), and it fades in
# and out over about a second instead of switching at once. Scroll on the
# button to make it warmer (down to 3000K) or cooler (up to 6000K).
# The chosen temperature is kept in $XDG_RUNTIME_DIR/waybar-nightlight, so it
# survives toggles (not reboots). After a change, SIGRTMIN+9 makes waybar
# re-run the status (the module's "signal": 9).

STATE="$XDG_RUNTIME_DIR/waybar-nightlight"       # the chosen temperature
FLAG="$XDG_RUNTIME_DIR/waybar-nightlight.on"     # there while it's on
FADE="$XDG_RUNTIME_DIR/waybar-nightlight.fade"   # pid of the newest fade
DEFAULT=5000 MIN=3000 MAX=6000 STEP=250
DAY=6500       # all but neutral: fades start and end here
FRAMES=20      # a fade is FRAMES steps ~50 ms apart

temp=$(cat "$STATE" 2>/dev/null)
[[ $temp =~ ^[0-9]+$ ]] || temp=$DEFAULT

running() { pgrep -x hyprsunset >/dev/null; }
is_on()   { [[ -e $FLAG ]] && running; }
changed() { "${0%/*}/bar-signal" 9; }   # not a bare pkill: see bar-signal

# What hyprsunset shows now (it reports 6000 while it shows no tint at all,
# so a fresh start is passed in as DAY instead of asked).
shown() {
    local t
    t=$(hyprctl hyprsunset temperature 2>/dev/null)
    [[ $t =~ ^[0-9]+$ ]] && echo "$t" || echo "$1"
}

# glide FROM TO: eases from one temperature to the other. A newer toggle
# or scroll writes its own pid to $FADE, and this one gives way.
glide() {
    local from=$1 to=$2 i x
    echo $$ >"$FADE"
    for ((i = 1; i <= FRAMES; i++)); do
        [[ $(cat "$FADE" 2>/dev/null) == "$$" ]] || return 1
        x=$(( i * 1000 / FRAMES ))     # smoothstep, 3x² - 2x³, in thousandths
        hyprctl hyprsunset temperature \
            $(( from + (to - from) * (3 * x * x * 1000 - 2 * x * x * x) / 1000000000 )) >/dev/null || return 1
        sleep 0.04
    done
}

turn_on() {
    touch "$FLAG"
    if running; then
        changed
        glide "$(shown "$DAY")" "$temp"   # it was fading out: turn round
    else
        setsid -f hyprsunset -i >/dev/null 2>&1   # setsid: outlives a waybar restart
        for _ in {1..40}; do
            hyprctl hyprsunset temperature >/dev/null 2>&1 && break
            sleep 0.05
        done
        changed   # only now: the bar's status needs hyprsunset running
        glide "$DAY" "$temp"
    fi
}

turn_off() {
    rm -f "$FLAG"
    changed
    running || return 0
    glide "$(shown "$temp")" "$DAY" || return 0   # turned back on meanwhile
    [[ -e $FLAG ]] && return 0
    hyprctl hyprsunset identity >/dev/null
    pkill -x hyprsunset
}

# 5000K and up reads as a soft tint, 4000K as plainly orange.
feel() {
    if   (( $1 >= 5500 )); then echo "faint"
    elif (( $1 >= 4750 )); then echo "soft"
    elif (( $1 >= 4000 )); then echo "warm"
    else echo "very warm"
    fi
}

case $1 in
toggle) if is_on; then turn_off; else turn_on; fi ;;
on)     is_on || turn_on ;;
off)    turn_off ;;
state)  is_on && echo on || echo off ;;
warmer|cooler)
    [[ $1 == warmer ]] && temp=$((temp - STEP)) || temp=$((temp + STEP))
    temp=$(( temp < MIN ? MIN : temp > MAX ? MAX : temp ))
    echo "$temp" > "$STATE"
    if is_on; then
        echo $$ >"$FADE"   # stops a fade still running
        hyprctl hyprsunset temperature "$temp" >/dev/null
    fi
    changed
    ;;
*)
    if is_on; then
        printf '{"text": "󰖔", "class": "on", "tooltip": "Night light on · %sK, %s\\nClick: off · Scroll: warmer / cooler"}\n' "$temp" "$(feel "$temp")"
    else
        printf '{"text": "󰖔", "class": "off", "tooltip": "Night light off (%sK, %s, when on)\\nClick: on · Scroll: warmer / cooler"}\n' "$temp" "$(feel "$temp")"
    fi
    ;;
esac
