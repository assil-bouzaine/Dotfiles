#!/usr/bin/env python3
"""Auto-hide for waybar: the bar shows while the cursor is at the top edge.

Waybar has no hover reveal on Hyprland (its "mode": "hide" is sway-only), but
SIGUSR1 toggles it: hidden, it drops to the bottom layer, lets clicks through
and gets the `hidden` class, which style.css fades to transparent.

This daemon polls the cursor through Hyprland's request socket (no hyprctl
process every tick). Cursor touches the top edge → show; cursor leaves the
bar area → hide after a short delay. The bar stays up while a rofi card
(launcher, Wi-Fi, Bluetooth) is open, since the cursor is down in the card.
SIGUSR1 is only a toggle, so before each toggle the real state is read back
from Hyprland's layer list instead of trusting our own bookkeeping.
Waybar starts it through the hidden custom/autohide module.
"""

import fcntl
import json
import os
import socket
import subprocess
import time

RUNTIME = os.environ["XDG_RUNTIME_DIR"]
HYPR_DIR = f"{RUNTIME}/hypr"
LOCK_FILE = f"{RUNTIME}/waybar-autohide.lock"

POLL = 0.1         # seconds between cursor checks
EDGE = 1           # px from the monitor top that reveal the bar
REVEAL_DELAY = 0.1 # cursor must rest on the edge this long (stops flicker on overshoot)
BAR_AREA = 40      # px from the top that keep it shown: margin-top 4 + height 30 + slack
HIDE_DELAY = 0.5   # seconds outside the bar area before it hides


def find_socket():
    """Request socket of the live Hyprland, like connect() in workspaces.py."""
    current = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    others = sorted(
        (d for d in os.listdir(HYPR_DIR) if d != current),
        key=lambda d: os.path.getmtime(f"{HYPR_DIR}/{d}"),
        reverse=True,
    )
    for sig in ([current] if current else []) + others:
        path = f"{HYPR_DIR}/{sig}/.socket.sock"
        try:
            request(path, "j/version")
        except OSError:
            continue
        return path
    raise OSError("no running Hyprland instance")


def request(path, cmd):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
        sock.connect(path)
        sock.sendall(cmd.encode())
        out = b""
        while chunk := sock.recv(65536):
            out += chunk
    return json.loads(out)


def bar_visible(path):
    # Hidden waybar sits on the bottom layer (level 1); shown, it is on "top".
    layers = request(path, "j/layers")
    return any(
        int(level) >= 2
        for mon in layers.values()
        for level, surfaces in mon["levels"].items()
        for s in surfaces
        if s["namespace"] == "waybar"
    )


def cursor_from_top(path, monitors):
    pos = request(path, "j/cursorpos")
    x, y = pos["x"], pos["y"]
    for m in monitors:
        w, h = m["width"] / m["scale"], m["height"] / m["scale"]
        if m["x"] <= x < m["x"] + w and m["y"] <= y < m["y"] + h:
            return y - m["y"]
    return None  # between monitors / monitor list out of date


def card_open():
    return subprocess.run(["pgrep", "-x", "rofi"], capture_output=True).returncode == 0


def run():
    path = find_socket()
    monitors = request(path, "j/monitors")
    monitors_at = time.monotonic()
    shown = bar_visible(path)
    on_edge_since = None
    left_since = None

    while True:
        time.sleep(POLL)
        now = time.monotonic()
        if now - monitors_at > 5:
            monitors = request(path, "j/monitors")
            monitors_at = now

        top = cursor_from_top(path, monitors)
        if top is None:
            continue

        want = shown
        if top <= EDGE:
            on_edge_since = on_edge_since or now
            if now - on_edge_since >= REVEAL_DELAY:
                want = True
        else:
            on_edge_since = None

        if top < BAR_AREA:
            left_since = None
        else:
            left_since = left_since or now
            if shown and now - left_since >= HIDE_DELAY and not card_open():
                want = False

        if want != shown:
            shown = bar_visible(path)
            if want != shown:
                subprocess.run(["pkill", "-USR1", "-x", "waybar"])
                shown = want


def main():
    # One daemon per waybar process; only one toggles, the others wait on the
    # lock and take over if it dies.
    lock = open(LOCK_FILE, "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    while True:
        try:
            run()
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(1)  # Hyprland restarting or socket gone: retry


if __name__ == "__main__":
    main()
