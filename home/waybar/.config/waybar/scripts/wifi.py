#!/usr/bin/env python3
"""Wi-Fi menu for the bar (Wi-Fi icon, SUPER + N), drawn with card.rasi.

Lists the networks in range through nmcli. Enter connects (asking for the
password of a new network) or disconnects the current one; Shift + Delete
forgets a saved network. Below the networks: scan again, Wi-Fi on/off and
the full connection editor.
"""

import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True  # no __pycache__ in the dotfiles

from menu import FORGET, GREEN, escape, muted, note, notify, pick, ask_password, run

BARS = ["󰤟", "󰤢", "󰤥", "󰤨"]   # same icons as the bar
HELP = "Enter: connect or disconnect   Shift + Delete: forget"


def nmcli(*args, timeout=30):
    return run("nmcli", *args, timeout=timeout)


def wifi_on():
    return nmcli("radio", "wifi")[1] == "enabled"


def wifi_device():
    for line in nmcli("-t", "-f", "DEVICE,TYPE", "device")[1].splitlines():
        dev, _, kind = line.partition(":")
        if kind == "wifi":
            return dev
    return None


def saved_networks():
    out = nmcli("-t", "-f", "TYPE,NAME", "connection", "show")[1]
    return {l.split(":", 1)[1].replace("\\:", ":") for l in out.splitlines()
            if l.startswith("802-11-wireless:")}


def networks(rescan="no"):
    """Networks in range, strongest first, the connected one on top."""
    out = nmcli("-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "device", "wifi", "list",
                "--rescan", rescan, timeout=20)[1]
    best = {}
    for line in out.splitlines():
        parts = re.split(r"(?<!\\):", line, maxsplit=3)
        if len(parts) < 4 or not parts[3]:
            continue  # hidden network
        ssid = parts[3].replace("\\:", ":").replace("\\\\", "\\")
        net = {"ssid": ssid, "used": parts[0] == "*",
               "signal": int(parts[1] or 0), "secure": parts[2] not in ("", "--")}
        old = best.get(ssid)
        if not old or (net["used"], net["signal"]) > (old["used"], old["signal"]):
            best[ssid] = net
    return sorted(best.values(), key=lambda n: (not n["used"], -n["signal"]))


def row(net, saved):
    icon = BARS[min(net["signal"] * len(BARS) // 100, len(BARS) - 1)]
    if net["used"]:
        return f"<span color='{GREEN}'>{icon}</span>   <b>{escape(net['ssid'])}</b>" + note("Connected")
    tag = "Saved" if net["ssid"] in saved else "󰌾" if net["secure"] else "Open"
    return f"{icon}   {escape(net['ssid'])}" + note(tag)


def connect(net, saved):
    ssid = net["ssid"]
    if ssid in saved:
        ok, out = nmcli("-w", "25", "connection", "up", "id", ssid)
    else:
        args = ["-w", "25", "device", "wifi", "connect", ssid]
        if net["secure"]:
            password = ask_password("Wi-Fi", f"Password for {escape(ssid)}")
            if password is None:
                return
            args += ["password", password]
        ok, out = nmcli(*args)
        if not ok:
            nmcli("connection", "delete", "id", ssid)  # don't keep a broken profile
    if ok:
        notify("Wi-Fi", f"Connected to {ssid}", "network-wireless")
    else:
        why = "wrong password?" if "ecret" in out or "802-11-wireless-security" in out else out.splitlines()[-1] if out else ""
        notify("Wi-Fi", f"Couldn't connect to {ssid}\n{why}", "network-wireless-offline")


def main():
    rescan = "no"
    subprocess.Popen(["nmcli", "device", "wifi", "rescan"],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    while True:
        if not wifi_on():
            rows = ["󰖩   Turn Wi-Fi on", muted("󰒓   Network settings")]
            i, _ = pick(rows, "Wi-Fi", "Wi-Fi is off")
            if i == 0:
                nmcli("radio", "wifi", "on")
                time.sleep(3)  # give it a moment to find networks
                rescan = "auto"
                continue
            if i == 1:
                subprocess.Popen(["nm-connection-editor"])
            return

        nets = networks(rescan)
        rescan = "no"
        saved = saved_networks()
        actions = [("scan", "󰑓   Scan again"), ("off", "󰖪   Turn Wi-Fi off"),
                   ("settings", "󰒓   Network settings")]
        rows = [row(n, saved) for n in nets] + [muted(text) for _, text in actions]
        i, code = pick(rows, "Wi-Fi", HELP if nets else "No networks found yet", "Search networks")
        if i is None:
            return

        if i < len(nets):
            net = nets[i]
            if code == FORGET:
                if net["ssid"] in saved:
                    nmcli("connection", "delete", "id", net["ssid"])
                    notify("Wi-Fi", f"Forgot {net['ssid']}", "network-wireless")
                continue
            if net["used"]:
                dev = wifi_device()
                if dev:
                    nmcli("device", "disconnect", dev)
                notify("Wi-Fi", f"Disconnected from {net['ssid']}", "network-wireless-offline")
            else:
                connect(net, saved)
            return

        action = actions[i - len(nets)][0]
        if action == "scan":
            rescan = "yes"   # blocks a few seconds, then the list reopens
            continue
        if action == "off":
            nmcli("radio", "wifi", "off")
        elif action == "settings":
            subprocess.Popen(["nm-connection-editor"])
        return


if __name__ == "__main__":
    main()
