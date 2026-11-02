"""tmux side: find the agents' panes, read their screens, spot a dialog's numbered choices."""
import re
import subprocess

AGENTS = ("claude", "codex")
FIELDS = ("id", "cmd", "tag", "state", "path", "where")
FORMAT = "\t".join(("#{pane_id}", "#{pane_current_command}", "#{@agent_name}",
                    "#{@agent_state}", "#{pane_current_path}",
                    "#{session_name}:#{window_index}"))


def tmux(*args, input=None):
    try:
        return subprocess.run(["tmux", *args], input=input, capture_output=True,
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
