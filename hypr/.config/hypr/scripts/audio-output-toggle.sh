#!/usr/bin/env bash
# Toggle sound between the laptop speakers and the monitor's headphone jack (HDMI).
# The monitor can't report whether something is plugged into its jack, so this is manual.

card="alsa_card.pci-0000_00_1f.3"
laptop="output:analog-stereo+input:analog-stereo"
monitor="output:hdmi-stereo+input:analog-stereo"

active=$(pactl list cards | awk -v c="$card" '$1 == "Name:" { mine = ($2 == c) } mine && /Active Profile:/ { print $3; exit }')

if [[ "$active" == "$monitor" ]]; then
    pactl set-card-profile "$card" "$laptop" && notify-send -t 2000 "Audio" "Laptop speakers"
else
    pactl set-card-profile "$card" "$monitor" && notify-send -t 2000 "Audio" "Monitor jack (HDMI)"
fi
