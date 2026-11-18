#!/usr/bin/env python3
"""Your own vim / tmux shortcuts as JSON for KeysCard.qml (Learn page).

    keymaps.py vim    ->  ~/.vimrc mappings, described by the comment line above each
    keymaps.py tmux   ->  ~/.tmux.conf bindings, described by their -N note

Prints {"binds": [{keys, combo, description, group, sep}]}, the same shape as
hypr/scripts/keybinds.lua --json. Each chip in `keys` is one key press; `sep`
is "" because these are sequences (press one, then the next), not chords.
Runs of bindings that differ only by a digit (<leader>1..9, M-1..9) become one
row. Reads the config on every call, so edits show up the next time the card opens.
"""
import json
import os
import re
import shlex
import sys

HOME = os.path.expanduser("~")


def collapse_digits(binds):
    """<leader>1 .. <leader>9 / M-1 .. M-9 with matching notes -> one "1…9" row."""
    out = []
    for b in binds:
        m = re.match(r"^(.*?)(\d)$", b["keys"][-1])
        prev = out[-1] if out else None
        if m and prev and prev.get("_stem") == (b["group"], tuple(b["keys"][:-1]), m.group(1)) \
                and int(m.group(2)) == prev["_last"] + 1:
            prev["_last"] = int(m.group(2))
            first = prev["_first"]
            prev["keys"][-1] = "%s%d…%d" % (m.group(1), first, prev["_last"])
            prev["description"] = re.sub(r"\b%d(–\d)?\b" % first, "%d–%d" % (first, prev["_last"]),
                                         prev["description"], count=1)
            prev["combo"] = " ".join(prev["keys"])
            continue
        if m:
            b["_stem"] = (b["group"], tuple(b["keys"][:-1]), m.group(1))
            b["_first"] = b["_last"] = int(m.group(2))
        out.append(b)
    for b in out:
        for k in ("_stem", "_first", "_last"):
            b.pop(k, None)
    return out


# ── vim ──────────────────────────────────────────────────────────────────────

MAP_RE = re.compile(r"^\s*([nvxsoilct]?)(?:nore)?map!?\s+(.*)$")
MODES = {"": "normal", "n": "normal", "v": "visual", "x": "visual", "s": "select",
         "o": "operator", "i": "insert", "l": "insert", "c": "command line", "t": "terminal"}
SPECIAL = {"cr": "Enter", "esc": "Esc", "space": "Space", "tab": "Tab", "bs": "Backspace",
           "up": "↑", "down": "↓", "left": "←", "right": "→", "bar": "|", "bslash": "\\",
           "lt": "<", "del": "Del", "home": "Home", "end": "End"}
MODS = {"c": "Ctrl", "s": "Shift", "a": "Alt", "m": "Alt", "d": "Cmd"}


def vim_key(token, leader):
    if not (token.startswith("<") and token.endswith(">") and len(token) > 2):
        return token
    inner = token[1:-1]
    low = inner.lower()
    if low == "leader":
        return leader
    if low == "localleader":
        return leader
    parts = inner.split("-")
    if len(parts) > 1 and all(p.lower() in MODS for p in parts[:-1]):
        key = parts[-1]
        key = SPECIAL.get(key.lower(), key.upper() if len(key) == 1 else key)
        return "+".join([MODS[p.lower()] for p in parts[:-1]] + [key])
    return SPECIAL.get(low, inner)


def pretty_leader(value):
    return {" ": "Space", "\\": "\\", ",": ","}.get(value, value or "\\")


def section_name(line):
    text = line.lstrip('"').strip()
    text = re.sub(r"^[─—=\-\s]+|[─—=\-\s]+$", "", text)
    if not text or len(text) > 40:
        return None
    if text.isupper():
        text = text.capitalize()
    return GROUPS.get(text, text)


# Friendlier names for the .vimrc's section banners
GROUPS = {"Key mappings": "General", "Fzf.vim configuration": "FZF search",
          "Harpoon-lite": "Harpoon"}


def vim_binds(path):
    with open(path) as f:
        lines = f.read().split("\n")
    leader = "\\"
    for line in lines:
        m = re.match(r"""^\s*let\s+mapleader\s*=\s*(["'])(.*?)\1""", line)
        if m:
            leader = pretty_leader(m.group(2))
    binds = []
    group = "General"
    for i, line in enumerate(lines):
        stripped = line.strip()
        # "=====" banners put the title on the next line; "── Title ──" inline
        if stripped.startswith('"') and "──" in stripped:
            name = section_name(stripped)
            if name:
                group = name
            continue
        banner = r'^"\s*={6,}'
        if re.match(banner, stripped):
            # the title sits between two banner lines
            if i + 2 < len(lines) and re.match(banner, lines[i + 2].strip()):
                name = section_name(lines[i + 1])
                if name:
                    group = name
            continue
        m = MAP_RE.match(line)
        if not m:
            continue
        mode = MODES.get(m.group(1), "normal")
        rest = m.group(2)
        while True:   # drop <buffer> <silent> <expr> <nowait> ...
            a = re.match(r"^<(buffer|silent|expr|nowait|unique|script|special)>\s*", rest, re.I)
            if not a:
                break
            rest = rest[a.end():]
        lhs = rest.split(None, 1)[0] if rest.split() else ""
        if not lhs:
            continue
        # description: the last comment line directly above (a "  " comment
        # inside the mapping's block counts too)
        desc = ""
        j = i - 1
        if j >= 0 and lines[j].strip().startswith('"'):
            desc = lines[j].strip().lstrip('"').strip()
        desc = re.sub(r"^[^=]{1,24}\s=\s", "", desc)          # "Space + f = find files"
        desc = re.sub(r"\s*\([^)]*\)\s*$", "", desc)            # trailing "(not <Leader>fh: ...)"
        desc = re.sub(r"^Map\s+\S+\s+to\s+", "", desc)          # "Map 'jj' to Escape ..."
        if not desc:
            desc = rest.split(None, 1)[1].strip() if len(rest.split(None, 1)) > 1 else lhs
        if re.match(r"^[a-z][a-z]", desc):   # not "j moves ...": that's the key
            desc = desc[:1].upper() + desc[1:]
        if mode != "normal" and mode not in desc.lower():
            desc += " (%s mode)" % mode
        keys = [vim_key(t, leader) for t in re.findall(r"<[^<>]+>|.", lhs)]
        binds.append({"keys": keys, "combo": " ".join(keys), "description": desc,
                      "group": group, "sep": ""})
    return collapse_digits(binds)


# ── tmux ─────────────────────────────────────────────────────────────────────

def tmux_key(key):
    mods = []
    while len(key) > 2 and key[1] == "-" and key[0] in "CMS":
        mods.append({"C": "Ctrl", "M": "Alt", "S": "Shift"}[key[0]])
        key = key[2:]
    if mods and len(key) == 1:
        key = key.upper()
    return "+".join(mods + [key])


def tmux_binds(path):
    with open(path) as f:
        text = f.read().replace("\\\n", " ")
    prefix = "Ctrl+B"
    rows = []
    for line in text.split("\n"):
        s = line.strip()
        m = re.match(r"^set(-option)?\s+(-\w+\s+)*prefix\s+(\S+)", s)
        if m:
            prefix = tmux_key(m.group(3))
            continue
        if not re.match(r"^bind(-key)?\s", s):
            continue
        try:
            args = shlex.split(s, comments=False)[1:]
        except ValueError:
            continue
        table, note, key = "prefix", "", None
        while args:
            a = args.pop(0)
            if a == "-n":
                table = "root"
            elif a == "-T" and args:
                table = args.pop(0)
            elif a == "-N" and args:
                note = args.pop(0)
            elif a.startswith("-") and len(a) > 1 and key is None and a not in ("-",):
                continue   # -r and friends
            else:
                key = a
                break
        if key is None:
            continue
        rows.append((table, key, note or " ".join(args)))
    groups = [("prefix", "After the prefix (%s)" % prefix, [prefix]),
              ("root", "No prefix", []),
              ("copy-mode-vi", "Copy mode (vi keys)", []),
              ("copy-mode", "Copy mode", [])]
    binds = []
    for table, title, lead in groups:
        for t, key, note in rows:
            if t == table:
                keys = lead + [tmux_key(key)]
                binds.append({"keys": keys, "combo": " ".join(keys),
                              "description": note,
                              "group": title, "sep": ""})
    known = {g[0] for g in groups}
    for t, key, note in rows:   # any other key table, last
        if t not in known:
            binds.append({"keys": [tmux_key(key)], "combo": key, "description": note,
                          "group": "Table " + t, "sep": ""})
    return collapse_digits(binds)


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if which == "vim":
            binds = vim_binds(os.path.join(HOME, ".vimrc"))
        elif which == "tmux":
            binds = tmux_binds(os.path.join(HOME, ".tmux.conf"))
        else:
            sys.exit("usage: keymaps.py vim|tmux")
    except OSError as e:
        sys.exit("Couldn't read %s: %s" % (e.filename, e.strerror))
    json.dump({"binds": binds}, sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
