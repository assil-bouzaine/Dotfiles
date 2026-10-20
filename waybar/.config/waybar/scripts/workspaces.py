#!/usr/bin/env python3
"""Workspace state for the waybar custom/ws-N modules.

Waybar's built-in hyprland/workspaces module switches workspaces with the
legacy `dispatch workspace N`, which the Lua Hyprland config rejects. So the
bar uses ten custom/ws-N modules instead (their on-click uses hl.dsp.focus).

This daemon listens to Hyprland's event socket. On every workspace or window
change it writes one JSON line per workspace to $XDG_RUNTIME_DIR/waybar-ws and
sends SIGRTMIN+8 to waybar, so each custom/ws-N re-reads its own line. The
apps on the focused workspace (real icon from the icon theme + name) go to
the slots of group/ws-apps the same way, see APP_SLOTS.
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
import warnings

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gio, GLib, Gtk  # noqa: E402

warnings.filterwarnings("ignore", category=DeprecationWarning)  # Gio.DesktopAppInfo

RUNTIME = os.environ["XDG_RUNTIME_DIR"]
HYPR_DIR = f"{RUNTIME}/hypr"
STATE_FILE = f"{RUNTIME}/waybar-ws"
LOCK_FILE = f"{RUNTIME}/waybar-ws.lock"
ICON_FILE = f"{RUNTIME}/waybar-ws-icons"

WORKSPACES = range(1, 11)   # same as the SUPER + [0-9] binds
ALWAYS_SHOWN = range(1, 6)  # 6-10 only appear when they have windows or focus

# Apps on the focused workspace: icon + name pairs in group/ws-apps, one
# image#app-N (icon file path, from ICON_FILE) and custom/app-N (name, line
# 10 + N of STATE_FILE) per slot. Empty slots hide themselves.
APP_SLOTS = 2              # only the first two apps are shown
ICON_SIZE = 64              # waybar scales it down; asks the theme for a sharp one
ICON_THEME = "breeze"       # same as gtk-icon-theme-name
FALLBACK_ICON = "application-x-executable"
IGNORED_CLASSES = {"xwaylandvideobridge"}  # invisible helper windows
DIVIDER = "<span color='#5c6370'>  │  </span>"  # @dim in style.css

_icon_theme = Gtk.IconTheme.new()
_icon_theme.set_custom_theme(ICON_THEME)
_apps = {}  # window class -> (icon path, name), looked up once per class


def app_info(cls):
    """Icon file and name for a window class, from the app's .desktop entry.

    The entry is the one whose StartupWMClass or file name matches the class
    (case-insensitive); without one, the class itself is tried as icon name.
    """
    if cls not in _apps:
        low = cls.lower()
        entry = next(
            (a for a in Gio.AppInfo.get_all()
             if low in ((a.get_startup_wm_class() or "").lower(),
                        (a.get_id() or "").lower().removesuffix(".desktop"))),
            None,
        )
        icon_name = entry.get_string("Icon") if entry else None
        name = entry.get_name() if entry else cls
        info = None
        for n in (icon_name, cls, low, FALLBACK_ICON):
            if n and os.path.isabs(n):
                path = n
                break
            if n and (info := _icon_theme.lookup_icon(n, ICON_SIZE, 0)):
                path = info.get_filename()
                break
        _apps[cls] = (path, name)
    return _apps[cls]


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

    # The apps on the focused workspace, one per app, in the order their
    # windows were opened
    apps = []
    for c in hyprctl("clients"):
        if (c["workspace"]["id"] == focused and c["mapped"] and not c["hidden"]
                and c["class"] not in IGNORED_CLASSES):
            app = app_info(c["class"])
            if app not in apps:
                apps.append(app)
    apps = apps[:APP_SLOTS]
    names = [GLib.markup_escape_text(name) for _, name in apps]
    names[:-1] = [n + DIVIDER for n in names[:-1]]  # divider before the next app's icon
    names += [""] * (APP_SLOTS - len(names))
    lines += [json.dumps({"text": n, "tooltip": False}) for n in names]

    # An empty path leaves the old icon up, a missing file hides it
    icons = [path for path, _ in apps] + ["none"] * (APP_SLOTS - len(apps))

    write(STATE_FILE, lines)
    write(ICON_FILE, icons)
    subprocess.run(["pkill", "-RTMIN+8", "-x", "waybar"])


def write(path, lines):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, path)


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
