"""tmux side: find the agents' panes, read their screens, spot a dialog's numbered choices."""
import os
import re
import shlex
import subprocess
from collections import Counter

AGENTS = ("claude", "codex")
BIN = ["tmux"]        # tests point this at a throwaway server: ["tmux", "-L", "test"]
FIELDS = ("id", "cmd", "tag", "state", "path", "where")
FORMAT = "\t".join(("#{pane_id}", "#{pane_current_command}", "#{@agent_name}",
                    "#{@agent_state}", "#{pane_current_path}",
                    "#{session_name}:#{window_index}"))


def tmux(*args, input=None):
    try:
        return subprocess.run([*BIN, *args], input=input, capture_output=True,
                              text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def server():
    """The tmux server's pid. Pane ids (%0, %1 ...) start over when tmux restarts."""
    return tmux("list-sessions", "-F", "#{pid}").partition("\n")[0].strip()


def panes():
    """Panes where claude or codex is running right now. Only the foreground command
    counts: a stale tag on a shell must never get typed into."""
    found = []
    for line in tmux("list-panes", "-a", "-F", FORMAT).splitlines():
        p = dict(zip(FIELDS, line.split("\t")))
        if p.get("cmd") in AGENTS:
            p["agent"] = p["cmd"]
            p["state"] = p.get("state") or "idle"
            found.append(p)
    return found


def pane(pane_id):
    """One pane's FIELDS, whatever runs in it; None once it's gone."""
    out = tmux("display-message", "-p", "-t", pane_id, FORMAT).rstrip("\n")
    p = dict(zip(FIELDS, out.split("\t")))
    return p if p.get("id") == pane_id else None


# ---- new windows ---------------------------------------------------------------

NEW = "#{pane_id}\t#{session_name}:#{window_index}"


def new_window(path, name, session="main"):
    """A new shell window in `path`, in `session` if it exists, else in the session used
    last. Starts tmux if it isn't running. Returns (pane id, "session:window"), or
    (None, why not)."""
    have = []
    for line in tmux("list-sessions", "-F",
                     "#{session_name}\t#{session_attached}\t#{session_activity}").splitlines():
        sname, attached, activity = (line.split("\t") + ["", ""])[:3]
        have.append((attached not in ("", "0"), int(activity or 0), sname))
    if not have:
        out = start_server(session, path, name)
    else:
        target = session if session in [s[2] for s in have] else max(have)[2]
        out = tmux("new-window", "-d", "-P", "-F", NEW, "-t", f"={target}:", "-c", path,
                   "-n", name)
    pane_id, _, where = out.strip().rpartition("\n")[2].partition("\t")
    return (pane_id, where) if pane_id.startswith("%") else (None, out.strip() or "tmux failed")


def start_server(session, path, name):
    """Start tmux with `session`, the way a terminal does: through an interactive shell,
    so the server gets the full PATH ~/.zshrc sets up (TMUX is set while it loads, which
    skips its auto-attach). It runs in a systemd scope of its own: started from the
    bridge's service, it would otherwise be killed whenever the bridge restarts."""
    cmd = shlex.join([*BIN, "new-session", "-d", "-P", "-F", NEW, "-s", session, "-c", path,
                      "-n", name])
    try:
        r = subprocess.run(["systemd-run", "--user", "--scope", "--quiet", "--collect",
                            "--description=tmux, started by tg-bridge",
                            "env", "TMUX=starting", os.environ.get("SHELL") or "/bin/sh",
                            "-ic", f"unset TMUX; exec {cmd}"],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True,
                           timeout=30, cwd=path)
    except (OSError, subprocess.SubprocessError) as e:
        return f"couldn't start tmux: {e}"
    return r.stdout if "\t" in r.stdout else (r.stderr.strip() or "couldn't start tmux")


def screen(pane, history=0):
    """What the pane shows (plus `history` lines above it), trailing blanks dropped."""
    out = tmux("capture-pane", "-p", "-J", "-t", pane, *(("-S", f"-{history}") if history else ()))
    return "\n".join(l.rstrip() for l in out.rstrip().splitlines())


# ---- dialogs ---------------------------------------------------------------
# Claude and Codex both draw approvals and questions as a numbered list at the
# bottom of the screen ("❯ 1. Yes"). Pressing a choice from Telegram is only
# allowed while the same list, and the command it's about, are still on screen.

BORDERS = " \t│┃║|"
CURSOR = re.compile(r"^[❯›>▶→●○◉]\s*")
OPTION = re.compile(r"^(\d{1,2})[.)]\s+(\S.*)$")


def _clean(line):
    return CURSOR.sub("", line.strip(BORDERS)).strip(BORDERS)


def dialog(text):
    """The dialog at the bottom of a screen: (its numbered choices ["1. Yes", ...], the
    line just above them, usually the question). ([], "") if there's none."""
    lines = [l for l in map(_clean, text.splitlines()) if l][-30:]
    nums = [(i, m) for i, m in ((i, OPTION.match(l)) for i, l in enumerate(lines)) if m]
    if not nums or nums[-1][0] < len(lines) - 10:    # a dialog sits at the very bottom
        return [], ""
    ones = [i for i, m in nums if m.group(1) == "1"]
    if not ones:
        return [], ""
    out = []
    for i, m in nums:
        if i >= ones[-1] and int(m.group(1)) == len(out) + 1:
            out.append(f"{m.group(1)}. {m.group(2)}")
    if len(out) < 2:
        return [], ""
    return out, lines[ones[-1] - 1] if ones[-1] > 0 else ""


def choices(text):
    return dialog(text)[0]


def squash(text):
    """Text without whitespace or box drawing, so wrapping and borders don't matter."""
    return re.sub(r"[\s│┃║|─━═╭╮╰╯┌┐└┘]+", "", text)


def shows(text, anchor):
    """Is `anchor` (say, the command being approved) visible in the screen text?"""
    a = squash(anchor)[:40]
    return not a or a in squash(text)


def dialog_is(pane, opts, anchor):
    """Is this exact dialog (same choices, same subject) still on the pane's screen?"""
    text = screen(pane)
    return bool(opts) and choices(text) == opts and shows(text, anchor)


SELECTED = re.compile(r"^[❯›>▶→]\s*\d{1,2}[.)]\s")


def menu(text):
    """dialog(), but only one the agent is waiting on right now: one of its choices has
    the cursor ("❯ 2. Sonnet") and it covers the input box. A numbered list in a reply,
    or your own prompt echoed as "❯ 1. ...", has the input box under it."""
    opts, prompt = dialog(text)
    tail = [l.strip(BORDERS) for l in text.splitlines() if l.strip()][-30:]
    if opts and any(SELECTED.match(l) for l in tail) and not has_input(text):
        return opts, prompt
    return [], ""


POINTER = re.compile(r"^[ │┃║|]*[❯›>▶→]\s+(?=\S)")


def select_list(text):
    """An unnumbered list the agent waits on, like Claude's folder trust check:
        ❯ No, exit
          Yes, I trust this folder
    Returns (labels, index of the one with the cursor, the line above the list), or None.
    The cursor must be on one of them and the input box hidden; numbered lists are
    dialog()'s. Their rows start in the same column as the text after the cursor."""
    if has_input(text):
        return None
    lines = text.splitlines()
    rows = [i for i, l in enumerate(lines) if l.strip()][-15:]
    at = next((i for i in reversed(rows) if POINTER.match(lines[i])), None)
    if at is None or OPTION.match(lines[at][POINTER.match(lines[at]).end():]):
        return None
    col = POINTER.match(lines[at]).end()

    def label(i):
        """Row i's text if it's the cursor row or a sibling (same column), else None."""
        if not 0 <= i < len(lines):
            return None
        line = lines[i]
        if i != at and (POINTER.match(line) or line[:col].strip(" │┃║|")
                        or len(line) <= col or line[col] == " "):
            return None
        return line[col:].strip(BORDERS) or None

    first = at
    while label(first - 1):
        first -= 1
    last = at
    while label(last + 1):
        last += 1
    labels = [label(i) for i in range(first, last + 1)]
    if len(labels) < 2:
        return None
    above = next((_clean(lines[i]) for i in range(first - 1, -1, -1) if _clean(lines[i])), "")
    return labels, at - first, above


# ---- busy, and what a command printed ------------------------------------------
# Mid-turn status lines: Claude's spinner "✻ Thinking… (12s · ↓ 1.2k tokens)",
# Codex's "• Working (5s • esc to interrupt)".
WORKING = re.compile(r"…\s*\(\d+[hms]\b|\(\d+[hms]\b[^)]*esc to interrupt\)", re.I)
GLYPHS = re.compile(r"^[\s⎿•■└├│┃║❯›●◐◑◒◓○◉✻✶✳✢✽·*▐▛▜▝▘▌█▀▄▔▁─━═╭╮╰╯]+")


def tidy(line):
    """A screen line for a phone: no leading glyphs or borders, single spaces.
    "" if it was only decoration."""
    line = re.sub(r"\s+", " ", GLYPHS.sub("", line)).strip(" │┃║▔▁─━═╮╯")
    return line if re.search(r"\w", line) else ""


def busy(text):
    """The agent's "working" status line while it's in the middle of a turn, else ""."""
    lines = [l for l in text.splitlines() if l.strip()][-25:]
    return next((tidy(l) for l in reversed(lines) if WORKING.search(l)), "")


RULE = re.compile(r"^[─━]{10,}")


def input_line(lines):
    """Index of the agent's input line, None while a menu or some other screen covers
    it: Claude's "❯" sits right under a rule, Codex's "›" just above its footer."""
    rows = [i for i, l in enumerate(lines) if l.strip()]
    for n, k in enumerate(range(len(rows) - 1, max(len(rows) - 8, 0) - 1, -1)):
        line = lines[rows[k]].strip(BORDERS)
        if SELECTED.match(line):
            continue
        if line[:1] == "❯" and k > 0 and RULE.match(lines[rows[k - 1]].strip()):
            return rows[k]
        if line[:1] == "›" and n < 4:
            return rows[k]
    return None


def has_input(text):
    """Is the agent back at its input box (no menu, settings panel ... on top)?"""
    return input_line(text.splitlines()) is not None


def above_input(text):
    """The screen above the agent's input box, or all of it if that isn't showing."""
    lines = text.splitlines()
    i = input_line(lines)
    return lines if i is None else lines[:i]


def news(before, after):
    """What the agent printed between two screens: the lines above its input box in
    `after` that weren't on screen `before`, tidied. Best effort, for confirmations."""
    seen = Counter(before.splitlines())
    out = []
    for line in above_input(after):
        if seen[line] > 0:
            seen[line] -= 1
        elif t := tidy(line):
            out.append(t)
    return out
