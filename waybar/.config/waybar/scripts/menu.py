"""Shared pieces of the bar's Wi-Fi and Bluetooth menus (wifi.py, bluetooth.py).

Both are rofi -dmenu lists drawn with card.rasi. Rows are pango markup; rofi
hands back the index of the picked row, so row text never has to be parsed.
"""

import os
import shlex
import subprocess
from html import escape  # noqa: F401  (re-exported for the menus)

HERE = os.path.dirname(os.path.realpath(__file__))
CARD = f"{HERE}/card.rasi"
MAX_ROWS = 10

MUTED = "#9299a6"   # same as @muted in card.rasi
GREEN = "#00ff99"

FORGET = 10         # rofi exit code of kb-custom-1 (Shift + Delete)


def muted(text):
    return f"<span color='{MUTED}'>{text}</span>"


def note(text):
    """Small grey text after a row's name."""
    return f"   <span color='{MUTED}' size='small'>{text}</span>"


def run(*cmd, timeout=30):
    """Run a command, return (ok, output). Never raises."""
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode == 0, (p.stdout + p.stderr).strip()
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, str(e)


def notify(title, body="", icon="dialog-information"):
    subprocess.run(["notify-send", "-t", "4000", "-i", icon, title, body])


def pick(rows, prompt, mesg=None, placeholder="Search"):
    """Show rows, return (index, exit code). Index is None when dismissed."""
    cmd = [
        "rofi", "-dmenu", "-i", "-markup-rows", "-no-custom", "-format", "i",
        "-theme", CARD, "-p", prompt, "-l", str(min(len(rows), MAX_ROWS)),
        "-theme-str", f'entry {{ placeholder: "{placeholder}"; }}',
        "-kb-delete-entry", "", "-kb-custom-1", "Shift+Delete",
    ]
    if mesg:
        cmd += ["-mesg", mesg]
    cmd += shlex.split(os.environ.get("BAR_MENU_ROFI_ARGS", ""))  # for testing
    p = subprocess.run(cmd, input="\n".join(rows), capture_output=True, text=True)
    out = p.stdout.strip()
    if p.returncode in (0, FORGET) and out.lstrip("-").isdigit() and int(out) >= 0:
        return int(out), p.returncode
    return None, p.returncode


def ask_password(prompt, mesg):
    """A card with only a hidden text field. Returns the text or None."""
    cmd = [
        "rofi", "-dmenu", "-password", "-theme", CARD, "-p", prompt, "-mesg", mesg,
        "-theme-str", 'listview { enabled: false; } entry { placeholder: "Password"; }',
    ]
    cmd += shlex.split(os.environ.get("BAR_MENU_ROFI_ARGS", ""))
    p = subprocess.run(cmd, input="", capture_output=True, text=True)
    text = p.stdout.rstrip("\n")
    return text if p.returncode == 0 and text else None
