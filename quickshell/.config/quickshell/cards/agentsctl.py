#!/usr/bin/env python3
"""Back end of the agents card (AgentsCard.qml) and the bar's robot icon.

    agentsctl.py limits [--refresh]   plan + limit windows per agent (JSON)
    agentsctl.py stats                token / prompt / session counts (JSON)
    agentsctl.py bar                  waybar JSON for the robot icon (no network)
    agentsctl.py launch <claude|codex> [prompt]   start an agent in a new tmux window, in ~
    agentsctl.py login <claude|codex>             sign in again, the same way

Modelled on Omarchy 4.5's agents panel (MIT, github.com/basecamp/omarchy,
shell/plugins/agents). Limits come from agent-notify's fetchers
(~/.local/lib/agent-notify/agentnotify/limits.py: Anthropic's OAuth usage
endpoint and ChatGPT's wham/usage, asked with the CLIs' own sign-ins) and are
cached for a minute. Stats are read from Claude Code's transcripts
(~/.claude/projects) and Codex's rollouts (~/.codex/sessions) of the last
8 days; only the bytes added since the last run are read (cache in
~/.cache/agent-usage/panel-stats.json). Tokens are what was sent and
written fresh: input + cache writes + output, without cache reads, which
would dwarf everything else.
"""

import base64
import json
import os
import shlex
import subprocess
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path

sys.dont_write_bytecode = True
HOME = Path.home()
sys.path.insert(0, str(HOME / ".local/lib/agent-notify"))

CACHE = HOME / ".cache/agent-usage"
LIMITS_CACHE = CACHE / "panel-limits.json"
STATS_CACHE = CACHE / "panel-stats.json"
LIMITS_TTL = 60
DAYS = 8

AGENTS = {
    "claude": {"name": "Claude Code", "cmd": "claude", "home": HOME / ".claude"},
    "codex": {"name": "Codex", "cmd": "codex", "home": HOME / ".codex"},
}
WINDOW_LABELS = {"5h": "Session", "weekly": "Weekly"}


def out(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(obj))
    os.replace(tmp, path)


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def installed(agent):
    a = AGENTS[agent]
    return a["home"].exists() or any(
        (Path(d) / a["cmd"]).exists() for d in os.environ.get("PATH", "").split(":"))


# ── plans ─────────────────────────────────────────────────────────────────

def claude_plan():
    o = read_json(HOME / ".claude/.credentials.json", {}).get("claudeAiOauth") or {}
    kind = (o.get("subscriptionType") or "").lower()
    tier = (o.get("rateLimitTier") or "").lower()
    if kind == "max":
        return "Max 20x" if "20x" in tier else "Max 5x" if "5x" in tier else "Max"
    return kind.capitalize() if kind else ""


def codex_plan():
    tok = (read_json(HOME / ".codex/auth.json", {}).get("tokens") or {}).get("id_token", "")
    try:
        part = tok.split(".")[1]
        part += "=" * (-len(part) % 4)
        claims = json.loads(base64.urlsafe_b64decode(part))
        plan = claims.get("https://api.openai.com/auth", {}).get("chatgpt_plan_type", "")
    except (IndexError, ValueError):
        return ""
    return {"pro": "Pro", "plus": "Plus", "team": "Business", "free": "Free"}.get(plan, plan.capitalize())


PLANS = {"claude": claude_plan, "codex": codex_plan}


# ── limits ────────────────────────────────────────────────────────────────

def fetch_limits():
    from agentnotify import limits as L
    agents = []
    for key in ("claude", "codex"):
        if not installed(key):
            continue
        try:
            u = L.FETCH[key]()
        except Exception as e:          # never let one agent break the card
            u = L.Usage(key, error=str(e))
        agents.append({
            "id": key, "name": AGENTS[key]["name"], "plan": PLANS[key](),
            "windows": [{"key": w.key, "label": WINDOW_LABELS.get(w.key, w.label.capitalize()),
                         "percent": round(w.percent, 1), "resets_at": w.resets_at} for w in u.windows],
            "error": u.error, "auth_error": u.auth_error,
        })
    return {"fetched_at": time.time(), "agents": agents}


def limits(refresh=False):
    cached = read_json(LIMITS_CACHE, None)
    if not refresh and cached and time.time() - cached.get("fetched_at", 0) < LIMITS_TTL:
        return cached
    fresh = fetch_limits()
    # A failed check keeps the last good windows, marked stale.
    old = {a["id"]: a for a in (cached or {}).get("agents", [])}
    for a in fresh["agents"]:
        prev = old.get(a["id"])
        if a["error"] and not a["windows"] and prev and prev.get("windows"):
            a["windows"] = prev["windows"]
            a["stale_since"] = prev.get("checked_at", cached.get("fetched_at"))
        a["checked_at"] = fresh["fetched_at"] if not a["error"] else a.get("stale_since", 0)
    write_json(LIMITS_CACHE, fresh)
    return fresh


# ── stats ─────────────────────────────────────────────────────────────────

def local_day(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().date().isoformat()
    except (ValueError, AttributeError):
        return None


def bump(entry, day, tokens=0, prompts=0, model=None, session=None):
    d = entry["days"].setdefault(day, {"tokens": 0, "prompts": 0, "models": {}, "sessions": []})
    d["tokens"] += tokens
    d["prompts"] += prompts
    if model and tokens:
        d["models"][model] = d["models"].get(model, 0) + tokens
    if session and session not in d["sessions"]:
        d["sessions"].append(session)


def is_prompt(rec):
    if rec.get("isMeta") or rec.get("isSidechain") or rec.get("isCompactSummary"):
        return False
    c = (rec.get("message") or {}).get("content")
    if isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return False
        c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    if not isinstance(c, str) or not c.strip():
        return False
    return not c.lstrip().startswith(("<command-", "<local-command", "Caveat:", "<task-notification", "<bash-"))


def scan_claude(line, entry):
    if b'"usage"' not in line and b'"type":"user"' not in line:
        return
    rec = json.loads(line)
    day = local_day(rec.get("timestamp", ""))
    if not day:
        return
    sid = rec.get("sessionId")
    if rec.get("type") == "assistant":
        msg = rec.get("message") or {}
        u = msg.get("usage") or {}
        mid = f'{msg.get("id")}:{rec.get("requestId")}'
        model = msg.get("model") or ""
        if not u or mid == entry.get("last_id") or model.startswith("<"):
            return
        entry["last_id"] = mid      # one reply is written once per content block
        tok = (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0) + (u.get("output_tokens") or 0)
        bump(entry, day, tokens=tok, model=model, session=sid)
    elif rec.get("type") == "user" and is_prompt(rec):
        bump(entry, day, prompts=1, session=sid)


def scan_codex(line, entry, path):
    if b'"token_count"' not in line and b'"UserMessage"' not in line and b'"turn_context"' not in line:
        return
    rec = json.loads(line)
    p = rec.get("payload") or {}
    if rec.get("type") == "turn_context":
        entry["model"] = p.get("model") or entry.get("model")
        return
    day = local_day(rec.get("timestamp", ""))
    if not day:
        return
    sid = path.stem
    if p.get("type") == "token_count":
        u = ((p.get("info") or {}).get("last_token_usage")) or {}
        if not u:
            return
        tok = max(0, (u.get("input_tokens") or 0) - (u.get("cached_input_tokens") or 0)) + (u.get("output_tokens") or 0)
        bump(entry, day, tokens=tok, model=entry.get("model"), session=sid)
    elif p.get("type") == "item_completed" and (p.get("item") or {}).get("type") == "UserMessage":
        bump(entry, day, prompts=1, session=sid)


def scan_file(path, entry, kind):
    st = path.stat()
    if st.st_size < entry.get("offset", 0):
        entry.clear()
    entry.setdefault("days", {})
    off = entry.get("offset", 0)
    if st.st_size == off:
        return
    with open(path, "rb") as f:
        f.seek(off)
        data = f.read()
    end = data.rfind(b"\n") + 1          # only whole lines; the rest next time
    for line in data[:end].splitlines():
        try:
            if kind == "claude":
                scan_claude(line, entry)
            else:
                scan_codex(line, entry, path)
        except (ValueError, TypeError, AttributeError):
            continue
    entry["offset"] = off + end


def pretty_model(m):
    if m.startswith("claude-"):
        parts = m[7:].split("-")
        words = [p for p in parts if not p.isdigit() or len(p) < 3]
        name = words[0].capitalize() if words else m
        nums = [p for p in words[1:] if p.isdigit()]
        return f"{name} {'.'.join(nums)}".strip()
    if m.startswith("gpt-"):
        bits = m.split("-")
        return "GPT-" + bits[1] + "".join(" " + b.capitalize() for b in bits[2:])
    return m


def stats():
    cache = read_json(STATS_CACHE, {"files": {}})
    files = cache.setdefault("files", {})
    cutoff = time.time() - DAYS * 86400
    seen = set()
    roots = [("claude", HOME / ".claude/projects"), ("codex", HOME / ".codex/sessions")]
    for kind, root in roots:
        if not root.exists():
            continue
        for path in root.rglob("*.jsonl"):
            try:
                if path.stat().st_mtime < cutoff:
                    continue
            except OSError:
                continue
            key = str(path)
            seen.add(key)
            entry = files.setdefault(key, {"kind": kind})
            try:
                scan_file(path, entry, kind)
            except OSError:
                pass
    for key in list(files):
        if key not in seen:
            del files[key]
    write_json(STATS_CACHE, cache)

    today = date.today()
    week = {(today - timedelta(days=i)).isoformat() for i in range(7)}
    per_day, models = {}, {}
    prompts_today, sessions_today = 0, set()
    for entry in files.values():
        for day, d in entry.get("days", {}).items():
            if day not in week:
                continue
            per_day[day] = per_day.get(day, 0) + d["tokens"]
            for m, t in d["models"].items():
                models[m] = models.get(m, 0) + t
            if day == today.isoformat():
                prompts_today += d["prompts"]
                sessions_today.update(d["sessions"])
    busiest = max(per_day, key=per_day.get) if per_day else None
    top = max(models, key=models.get) if models else None
    return {
        "week_tokens": sum(per_day.values()),
        "today_tokens": per_day.get(today.isoformat(), 0),
        "top_model": pretty_model(top) if top else "",
        "busiest_day": date.fromisoformat(busiest).strftime("%A") if busiest and per_day[busiest] else "",
        "prompts_today": prompts_today,
        "sessions_today": len(sessions_today),
    }


# ── bar + launching ───────────────────────────────────────────────────────

def bar():
    data = read_json(LIMITS_CACHE, None)
    if not data or time.time() - data.get("fetched_at", 0) > 15 * 60:
        try:
            data = limits()
        except Exception:
            data = data or {"agents": []}
    lines, worst = [], 0
    for a in data.get("agents", []):
        parts = [f'{w["label"]} {w["percent"]:.0f}%' for w in a.get("windows", [])]
        worst = max([worst] + [w["percent"] for w in a.get("windows", [])])
        lines.append(f'{a["name"]}: ' + (" · ".join(parts) if parts else (a.get("error") or "no data")))
    cls = "spent" if worst >= 100 else "high" if worst >= 80 else "ok"
    out({"text": "󰚩", "class": cls,
         "tooltip": "\n".join(lines + ["Click: agents card · Right-click: start Claude Code"])})


SESSION = "main"     # every kitty attaches to it (~/.zshrc)


def sh(*cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.returncode == 0, p.stdout.strip()


def terminal_for_tmux():
    """Hyprland address of the kitty window showing the tmux session, or None."""
    ok, clients = sh("tmux", "list-clients", "-t", SESSION, "-F", "#{client_pid}")
    if not ok or not clients:
        return None
    ok, js = sh("hyprctl", "clients", "-j")
    windows = {w["pid"]: w["address"] for w in json.loads(js or "[]")} if ok else {}
    for pid in clients.split():
        pid = int(pid)
        while pid > 1:                          # walk up: tmux client -> zsh -> kitty
            if pid in windows:
                return windows[pid]
            try:
                with open(f"/proc/{pid}/stat") as f:
                    pid = int(f.read().rsplit(")", 1)[1].split()[1])
            except (OSError, ValueError, IndexError):
                break
    return None


def run_in_tmux(command):
    """Start `command` in a new window of the tmux session, always in ~, and
    bring a terminal showing it to the front (or open one)."""
    home = str(HOME)
    if not sh("tmux", "has-session", "-t", SESSION)[0]:
        sh("tmux", "new-session", "-d", "-s", SESSION, "-c", home)
    ok, pane = sh("tmux", "new-window", "-t", f"{SESSION}:", "-c", home, "-P", "-F", "#{pane_id}")
    if not ok:
        return subprocess.Popen(["kitty", "--directory", home, "sh", "-c", command], start_new_session=True)
    # Typed into the window's shell, so you're back at a prompt when the agent exits.
    sh("tmux", "send-keys", "-t", pane, "-l", command)
    sh("tmux", "send-keys", "-t", pane, "Enter")
    addr = terminal_for_tmux()
    if addr:
        sh("hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{addr}" }})')
    else:   # no terminal open: a new kitty attaches to the session (~/.zshrc), on the new window
        subprocess.Popen(["kitty", "--directory", home], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        sys.exit(2)
    if a[0] == "limits":
        out(limits(refresh="--refresh" in a))
    elif a[0] == "stats":
        out(stats())
    elif a[0] == "bar":
        bar()
    elif a[0] == "launch" and len(a) >= 2 and a[1] in AGENTS:
        prompt = a[2] if len(a) > 2 else ""
        run_in_tmux(AGENTS[a[1]]["cmd"] + (" " + shlex.quote(prompt) if prompt else ""))
    elif a[0] == "login" and len(a) == 2 and a[1] in AGENTS:
        run_in_tmux("claude /login" if a[1] == "claude" else "codex login")
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
