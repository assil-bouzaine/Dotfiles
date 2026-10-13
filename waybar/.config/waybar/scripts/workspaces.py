#!/usr/bin/env python3
"""Workspace state for the waybar custom/ws-N modules.

Waybar's built-in hyprland/workspaces module switches workspaces with the
legacy `dispatch workspace N`, which the Lua Hyprland config rejects. So the
bar uses ten custom/ws-N modules instead (their on-click uses hl.dsp.focus).

This daemon listens to Hyprland's event socket. On every workspace or window
change it writes one JSON line per workspace to $XDG_RUNTIME_DIR/waybar-ws and
sends SIGRTMIN+8 to waybar, so each custom/ws-N re-reads its own line.
Waybar starts it through the hidden custom/ws-daemon module.

It finds the running Hyprland itself instead of trusting
HYPRLAND_INSTANCE_SIGNATURE: waybar restarted from a shell (e.g. tmux) that
outlived a Hyprland restart carries a stale one, and the bar would freeze.
"""

import fcntl
import json
import os
import socket
import subprocess
import time

RUNTIME = os.environ["XDG_RUNTIME_DIR"]
HYPR_DIR = f"{RUNTIME}/hypr"
STATE_FILE = f"{RUNTIME}/waybar-ws"
LOCK_FILE = f"{RUNTIME}/waybar-ws.lock"

WORKSPACES = range(1, 11)   # same as the SUPER + [0-9] binds
ALWAYS_SHOWN = range(1, 6)  # 6-10 only appear when they have windows or focus

# Events that can change what the bar shows
EVENTS = {
    "workspace", "workspacev2", "focusedmon", "focusedmonv2",
    "createworkspace", "createworkspacev2", "destroyworkspace", "destroyworkspacev2",
    "moveworkspace", "moveworkspacev2", "openwindow", "closewindow", "movewindow",
    "movewindowv2", "monitoradded", "monitorremoved",
}


def hyprctl(what):
    out = subprocess.run(["hyprctl", "-j", what], capture_output=True, text=True).stdout
    return json.loads(out)


def write_state():
    workspaces = {ws["id"]: ws for ws in hyprctl("workspaces")}
    monitors = hyprctl("monitors")
    focused = next((m["activeWorkspace"]["id"] for m in monitors if m["focused"]), None)
    visible = {m["activeWorkspace"]["id"] for m in monitors}

    lines = []
    for n in WORKSPACES:
        windows = workspaces[n]["windows"] if n in workspaces else 0
        if n == focused:
            cls = "active"
        elif n in visible:
            cls = "visible"
        elif windows:
            cls = "occupied"
        elif n in ALWAYS_SHOWN:
            cls = "empty"
        else:
            lines.append(json.dumps({"text": ""}))  # empty text hides the module
            continue
        tooltip = f"Workspace {n}: {windows} window{'' if windows == 1 else 's'}"
        lines.append(json.dumps({"text": str(n), "class": cls, "tooltip": tooltip}))

    tmp = STATE_FILE + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, STATE_FILE)
    subprocess.run(["pkill", "-RTMIN+8", "-x", "waybar"])


def connect():
    """Connect to the event socket of the live Hyprland instance.

    Tries the inherited signature first, then the other instance dirs, newest
    first (dead instances leave their socket file behind, so connect to tell).
    The env var is updated so hyprctl talks to the same instance.
    """
    current = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    others = sorted(
        (d for d in os.listdir(HYPR_DIR) if d != current),
        key=lambda d: os.path.getmtime(f"{HYPR_DIR}/{d}"),
        reverse=True,
    )
    for sig in ([current] if current else []) + others:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            sock.connect(f"{HYPR_DIR}/{sig}/.socket2.sock")
        except OSError:
            sock.close()
            continue
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = sig
        return sock
    raise OSError("no running Hyprland instance")


def listen():
    with connect() as sock:
        write_state()
        for line in sock.makefile():
            if line.split(">>", 1)[0] in EVENTS:
                write_state()


def main():
    # One waybar per monitor means one daemon each; only one does the work,
    # the others wait on the lock and take over if it dies.
    lock = open(LOCK_FILE, "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
    while True:
        try:
            listen()
        except (OSError, ValueError):
            pass
        time.sleep(1)  # Hyprland restarting or socket gone: retry


if __name__ == "__main__":
    main()
