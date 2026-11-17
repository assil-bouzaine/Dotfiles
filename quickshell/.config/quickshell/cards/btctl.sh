#!/bin/bash
# Bluetooth actions for the Bluetooth card (BtCard.qml) and the bar icon.
#   btctl.sh power on|off|toggle
#   btctl.sh pair|connect|disconnect|forget <address>
# Ported from Omarchy 4.5's omarchy-bluetooth-power / omarchy-bluetooth-device
# (MIT, github.com/basecamp/omarchy). Power moves the rfkill soft block rather
# than BlueZ's Powered flag, so off / on survives a reboot. A headset that
# connects becomes the default sound output, as in Omarchy.

set -u

powered() { timeout 2s bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; }

power_on() {
    rfkill unblock bluetooth
    for _ in $(seq 10); do powered && return 0; sleep 0.2; done
    timeout 5s bluetoothctl power on >/dev/null 2>&1
    for _ in $(seq 10); do powered && return 0; sleep 0.2; done
    return 1
}

# Make the device's PipeWire sink the default output once it shows up.
use_as_output() {
    local id=${1//:/_} sink
    for _ in $(seq 16); do
        sink=$(pactl list short sinks 2>/dev/null | awk -v id="$id" '$2 ~ "bluez_output." id {print $2; exit}')
        if [[ -n $sink ]]; then
            pactl set-default-sink "$sink"
            return
        fi
        sleep 0.5
    done
}

case "${1:-}" in
power)
    case "${2:-}" in
        on) power_on ;;
        off) rfkill block bluetooth ;;
        toggle) if powered; then rfkill block bluetooth; else power_on; fi ;;
    esac
    ;;
pair|connect|disconnect|forget)
    addr=${2:-}
    [[ $addr =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || { echo "bad address" >&2; exit 2; }
    case "$1" in
        pair)
            powered || power_on
            timeout 20s bluetoothctl pair "$addr" >/dev/null 2>&1
            bluetoothctl trust "$addr" >/dev/null 2>&1
            timeout 20s bluetoothctl connect "$addr" >/dev/null 2>&1 && use_as_output "$addr"
            ;;
        connect)
            powered || power_on
            bluetoothctl trust "$addr" >/dev/null 2>&1
            timeout 20s bluetoothctl connect "$addr" >/dev/null 2>&1 && use_as_output "$addr"
            ;;
        disconnect)
            timeout 10s bluetoothctl disconnect "$addr" >/dev/null 2>&1
            ;;
        forget)
            timeout 10s bluetoothctl disconnect "$addr" >/dev/null 2>&1
            timeout 10s bluetoothctl remove "$addr" >/dev/null 2>&1
            ;;
    esac
    ;;
*)
    echo "usage: btctl.sh power on|off|toggle | pair|connect|disconnect|forget <address>" >&2
    exit 2
    ;;
esac
exit 0
