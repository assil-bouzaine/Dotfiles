"""Starting a new agent session from the phone (/new): which folders, models and effort
levels to offer, and the command line that starts the agent.

  Folders  the ones you used last with either agent (Claude's ~/.claude.json projects,
           Codex's session files) and ~/Projects, newest first
  Models   Claude: its aliases, which always mean the newest of each family (`--model opus`
           is Opus 5.5 today). Codex: its own model list, ~/.codex/models_cache.json
  Effort   Claude: --effort. Codex has no flag for it (-c would cost it its shared
           background server), so the bridge types /model --reasoning=<level> once it's up
Everything chosen here is for that session only; your defaults stay as they are.
"""
import json
import os
import re
import shlex
import tomllib
from pathlib import Path

HOME = Path.home()
PROJECTS = HOME / "Projects"
CLAUDE_MODELS = (("opus", "Opus"), ("sonnet", "Sonnet"), ("fable", "Fable"), ("haiku", "Haiku"))
CLAUDE_EFFORTS = ("low", "medium", "high", "xhigh", "max")
CODEX_EFFORTS = ("low", "medium", "high", "xhigh", "max", "ultra")
MODEL_NAME = re.compile(r"^[A-Za-z0-9][\w.:\[\]-]{0,60}$")
# a model name typed in full: /new radar claude-opus-4-8
FULL_NAME = {"claude": re.compile(r"^claude-", re.I), "codex": re.compile(r"^(gpt-|codex-|o\d)", re.I)}
SKIP_DIRS = ("/tmp/", "/var/tmp/", "/run/")


def _json(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}


def codex_config():
    try:
        return tomllib.loads((HOME / ".codex/config.toml").read_text())
    except (OSError, ValueError):
        return {}


def codex_cache():
    """Codex's model list as its /model menu shows it: [(slug, name, levels, default level)]."""
    out = []
    for m in sorted(_json(HOME / ".codex/models_cache.json").get("models") or [],
                    key=lambda m: m.get("priority") or 99):
        if m.get("visibility") == "list" and m.get("slug"):
            levels = [l.get("effort") if isinstance(l, dict) else l
                      for l in m.get("supported_reasoning_levels") or []]
            out.append((m["slug"], m.get("display_name") or m["slug"],
                        [l for l in levels if l], m.get("default_reasoning_level")))
    return out


# ---- models and effort ------------------------------------------------------------

def models(agent):
    """([(value, label)], your default value). The value "" starts it without a flag."""
    if agent == "claude":
        default = _json(HOME / ".claude/settings.json").get("model") or ""
        out = list(CLAUDE_MODELS)
    else:
        default = codex_config().get("model") or ""
        out = [(slug, name) for slug, name, _, _ in codex_cache()]
    if default and default not in [v for v, _ in out]:
        out.insert(0, (default, default))
    if not default:
        out.insert(0, ("", "Default"))
    return out, default


def model_label(agent, value):
    if not value:
        return "Default"
    return dict(models(agent)[0]).get(value, value)


def efforts(agent, model):
    """(levels the model takes, the level it starts with if you don't pick one, if known)."""
    if agent == "claude":
        return list(CLAUDE_EFFORTS), None
    conf = codex_config()
    slug = model or conf.get("model")
    found = next((m for m in codex_cache() if m[0] == slug), None)
    levels = found[2] if found and found[2] else list(CODEX_EFFORTS[:5])
    default = conf.get("model_reasoning_effort") or (found[3] if found else None)
    return levels, default if default in levels else None


def all_efforts(agent):
    return CLAUDE_EFFORTS if agent == "claude" else CODEX_EFFORTS


def as_model(agent, word):
    """`word` as a model name (spelled the way the agent knows it), or None if it isn't
    one: a model from the menu (any case), or a full name like claude-opus-4-8."""
    known = {v.lower(): v for v, _ in models(agent)[0] if v}
    if agent == "claude":
        known.update((v, v) for v, _ in CLAUDE_MODELS)
    if word.lower() in known:
        return known[word.lower()]
    return word if FULL_NAME[agent].match(word) and MODEL_NAME.match(word) else None


def command(agent, model, effort):
    """(what to type into the new shell, what to type into the agent once it's up)."""
    if model and not MODEL_NAME.match(model):
        raise ValueError(f"that doesn't look like a model name: {model}")
    if effort and effort not in all_efforts(agent):
        raise ValueError(f"unknown effort: {effort}")
    if agent == "claude":
        args = ["claude", *(["--model", model] if model else []),
                *(["--effort", effort] if effort else [])]
        return shlex.join(args), None
    return shlex.join(["codex", *(["-m", model] if model else [])]), \
        (f"/model --reasoning={effort}" if effort else None)


def describe(agent, model, effort):
    """What was asked for, the way the agent shows it: "GPT-6-Luna low",
    "Sonnet, high effort"."""
    if agent == "claude":
        return f"{model_label(agent, model)}, {effort or 'default'} effort"
    slug = model or codex_config().get("model") or ""
    name = next((n for s, n, _, _ in codex_cache() if s == slug), slug or "Default model")
    return f"{name} {effort or efforts(agent, model)[1] or 'default effort'}"


def claude_banner(screen):
    """The model and effort a new Claude session shows under its name: "Opus 5.5 with high
    effort", or "". (Codex's status line gets cut short in a narrow window, and its
    model only shows up there a moment later: the bridge reports Codex from describe().)"""
    from .tmux import tidy
    lines = [t for t in map(tidy, screen.splitlines()) if t]
    for i, l in enumerate(lines[:-1]):
        if l.startswith("Claude Code v"):
            return lines[i + 1].split(" · ")[0]
    return ""


# ---- folders ------------------------------------------------------------------------

def recent_dirs(n=8):
    """Folders you worked in last, with either agent or in ~/Projects; ~ is always there."""
    seen = {}

    def add(path, t):
        if not path or str(path).startswith(SKIP_DIRS):
            return
        p = Path(path)
        if p.is_dir():
            seen[p] = max(seen.get(p, 0), t)

    def mtime(f):
        try:
            return f.stat().st_mtime
        except OSError:
            return 0

    for path in _json(HOME / ".claude.json").get("projects") or {}:
        transcripts = HOME / ".claude/projects" / re.sub(r"[^A-Za-z0-9]", "-", path)
        add(path, max(map(mtime, transcripts.glob("*.jsonl")), default=0))
    sessions = sorted((HOME / ".codex/sessions").glob("*/*/*/rollout-*.jsonl"), key=mtime,
                      reverse=True)
    for f in sessions[:40]:
        try:
            with open(f) as fh:
                add((json.loads(fh.readline()).get("payload") or {}).get("cwd"), mtime(f))
        except (OSError, ValueError):
            pass
    if PROJECTS.is_dir():
        for d in PROJECTS.iterdir():
            add(d, mtime(d))
    out = sorted(seen, key=seen.get, reverse=True)[:n]
    return out if HOME in out else out[:n - 1] + [HOME]


def resolve(text):
    """The folder a typed path means: ~/x, /abs/x, or a bare name looked up in ~/Projects,
    then in ~, in any case (phone keyboards capitalise). Returns (folder, None), or
    (None, where it would be created)."""
    t = text.strip().strip("\"'")
    if not t:
        return None, None
    p = Path(os.path.expanduser(t))
    tries = [p] if p.is_absolute() else [PROJECTS / t, HOME / t]
    for c in tries:
        if c.is_dir():
            return c.resolve(), None
    for c in tries:
        try:
            hit = next((d for d in c.parent.iterdir()
                        if d.name.casefold() == c.name.casefold() and d.is_dir()), None)
        except OSError:
            hit = None
        if hit:
            return hit.resolve(), None
    return None, tries[0]


def tilde(path):
    p = Path(path)
    try:
        rel = p.relative_to(HOME)
    except ValueError:
        return str(p)
    return "~" if str(rel) == "." else f"~/{rel}"


def label(path):
    """A folder as a button: a project by its name, anything else as a ~ path."""
    p = Path(path)
    if p == HOME:
        return "~ (home)"
    return p.name if p.parent == PROJECTS else tilde(p)


def window_name(path, agent):
    p = Path(path)
    return f"{'home' if p == HOME else p.name}:{agent}"
