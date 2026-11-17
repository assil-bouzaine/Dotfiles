#!/usr/bin/env python3
"""Wallpapers for the picker (shell.qml) and login. Uses awww.

    wallctl.py list       JSON: current wallpaper + every image with a thumbnail
    wallctl.py set PATH   show PATH on every screen and remember it
    wallctl.py restore    at login: show the remembered wallpaper (autostart.lua)

Images: the current theme's own wallpapers first (~/.config/theme/themes/
<theme>/backgrounds, see ~/.local/bin/theme), then yours in ~/Pictures/Wallpapers.
Thumbnails are cached in ~/.cache/wallpicker (made once per image with
ImageMagick). The choice is kept in ~/.local/state/wallpaper, and
~/.local/state/wallpaper-current is a symlink to it (the lock screen shows it).
Replaces the old 10-minute shuffle (hypr/scripts/wallpaper-cycle.sh).
"""

import hashlib
import json
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

sys.dont_write_bytecode = True

HOME = os.path.expanduser("~")
DIR = os.path.join(HOME, "Pictures", "Wallpapers")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", f"{HOME}/.cache"), "wallpicker")
STATE_HOME = os.environ.get("XDG_STATE_HOME", f"{HOME}/.local/state")
STATE = os.path.join(STATE_HOME, "wallpaper")
LINK = os.path.join(STATE_HOME, "wallpaper-current")
THEMES = os.path.join(os.environ.get("XDG_CONFIG_HOME", f"{HOME}/.config"), "theme", "themes")
EXTS = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp")


def images_in(folder):
    try:
        names = sorted(os.listdir(folder), key=str.lower)
    except OSError:
        return []
    return [os.path.join(folder, n) for n in names
            if n.lower().endswith(EXTS) and os.path.isfile(os.path.join(folder, n))]


def theme():
    """(name, title) of the current theme, or ("", "") without one."""
    try:
        with open(os.path.join(STATE_HOME, "theme", "theme.json")) as f:
            d = json.load(f)
        return d.get("name", ""), d.get("title", "")
    except (OSError, ValueError):
        return "", ""


def images():
    name, _ = theme()
    own = images_in(os.path.join(THEMES, name, "backgrounds")) if name else []
    return own + images_in(DIR)


def link(path):
    """Point ~/.local/state/wallpaper-current at the wallpaper on screen."""
    try:
        tmp = LINK + ".tmp"
        if os.path.lexists(tmp):
            os.unlink(tmp)
        os.symlink(path, tmp)
        os.replace(tmp, LINK)
    except OSError:
        pass


def thumb(path):
    st = os.stat(path)
    key = hashlib.sha1(f"{path}:{st.st_mtime_ns}:{st.st_size}".encode()).hexdigest()[:16]
    out = os.path.join(CACHE, key + ".jpg")
    if not os.path.exists(out):
        tmp = out + ".tmp.jpg"
        subprocess.run(["magick", path + "[0]", "-auto-orient", "-thumbnail", "480x270^",
                        "-gravity", "center", "-extent", "480x270", "-quality", "86", tmp],
                       capture_output=True, timeout=60)
        if os.path.exists(tmp):
            os.replace(tmp, out)
    return out if os.path.exists(out) else ""


def current():
    try:
        with open(STATE) as f:
            p = f.read().strip()
            if p:
                return p
    except OSError:
        pass
    ok = subprocess.run(["awww", "query"], capture_output=True, text=True)
    for line in ok.stdout.splitlines():
        if "image: " in line:
            return line.split("image: ", 1)[1].strip()
    return ""


def daemon():
    """Make sure awww-daemon runs (it draws the wallpaper)."""
    if subprocess.run(["awww", "query"], capture_output=True).returncode == 0:
        return True
    subprocess.Popen(["awww-daemon"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)
    for _ in range(50):
        time.sleep(0.1)
        if subprocess.run(["awww", "query"], capture_output=True).returncode == 0:
            return True
    return False


def show(path, transition):
    args = ["awww", "img", path, "--transition-type", transition]
    if transition != "none":
        args += ["--transition-duration", "0.7", "--transition-fps", "60"]
    return subprocess.run(args, capture_output=True, text=True)


def cmd_list():
    os.makedirs(CACHE, exist_ok=True)
    paths = images()
    with ThreadPoolExecutor(max_workers=2) as pool:
        thumbs = list(pool.map(thumb, paths))
    name, title = theme()
    items = [{"path": p, "name": os.path.splitext(os.path.basename(p))[0], "thumb": t,
              "theme": not p.startswith(DIR + os.sep)}
             for p, t in zip(paths, thumbs)]
    print(json.dumps({"dir": DIR, "theme": title, "current": current(), "items": items}))


def cmd_set(path):
    if not os.path.isfile(path):
        print(json.dumps({"ok": False, "error": "No such image"}))
        return
    if not daemon():
        print(json.dumps({"ok": False, "error": "awww-daemon didn't start"}))
        return
    r = show(path, "fade")
    if r.returncode == 0:
        os.makedirs(os.path.dirname(STATE), exist_ok=True)
        with open(STATE, "w") as f:
            f.write(path + "\n")
        link(path)
    print(json.dumps({"ok": r.returncode == 0, "error": r.stderr.strip()}))


def cmd_restore():
    if not daemon():
        sys.exit(1)
    path = current()
    if not os.path.isfile(path):
        paths = images()
        if not paths:
            sys.exit(0)
        path = paths[0]
    show(path, "none")
    link(path)


if __name__ == "__main__":
    a = sys.argv[1:]
    if a == ["list"]:
        cmd_list()
    elif len(a) == 2 and a[0] == "set":
        cmd_set(a[1])
    elif a == ["restore"]:
        cmd_restore()
    else:
        print(__doc__)
        sys.exit(2)
