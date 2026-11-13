#!/usr/bin/env python3
"""Bluetooth menu for the bar (Bluetooth icon, SUPER + B), drawn with card.rasi.

Lists known devices through bluetoothctl. Enter connects or disconnects
(pairing a new device first); Shift + Delete forgets a device. Below the
devices: scan for new ones and Bluetooth on/off. Turning it on also lifts
the rfkill soft block, which bluetoothctl alone can't.
"""

import re
import sys
import time

sys.dont_write_bytecode = True  # no __pycache__ in the dotfiles

from menu import FORGET, GREEN, escape, muted, note, notify, pick, run

ICONS = {
    "audio-headset": "󰋋", "audio-headphones": "󰋋", "audio-card": "󰓃",
    "input-mouse": "󰍽", "input-keyboard": "󰌌", "input-gaming": "󰊴",
    "phone": "󰏲", "computer": "󰌢",
}
HELP = "Enter: connect or disconnect   Shift + Delete: forget"
SCAN_SECONDS = 8


def btctl(*args, timeout=25):
    return run("bluetoothctl", *args, timeout=timeout)


def powered():
    return "Powered: yes" in btctl("show")[1]


def power_on():
    run("rfkill", "unblock", "bluetooth")
    for _ in range(10):  # the controller needs a moment after the unblock
        time.sleep(0.5)
        btctl("power", "on")
        if powered():
            return True
    return False


def devices():
    """Known devices: connected first, then paired, then just seen."""
    found = []
    for line in btctl("devices")[1].splitlines():
        m = re.match(r"Device (\S+) (.+)", line)
        if not m:
            continue
        mac, name = m.groups()
        info = btctl("info", mac)[1]
        dev = {
            "mac": mac, "name": name,
            "connected": "Connected: yes" in info,
            "paired": "Paired: yes" in info,
            "icon": ICONS.get((re.search(r"Icon: (\S+)", info) or [None, ""])[1], "󰂯"),
            "battery": (re.search(r"Battery Percentage: \S+ \((\d+)\)", info) or [None, None])[1],
        }
        if not dev["paired"] and name.replace("-", ":").upper() == mac:
            continue  # nameless device seen during a scan
        found.append(dev)
    return sorted(found, key=lambda d: (not d["connected"], not d["paired"], d["name"].lower()))


def row(dev):
    name = escape(dev["name"])
    if dev["connected"]:
        state = "Connected" + (f", {dev['battery']}%" if dev["battery"] else "")
        return f"<span color='{GREEN}'>{dev['icon']}</span>   <b>{name}</b>" + note(state)
    return f"{dev['icon']}   {name}" + note("Paired" if dev["paired"] else "New")


def toggle(dev):
    name = dev["name"]
    if dev["connected"]:
        btctl("disconnect", dev["mac"])
        notify("Bluetooth", f"Disconnected from {name}", "bluetooth")
        return
    if not dev["paired"]:
        ok, out = btctl("pair", dev["mac"], timeout=40)
        if not ok and "AlreadyExists" not in out:
            notify("Bluetooth", f"Couldn't pair with {name}\nPut it in pairing mode and try again", "bluetooth")
            return
        btctl("trust", dev["mac"])
    ok, out = btctl("connect", dev["mac"])
    if ok and "successful" in out:
        notify("Bluetooth", f"Connected to {name}", "bluetooth")
    else:
        notify("Bluetooth", f"Couldn't connect to {name}\nIs it on and in range?", "bluetooth")


def main():
    mesg = HELP
    while True:
        if not powered():
            i, _ = pick(["󰂯   Turn Bluetooth on"], "Bluetooth", "Bluetooth is off")
            if i != 0:
                return
            if not power_on():
                notify("Bluetooth", "Couldn't turn Bluetooth on", "bluetooth")
                return
            continue

        devs = devices()
        actions = [("scan", "󰑓   Scan for new devices"), ("off", "󰂲   Turn Bluetooth off")]
        rows = [row(d) for d in devs] + [muted(text) for _, text in actions]
        i, code = pick(rows, "Bluetooth", mesg if devs else "No devices yet. Scan to find one.", "Search devices")
        mesg = HELP
        if i is None:
            return

        if i < len(devs):
            if code == FORGET:
                btctl("remove", devs[i]["mac"])
                notify("Bluetooth", f"Forgot {devs[i]['name']}", "bluetooth")
                continue
            toggle(devs[i])
            return

        action = actions[i - len(devs)][0]
        if action == "scan":
            notify("Bluetooth", f"Scanning for {SCAN_SECONDS} seconds…", "bluetooth")
            btctl("--timeout", str(SCAN_SECONDS), "scan", "on", timeout=SCAN_SECONDS + 5)
            mesg = "Scan done. New devices are marked New."
            continue
        if action == "off":
            btctl("power", "off")
        return


if __name__ == "__main__":
    main()
