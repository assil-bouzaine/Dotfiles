"""The footer under each alert: context used, 5h limit, weekly limit.

Claude  limits + window size come from the snapshot the status line saves on every refresh
        (~/.claude/statusline-command.sh -> ~/.cache/agent-usage/claude/<session>.json);
        context tokens from the transcript, which is fresher.
Codex   the last token_count event in the session's rollout (~/.codex/sessions/...):
        primary = 5h window, secondary = weekly.
"""
import json
import time
from pathlib import Path

CACHE = Path.home() / ".cache/agent-usage"


def footer(agent, payload):
    """HTML footer for an alert, or "" when nothing is known. Never raises."""
    try:
        get = codex_usage if agent == "codex" else claude_usage
        return render(get(payload))
    except Exception:      # usage is a nice-to-have; never lose the alert over it
        return ""


def tail_json(path, size=400_000):
    """JSON objects from the end of a JSONL file, newest first."""
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - size))
            lines = f.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return
    for line in reversed(lines):
        try:
            yield json.loads(line)
        except ValueError:
            continue


def load(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}


def claude_usage(p):
    d = CACHE / "claude"
    snaps = sorted(d.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True) if d.is_dir() else []
    for f in snaps[20:]:                       # keep the cache small
        f.unlink(missing_ok=True)
    session, transcript = p.get("session_id"), p.get("transcript_path")
    own = load(d / f"{session}.json") if session else {}
    limits = next((s["rate_limits"] for s in map(load, snaps[:5]) if s.get("rate_limits")), {})
    u = {"5h": limits.get("five_hour"), "week": limits.get("seven_day")}
    cw = own.get("context_window") or {}
    window = cw.get("context_window_size")
    used = None
    for e in tail_json(transcript) if transcript else ():
        usage = (e.get("message") or {}).get("usage")
        if e.get("type") == "assistant" and not e.get("isSidechain") and usage:
            used = sum(usage.get(k) or 0 for k in
                       ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
            break
    if used is None and cw.get("used_percentage") is not None and window:
        used = cw["used_percentage"] / 100 * window
    u["ctx"] = (used, window)
    return u


def codex_rollout(p):
    transcript, session, cwd = p.get("transcript_path"), p.get("session_id"), p.get("cwd")
    if transcript and Path(transcript).is_file():
        return transcript
    files = sorted((Path.home() / ".codex/sessions").glob("*/*/*/*.jsonl"),
                   key=lambda f: f.stat().st_mtime, reverse=True)[:30]
    if session:
        for f in files:
            if session in f.name:
                return f
    for f in files:
        try:
            with open(f) as fh:
                meta = json.loads(fh.readline()).get("payload", {})
        except (OSError, ValueError):
            continue
        if not cwd or meta.get("cwd") == cwd:
            return f
    return None


def codex_usage(p):
    time.sleep(1)   # let Codex flush the turn's final token_count event
    f = codex_rollout(p)
    for e in tail_json(f) if f else ():
        pl = e.get("payload") or {}
        if pl.get("type") == "token_count" and (pl.get("info") or pl.get("rate_limits")):
            info, rl = pl.get("info") or {}, pl.get("rate_limits") or {}
            last = info.get("last_token_usage") or {}
            conv = lambda w: w and {"used_percentage": w.get("used_percent"),
                                    "resets_at": w.get("resets_at")}
            return {"ctx": (last.get("total_tokens"), info.get("model_context_window")),
                    "5h": conv(rl.get("primary")), "week": conv(rl.get("secondary"))}
    return {}


def tokens(n):
    if n >= 1e6:
        return f"{n / 1e6:.1f}".removesuffix(".0") + "M"
    return f"{n / 1e3:.0f}k" if n >= 1e3 else str(int(n))


def until(ts):
    secs = int(ts - time.time())
    if secs <= 0:
        return None
    d, h, m = secs // 86400, secs % 86400 // 3600, secs % 3600 // 60
    return f"{d}d {h}h" if d else f"{h}h {m}m" if h else f"{m}m"


def render(u):
    rows = []
    used, window = u.get("ctx") or (None, None)
    if used is not None and window:
        rows.append(f"<b>Context</b>  {used / window:.0%} · {tokens(used)} of {tokens(window)}")
    elif used is not None:
        rows.append(f"<b>Context</b>  {tokens(used)} tokens")
    for key, label in (("5h", "5h limit"), ("week", "Weekly")):
        w = u.get(key) or {}
        pct, reset = w.get("used_percentage"), w.get("resets_at")
        if pct is None:
            continue
        left = until(reset) if reset else None
        if reset and not left:
            rows.append(f"<b>{label}</b>  0% used · just reset")
        else:
            rows.append(f"<b>{label}</b>  {pct:.0f}% used" + (f" · resets in {left}" if left else ""))
    return "──────────\n" + "\n".join(rows) if rows else ""
