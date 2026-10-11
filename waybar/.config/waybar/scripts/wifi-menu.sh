#!/usr/bin/env bash
# Wi-Fi picker for the waybar network module (rofi + nmcli).
# Opens a card under the bar (theme: card.rasi). Picking a saved network
# reconnects, picking a new secured one asks for the password.
# The last entry turns Wi-Fi off.

theme=~/.config/waybar/scripts/card.rasi
dim="#5c6370"
cyan="#33ccff"

menu()   { rofi -dmenu -i -markup-rows -theme "$theme" "$@"; }
# One toast per menu: each message replaces the previous one instead of stacking
notify() { notify-send -a "Wi-Fi" -i network-wireless -h string:x-canonical-private-synchronous:wifi "$1" "$2"; }
esc()    { local s=${1//&/&amp;}; s=${s//</&lt;}; printf '%s' "${s//>/&gt;}"; }

if [[ $(nmcli -t -f WIFI radio) == "disabled" ]]; then
    choice=$(printf '󰖩   Turn Wi-Fi on\n' |
        menu -p "󰖪" -mesg "Wi-Fi is off" -l 1 -theme-str 'inputbar { enabled: false; }')
    [[ -n $choice ]] && nmcli radio wifi on && notify "Wi-Fi on" ""
    exit 0
fi

# The cached scan opens instantly; a background rescan refreshes it for next
# time. Only block on a scan when there is nothing cached yet.
list() {
    # -t escapes ':' inside fields as '\:'; SSID is last so it can keep them.
    nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan "$1" |
        awk -F: '$4 != "" && !seen[$4]++' |
        sort -s -t: -k1,1r  # connected network first
}
mapfile -t networks < <(list no)
(( ${#networks[@]} == 0 )) && mapfile -t networks < <(list yes)
nmcli device wifi rescan >/dev/null 2>&1 &

rows=()
status="Not connected"
for row in "${networks[@]}"; do
    IFS=: read -r inuse signal security ssid <<<"$row"
    ssid=$(esc "${ssid//\\:/:}")
    if   (( signal >= 75 )); then icon="󰤨"
    elif (( signal >= 50 )); then icon="󰤥"
    elif (( signal >= 25 )); then icon="󰤢"
    else                          icon="󰤟"
    fi
    lock=""; [[ -n $security && $security != "--" ]] && lock="󰌾 "
    if [[ $inuse == "*" ]]; then
        status="Connected to <span color='$cyan'><b>$ssid</b></span>"
        rows+=("<span color='$cyan'>$icon</span>   <b>$ssid</b>   <span color='$cyan' size='small'>󰄬</span>")
    else
        rows+=("<span color='$cyan'>$icon</span>   $ssid   <span color='$dim' size='small'>$lock$signal%</span>")
    fi
done
rows+=("<span color='$dim'>󰖪   Turn Wi-Fi off</span>")

lines=$(( ${#rows[@]} < 7 ? ${#rows[@]} : 7 ))
choice=$(printf '%s\n' "${rows[@]}" | menu -p "󰖩" -mesg "$status" -format i -l "$lines")
[[ -z $choice || $choice -lt 0 ]] && exit 0  # -1: typed text matching no row

if (( choice == ${#networks[@]} )); then
    nmcli radio wifi off && notify "Wi-Fi off" ""
    exit 0
fi

IFS=: read -r inuse signal security ssid <<<"${networks[choice]}"
ssid=${ssid//\\:/:}

if [[ $inuse == "*" ]]; then
    notify "Already connected" "$ssid"
elif nmcli -t -f NAME connection show | grep -Fxq -- "$ssid"; then
    notify "Connecting…" "$ssid"
    nmcli connection up id "$ssid" >/dev/null 2>&1 &&
        notify "Connected" "$ssid" || notify "Failed to connect" "$ssid"
elif [[ -n $security && $security != "--" ]]; then
    password=$(menu -password -p "󰌾" -mesg "Password for <b>$(esc "$ssid")</b>" \
        -theme-str 'listview { enabled: false; } entry { placeholder: "Password"; }' </dev/null)
    [[ -z $password ]] && exit 0
    notify "Connecting…" "$ssid"
    if nmcli device wifi connect "$ssid" password "$password" >/dev/null 2>&1; then
        notify "Connected" "$ssid"
    else
        # nmcli keeps the profile even when the password is wrong; drop it
        # so the next try asks for the password again.
        nmcli connection delete id "$ssid" >/dev/null 2>&1
        notify "Failed to connect" "$ssid (wrong password?)"
    fi
else
    notify "Connecting…" "$ssid"
    nmcli device wifi connect "$ssid" >/dev/null 2>&1 &&
        notify "Connected" "$ssid" || notify "Failed to connect" "$ssid"
fi
