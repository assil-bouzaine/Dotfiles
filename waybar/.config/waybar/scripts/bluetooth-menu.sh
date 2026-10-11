#!/usr/bin/env bash
# Bluetooth card for the waybar bluetooth module (rofi + bluetoothctl).
# Same card as the Wi-Fi menu (theme: card.rasi). Picking a paired device
# connects it, or disconnects it when it is already connected.
# "Scan for new devices" finds, pairs, trusts and connects a new one;
# devices that need a PIN are easier from "Bluetooth settings" (blueman).

theme=~/.config/waybar/scripts/card.rasi
dim="#5c6370"
cyan="#33ccff"
scan_seconds=8

menu()   { rofi -dmenu -i -markup-rows -theme "$theme" "$@"; }
# One toast per menu: each message replaces the previous one instead of stacking
notify() { notify-send -a "Bluetooth" -i bluetooth -h string:x-canonical-private-synchronous:bluetooth "$1" "$2"; }
esc()    { local s=${1//&/&amp;}; s=${s//</&lt;}; printf '%s' "${s//>/&gt;}"; }
fit()    { (( $1 < 7 )) && echo "$1" || echo 7; }  # rows shown, max 7

powered() { bluetoothctl show | grep -q 'Powered: yes'; }

device_icon() {
    case $1 in
        audio-headset|audio-headphones) echo "󰋋" ;;
        audio-card)                     echo "󰓃" ;;
        input-keyboard)                 echo "󰌌" ;;
        input-mouse)                    echo "󰍽" ;;
        input-gaming)                   echo "󰊴" ;;
        phone)                          echo "󰄜" ;;
        *)                              echo "󰂯" ;;
    esac
}

if ! powered; then
    choice=$(printf '󰂯   Turn Bluetooth on\n' |
        menu -p "󰂲" -mesg "Bluetooth is off" -l 1 -theme-str 'inputbar { enabled: false; }')
    [[ -z $choice ]] && exit 0
    rfkill unblock bluetooth  # power on fails while rfkill soft-blocks it
    sleep 1
    bluetoothctl power on >/dev/null && notify "Bluetooth on" "" ||
        notify "Couldn't turn Bluetooth on" "Check: rfkill list bluetooth"
    exit 0
fi

scan() {
    notify "Scanning…" "Looking for devices for ${scan_seconds}s"
    bluetoothctl --timeout "$scan_seconds" scan on >/dev/null 2>&1
    local paired; paired=$(bluetoothctl devices Paired | cut -d' ' -f2)
    macs=() rows=()
    while read -r _ mac name; do
        grep -qF -- "$mac" <<<"$paired" && continue
        [[ $name == "${mac//:/-}" ]] && continue  # nameless devices
        macs+=("$mac")
        rows+=("<span color='$cyan'>󰂯</span>   $(esc "$name")")
    done < <(bluetoothctl devices)

    if (( ${#rows[@]} == 0 )); then
        notify "No new devices found" "Put the device in pairing mode and try again"
        exit 0
    fi
    choice=$(printf '%s\n' "${rows[@]}" |
        menu -p "󰂰" -mesg "New devices" -format i -l "$(fit ${#rows[@]})")
    [[ -z $choice || $choice -lt 0 ]] && exit 0  # -1: typed text matching no row

    mac=${macs[choice]}
    name=$(bluetoothctl info "$mac" | sed -n 's/^\s*Alias: //p')
    notify "Pairing…" "$name"
    if bluetoothctl pair "$mac" >/dev/null 2>&1 &&
       bluetoothctl trust "$mac" >/dev/null 2>&1 &&
       bluetoothctl connect "$mac" >/dev/null 2>&1; then
        notify "Connected" "$name"
    else
        notify "Failed to pair" "$name (try Bluetooth settings)"
    fi
    exit 0
}

# Paired devices, connected ones first
macs=() rows=()
connected_names=()
while read -r _ mac name; do
    info=$(bluetoothctl info "$mac")
    icon=$(device_icon "$(sed -n 's/^\s*Icon: //p' <<<"$info")")
    battery=$(sed -n 's/^\s*Battery Percentage: .*(\([0-9]*\))/\1/p' <<<"$info")
    label=$(esc "$name")
    if grep -q 'Connected: yes' <<<"$info"; then
        extra="󰄬"; [[ -n $battery ]] && extra="$battery%  󰄬"
        macs=("$mac" "${macs[@]}")
        rows=("<span color='$cyan'>$icon</span>   <b>$label</b>   <span color='$cyan' size='small'>$extra</span>" "${rows[@]}")
        connected_names+=("$label")
    else
        macs+=("$mac")
        rows+=("<span color='$cyan'>$icon</span>   $label   <span color='$dim' size='small'>paired</span>")
    fi
done < <(bluetoothctl devices Paired)

if (( ${#connected_names[@]} )); then
    status="Connected to <span color='$cyan'><b>$(IFS=,; echo "${connected_names[*]}" | sed 's/,/, /g')</b></span>"
else
    status="On · no device connected"
fi

actions=(
    "<span color='$dim'>󰑐   Scan for new devices</span>"
    "<span color='$dim'>󰒓   Bluetooth settings</span>"
    "<span color='$dim'>󰂲   Turn Bluetooth off</span>"
)
all=("${rows[@]}" "${actions[@]}")

choice=$(printf '%s\n' "${all[@]}" |
    menu -p "󰂯" -mesg "$status" -format i -l "$(fit ${#all[@]})")
[[ -z $choice || $choice -lt 0 ]] && exit 0  # -1: typed text matching no row

case $(( choice - ${#rows[@]} )) in
    0) scan ;;
    1) blueman-manager & exit 0 ;;
    2) bluetoothctl power off >/dev/null && notify "Bluetooth off" ""; exit 0 ;;
esac

mac=${macs[choice]}
name=$(bluetoothctl info "$mac" | sed -n 's/^\s*Alias: //p')
if bluetoothctl info "$mac" | grep -q 'Connected: yes'; then
    bluetoothctl disconnect "$mac" >/dev/null 2>&1 && notify "Disconnected" "$name"
else
    notify "Connecting…" "$name"
    bluetoothctl connect "$mac" >/dev/null 2>&1 &&
        notify "Connected" "$name" || notify "Failed to connect" "$name"
fi
