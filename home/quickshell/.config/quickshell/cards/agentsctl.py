#!/usr/bin/env python3
"""Back end of the agents card (AgentsCard.qml) and the bar's robot icon.

    agentsctl.py limits [--refresh]      plan, limits, and live sessions per agent (JSON)
    agentsctl.py stats                   token / prompt / session counts across all agents (JSON)
    agentsctl.py bar                     waybar JSON for the robot icon (no blocking network)
    agentsctl.py launch <agent> [prompt] start an agent in a new tmux window, in ~
    agentsctl.py focus <tmux_target>     jump to a live agent's tmux window & terminal
    agentsctl.py login <agent>           sign in again in a new tmux window

Supports Claude Code, Codex, Antigravity (agy), OpenCode, and Pi.
Modelled on Omarchy 4.5's agents panel (MIT, github.com/omacom/omarchy,
shell/plugins/agents & bin/omarchy-agent-usage-*), extended with live tmux
session tracking, per-agent 7-day activity sparklines, and Pi support.
"""

import base64
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime, timedelta, timezone
import json
import math
import os
from pathlib import Path
import re
import shlex
import sqlite3
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.dont_write_bytecode = True
HOME = Path.home()
sys.path.insert(0, str(HOME / ".local/lib/agent-notify"))

CACHE = HOME / ".cache/agent-usage"
LIMITS_CACHE = CACHE / "panel-limits.json"
STATS_CACHE = CACHE / "panel-stats-v2.json"
NOPLAN_CACHE = CACHE / "opencode-noplan.json"
LIMITS_TTL = 60
NOPLAN_TTL = 3600
DAYS = 8
AGENT_ORDER = ("claude", "codex", "agy", "opencode", "pi")

EXTRA_BIN_DIRS = (
    HOME / ".local/bin",
    HOME / ".opencode/bin",
    HOME / ".pi/agent/bin",
    HOME / ".bun/bin",
    HOME / ".cargo/bin",
    Path("/usr/local/bin"),
    Path("/usr/bin"),
)

WINDOW_LABELS = {"5h": "Session", "weekly": "Weekly", "monthly": "Monthly"}
DEFAULT_CLOUD_CODE_URL = "https://daily-cloudcode-pa.googleapis.com"
OPENCODE_API_BASE = "https://opencode.ai"
MODEL_SELECTION_RE = re.compile(r"Model Selection` (?:from .+? )?to (.+?)\.(?:\s|$|<)")


def data_home():
    return Path(os.environ.get("XDG_DATA_HOME") or (HOME / ".local/share"))


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME") or (HOME / ".config"))


def agy_root():
    return Path(os.environ.get("AGY_DIR") or (HOME / ".gemini/antigravity-cli"))


def pi_agent_dir():
    cfg = os.environ.get("PI_CODING_AGENT_DIR", "").strip()
    return Path(cfg).expanduser() if cfg else HOME / ".pi/agent"


def pi_session_roots():
    roots = []
    cfg_sess = os.environ.get("PI_CODING_AGENT_SESSION_DIR", "").strip()
    if cfg_sess:
        roots.append(Path(cfg_sess).expanduser())
    roots.append(pi_agent_dir() / "sessions")
    out_roots, seen = [], set()
    for r in roots:
        if r.is_dir():
            key = str(r.resolve())
            if key not in seen:
                seen.add(key)
                out_roots.append(r)
    return out_roots


def opencode_db_path():
    root = data_home() / "opencode"
    cfg = os.environ.get("OPENCODE_DB", "").strip()
    if cfg:
        p = Path(cfg).expanduser()
        return p if p.is_absolute() else root / p
    normal = root / "opencode.db"
    legacy = root / "opencode-v2.db"
    return legacy if not normal.is_file() and legacy.is_file() else normal


AGENTS = {
    "claude": {"name": "Claude Code", "cmd": "claude", "login": "claude /login"},
    "codex": {"name": "Codex", "cmd": "codex", "login": "codex login"},
    "agy": {"name": "Antigravity", "cmd": "agy", "login": "agy"},
    "opencode": {"name": "OpenCode", "cmd": "opencode", "login": "opencode auth login"},
    "pi": {"name": "Pi", "cmd": "pi", "login": "pi"},
}


def out(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def write_json(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(obj))
    os.replace(tmp, path)


def read_json(path, default=None):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {} if default is None else default


def find_cmd(name):
    dirs = [Path(d) for d in os.environ.get("PATH", "").split(":") if d] + list(EXTRA_BIN_DIRS)
    seen = set()
    for d in dirs:
        s = str(d)
        if s in seen:
            continue
        seen.add(s)
        cand = d / name
        if cand.is_file() and os.access(cand, os.X_OK):
            return str(cand)
    return None


def agent_home_exists(agent_id):
    if agent_id == "claude":
        return (HOME / ".claude").exists()
    if agent_id == "codex":
        return (HOME / ".codex").exists()
    if agent_id == "agy":
        return agy_root().exists()
    if agent_id == "opencode":
        return (HOME / ".opencode").exists() or (data_home() / "opencode").exists()
    if agent_id == "pi":
        return pi_agent_dir().exists() or (HOME / ".pi").exists()
    return False


def installed(agent_id):
    return bool(find_cmd(AGENTS[agent_id]["cmd"])) or agent_home_exists(agent_id)


def num(val, default=0):
    if isinstance(val, bool) or val is None:
        return default
    try:
        f = float(val)
        return int(f) if math.isfinite(f) and 0 <= f < 1e15 else default
    except (TypeError, ValueError):
        return default


def parse_time(val):
    if val is None or val == "" or isinstance(val, bool):
        return None
    try:
        if isinstance(val, (int, float)) or (isinstance(val, str) and val.isdigit()):
            stamp = float(val)
            if not math.isfinite(stamp) or stamp <= 0:
                return None
            dt = datetime.fromtimestamp(stamp / 1000.0 if stamp > 1e12 else stamp, timezone.utc)
        else:
            dt = datetime.fromisoformat(str(val).strip().replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
    except (ValueError, OverflowError, OSError):
        return None
    if not (2000 <= dt.year <= 2100):
        return None
    return dt


def local_day(val):
    dt = parse_time(val)
    if dt is None:
        return None
    try:
        return dt.astimezone().date().isoformat()
    except (ValueError, OverflowError, OSError):
        return None


def http_json(url, headers=None, body=None, timeout=10):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read(2_000_000)
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        try:
            raw = e.read(500_000)
            payload = json.loads(raw) if raw else {}
        except Exception:
            payload = {}
        return e.code, payload
    except Exception as e:
        return 0, {"_transport_error": str(e)}


# ── live tmux / process detection ─────────────────────────────────────────

STATE_PRIORITY = {"question": 4, "waiting": 3, "working": 2, "done": 1, "running": 0, "idle": 0}


def _match_agent_cmdline(comm, cmdline):
    c = (comm or "").lower().strip()
    if c in ("claude", "codex", "agy", "opencode", "pi"):
        return c
    if not cmdline:
        return None
    parts = [p for p in cmdline.split("\x00") if p]
    if not parts:
        return None
    for idx, arg in enumerate(parts[:4]):
        base = os.path.basename(arg).lower()
        if base in ("claude", "codex", "agy", "opencode", "pi"):
            # Skip our own scripts or helper binaries
            if idx == 0 or base in ("claude", "codex", "agy", "opencode", "pi"):
                return base
        if "/@mariozechner/pi-coding-agent/" in arg or "/.pi/agent/bin/pi" in arg:
            return "pi"
        if "/.opencode/bin/opencode" in arg or "/opencode/bin/" in arg:
            return "opencode"
        if "/antigravity-cli/" in arg and base == "agy":
            return "agy"
    return None


def _proc_tree():
    """Map ppid -> [child_pids] and pid -> (comm, cmdline) via /proc."""
    children = {}
    info = {}
    try:
        entries = os.listdir("/proc")
    except OSError:
        return children, info
    for name in entries:
        if not name.isdigit():
            continue
        pid = int(name)
        try:
            stat = Path(f"/proc/{pid}/stat").read_text(errors="ignore")
            rp = stat.rfind(")")
            if rp < 0:
                continue
            comm = stat[stat.find("(") + 1:rp]
            ppid = int(stat[rp + 2:].split()[1])
            children.setdefault(ppid, []).append(pid)
            info[pid] = comm
        except (OSError, ValueError, IndexError):
            continue
    return children, info


def _find_agent_under(root_pid, children, info):
    """Breadth-first scan of a tmux pane's process subtree for a coding agent."""
    queue = [root_pid]
    visited = set()
    while queue:
        pid = queue.pop(0)
        if pid in visited:
            continue
        visited.add(pid)
        comm = info.get(pid, "")
        try:
            cmdline = Path(f"/proc/{pid}/cmdline").read_text(errors="ignore")
        except OSError:
            cmdline = ""
        # Ignore our own agentsctl.py or agent-notify helpers
        if "agentsctl.py" not in cmdline and "agent-notify" not in cmdline:
            found = _match_agent_cmdline(comm, cmdline)
            if found:
                return found
        for child in children.get(pid, ()):
            queue.append(child)
    return None


def _hypr_clients_by_pid():
    ok, js = sh("hyprctl", "clients", "-j")
    if not ok or not js:
        return {}
    try:
        return {w["pid"]: w["address"] for w in json.loads(js) if isinstance(w, dict) and w.get("pid") and w.get("address")}
    except ValueError:
        return {}


def _window_addr_for_pid(pid, windows):
    seen = set()
    while pid > 1 and pid not in seen:
        seen.add(pid)
        if pid in windows:
            return windows[pid]
        try:
            stat = Path(f"/proc/{pid}/stat").read_text(errors="ignore")
            pid = int(stat.rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return None


def _all_descendants(root_pid, children):
    out_pids, queue = set(), [root_pid]
    while queue:
        p = queue.pop()
        if p in out_pids:
            continue
        out_pids.add(p)
        queue.extend(children.get(p, ()))
    return out_pids


def live_sessions():
    """Return {agent_id: {count, state, target, cwd}} for agents running in tmux or standalone terminals."""
    children, info = _proc_tree()
    found = {}
    tmux_pids = set()

    ok, raw = sh(
        "tmux", "list-panes", "-a", "-F",
        "#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}\t"
        "#{pane_pid}\t#{pane_current_path}\t#{@agent_name}\t#{@agent_state}",
    )
    if ok and raw:
        for line in raw.splitlines():
            cols = line.split("\t")
            if len(cols) < 6:
                continue
            target, cmd, pid_s, cwd, tag_name, tag_state = cols[:6]
            if pid_s.isdigit():
                tmux_pids.update(_all_descendants(int(pid_s), children))
            agent_id = tag_name.strip().lower() if tag_name.strip().lower() in AGENTS else None
            if not agent_id:
                agent_id = _match_agent_cmdline(cmd, "")
            if not agent_id and pid_s.isdigit():
                agent_id = _find_agent_under(int(pid_s), children, info)
            if not agent_id:
                continue
            state = tag_state.strip().lower() or "running"
            if state not in STATE_PRIORITY:
                state = "running"
            cwd_short = "~" if cwd == str(HOME) else os.path.basename(cwd.rstrip("/")) or cwd
            tmux_target = f"tmux:{target}"
            cur = found.get(agent_id)
            if not cur:
                found[agent_id] = {"count": 1, "state": state, "target": tmux_target, "cwd": cwd_short}
            else:
                cur["count"] += 1
                if STATE_PRIORITY.get(state, 0) > STATE_PRIORITY.get(cur["state"], 0):
                    cur["state"] = state
                    cur["target"] = tmux_target
                    cur["cwd"] = cwd_short

    # Also detect standalone interactive agent processes outside tmux (must have a PTY;
    # deduped by tty_nr so helper/subagent child processes in the same terminal count once).
    windows = None
    seen_ttys = set()
    for pid, comm in info.items():
        if pid in tmux_pids:
            continue
        try:
            stat = Path(f"/proc/{pid}/stat").read_text(errors="ignore")
            rp = stat.rfind(")")
            if rp < 0:
                continue
            fields = stat[rp + 2:].split()
            tty_nr = int(fields[4])     # field 7 overall (0 = no controlling terminal / daemon)
        except (OSError, ValueError, IndexError):
            continue
        if tty_nr == 0 or tty_nr in seen_ttys:
            continue
        try:
            cmdline = Path(f"/proc/{pid}/cmdline").read_text(errors="ignore")
        except OSError:
            continue
        if not cmdline or "agentsctl.py" in cmdline or "agent-notify" in cmdline:
            continue
        parts = [p for p in cmdline.split("\x00") if p]
        if any(flag in parts[1:4] for flag in ("daemon", "acp", "mcp", "remote-control", "mic-serve", "app-server", "-p", "--print")):
            continue
        agent_id = _match_agent_cmdline(comm, cmdline)
        if not agent_id:
            continue
        seen_ttys.add(tty_nr)
        if windows is None:
            windows = _hypr_clients_by_pid()
        addr = _window_addr_for_pid(pid, windows)
        try:
            cwd = os.readlink(f"/proc/{pid}/cwd")
            cwd_short = "~" if cwd == str(HOME) else os.path.basename(cwd.rstrip("/")) or cwd
        except OSError:
            cwd_short = ""
        target = f"hypr:{addr}" if addr else ""
        cur = found.get(agent_id)
        if not cur:
            found[agent_id] = {"count": 1, "state": "running", "target": target, "cwd": cwd_short}
        else:
            cur["count"] += 1
            if not cur["target"] and target:
                cur["target"] = target
    return found


def _ancestors(pid):
    out_p, seen = [], set()
    cur = pid
    while cur > 1 and cur not in seen:
        seen.add(cur)
        try:
            stat = Path(f"/proc/{cur}/stat").read_text(errors="ignore")
            cur = int(stat.rsplit(")", 1)[1].split()[1])
            out_p.append(cur)
        except (OSError, ValueError, IndexError):
            break
    return out_p


# ── plans & credentials ───────────────────────────────────────────────────

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


def pi_plan():
    auth = read_json(pi_agent_dir() / "auth.json", {})
    settings = read_json(pi_agent_dir() / "settings.json", {})
    providers = [k for k in auth.keys() if isinstance(k, str)] if isinstance(auth, dict) else []
    pkgs = settings.get("packages") if isinstance(settings, dict) else []
    has_free = any("pi-free" in str(p) for p in (pkgs or []))
    labels = []
    for p in providers[:2]:
        nice = {
            "anthropic": "Anthropic",
            "openai": "OpenAI",
            "google-antigravity": "Antigravity",
            "opencode": "OpenCode",
            "opencode-go": "OpenCode Go",
            "cline": "Cline",
            "openrouter": "OpenRouter",
        }.get(p, p.capitalize())
        if nice not in labels:
            labels.append(nice)
    if has_free and "Free" not in labels:
        labels.append("Free")
    return " · ".join(labels)


def opencode_providers_label():
    labels = []
    db = opencode_db_path()
    if db.is_file():
        try:
            conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=1.5)
            try:
                conn.execute("PRAGMA query_only = ON")
                rows = conn.execute(
                    "SELECT integration_id FROM credential WHERE active = 1 ORDER BY time_updated DESC"
                ).fetchall()
                for (iid,) in rows:
                    nice = {
                        "opencode-go": "Go",
                        "opencode": "Zen",
                        "openai": "OpenAI",
                        "anthropic": "Anthropic",
                        "github-copilot": "Copilot",
                    }.get(str(iid or ""), str(iid or "").capitalize())
                    if nice and nice not in labels:
                        labels.append(nice)
            except sqlite3.Error:
                pass
            finally:
                conn.close()
        except sqlite3.Error:
            pass
    auth = read_json(data_home() / "opencode/auth.json", {})
    if isinstance(auth, dict):
        for k in auth:
            nice = {
                "opencode-go": "Go",
                "opencode": "Zen",
                "github-copilot": "Copilot",
                "openai": "OpenAI",
                "anthropic": "Anthropic",
            }.get(k, k.capitalize())
            if nice not in labels:
                labels.append(nice)
    return " · ".join(labels[:2]) if labels else "Zen"


# ── Antigravity (agy) limits (from Omarchy omarchy-agent-usage-agy) ───────

def _agy_logins():
    entries = []
    # 1. Secret Service keyring (where agy stores its OAuth JSON)
    data = None
    try:
        raw = subprocess.check_output(
            ["secret-tool", "lookup", "service", "gemini", "username", "antigravity"],
            text=True, stderr=subprocess.DEVNULL, timeout=2.5,
        )
        data = json.loads(raw) if raw.strip() else None
    except Exception:
        data = None
    if not isinstance(data, dict):
        data = read_json(agy_root() / "antigravity-oauth-token", None)
    if isinstance(data, dict):
        tok = data.get("token") if isinstance(data.get("token"), dict) else {}
        exp = parse_time(tok.get("expiry") or data.get("expiry"))
        access = str(tok.get("access_token") or data.get("access_token") or "")
        refresh = str(tok.get("refresh_token") or data.get("refresh_token") or "")
        if access:
            entries.append({
                "source": "agy",
                "access": access,
                "expires": exp.timestamp() if exp else 0,
                "refresh": refresh,
                "auth_method": str(data.get("auth_method") or "consumer"),
            })
    # 2. pi's google-antigravity OAuth token (read-only)
    pi_auth = read_json(pi_agent_dir() / "auth.json", {})
    if isinstance(pi_auth, dict):
        ga = pi_auth.get("google-antigravity")
        if isinstance(ga, dict) and ga.get("type", "oauth") == "oauth" and ga.get("access"):
            exp = parse_time(ga.get("expires"))
            entries.append({
                "source": "pi",
                "access": str(ga["access"]),
                "expires": exp.timestamp() if exp else 0,
                "refresh": str(ga.get("refresh") or ""),
                "auth_method": "consumer",
            })
    # 3. opencode's antigravity plugin token (read-only)
    if (config_home() / "opencode/antigravity-accounts.json").is_file():
        oc_auth = read_json(data_home() / "opencode/auth.json", {})
        if isinstance(oc_auth, dict):
            ga = oc_auth.get("google")
            if isinstance(ga, dict) and ga.get("type", "oauth") == "oauth" and ga.get("access"):
                exp = parse_time(ga.get("expires"))
                entries.append({
                    "source": "opencode",
                    "access": str(ga["access"]),
                    "expires": exp.timestamp() if exp else 0,
                    "refresh": str(ga.get("refresh") or ""),
                    "auth_method": "consumer",
                })
    return entries


def _agy_tier(data):
    for key in ("paidTier", "currentTier"):
        tier = data.get(key) if isinstance(data, dict) else None
        if isinstance(tier, dict):
            name = str(tier.get("name") or "").strip()
            tid = str(tier.get("id") or "").strip()
            for word in ("ultra", "pro", "free"):
                if word in tid.lower() or word in name.lower():
                    return word.capitalize()
            if name.lower().startswith("google ai "):
                return name[10:].strip()
            if name or tid:
                return name or tid.replace("-tier", "").capitalize()
    return ""


def _agy_bucket_used(bucket):
    if bucket.get("disabled") is True:
        return None
    rem = bucket.get("remainingFraction", bucket.get("remaining_fraction"))
    amt = bucket.get("remainingAmount", bucket.get("remaining_amount"))
    rst = parse_time(bucket.get("resetTime") or bucket.get("reset_time"))
    if rem is None and amt is not None:
        return 100.0 if amt in (0, "0") and not isinstance(amt, bool) else None
    if rem is None and rst is not None:
        return 100.0
    if rem is None or isinstance(rem, bool):
        return None
    try:
        f = float(rem)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(f):
        return None
    return round(max(0.0, min(100.0, (1.0 - f) * 100.0)), 1)


def _agy_extract_windows(summary_data, raw_quota=None):
    """Combine retrieveUserQuotaSummary + retrieveUserQuota.

    On some Google AI Pro accounts, retrieveUserQuotaSummary only returns the
    3P ("Claude and GPT models") group while omitting Gemini; retrieveUserQuota
    still returns the live per-model Gemini remainingFraction and resetTime.
    We prefer Gemini from retrieveUserQuotaSummary when present, and otherwise
    pull the live Gemini bucket from retrieveUserQuota so the meter matches agy.
    """
    if not isinstance(summary_data, dict) or "error" in summary_data:
        summary_data = {}
    groups = [g for g in (summary_data.get("groups") or []) if isinstance(g, dict)]
    if not groups and isinstance(summary_data.get("buckets"), list):
        groups = [{"displayName": "Gemini", "buckets": summary_data["buckets"]}]

    gemini = next((g for g in groups if "gemini" in str(g.get("displayName") or "").lower()), None)
    windows = []
    by_key = {}

    if gemini is not None:
        session_b = weekly_b = None
        for b in (gemini.get("buckets") or []):
            if not isinstance(b, dict) or _agy_bucket_used(b) is None:
                continue
            w = str(b.get("window") or "").lower()
            bid = str(b.get("bucketId") or "").lower()
            nm = str(b.get("displayName") or "").lower()
            if w == "5h" or "5h" in bid or "five" in nm:
                session_b = b
            elif w == "weekly" or "weekly" in bid or "week" in nm:
                weekly_b = b
        for key, label, b in (("5h", "Session", session_b), ("weekly", "Weekly", weekly_b)):
            if b:
                rst = parse_time(b.get("resetTime") or b.get("reset_time"))
                row = {
                    "key": key, "label": label,
                    "percent": _agy_bucket_used(b),
                    "resets_at": rst.timestamp() if rst else None,
                    "scoped": [],
                }
                windows.append(row)
                by_key[key] = row

    # Fallback: live Gemini quota from retrieveUserQuota when summary omitted Gemini
    if not windows and isinstance(raw_quota, dict):
        best_pct = None
        best_rst = None
        for b in (raw_quota.get("buckets") or []):
            if not isinstance(b, dict):
                continue
            mid = str(b.get("modelId") or "").lower()
            if not mid.startswith("gemini-"):
                continue
            pct = _agy_bucket_used(b)
            if pct is None:
                continue
            rst = parse_time(b.get("resetTime") or b.get("reset_time"))
            if best_pct is None or pct > best_pct:
                best_pct = pct
                best_rst = rst
        if best_pct is not None:
            row = {
                "key": "5h", "label": "Gemini",
                "percent": best_pct,
                "resets_at": best_rst.timestamp() if best_rst else None,
                "scoped": [],
            }
            windows.append(row)
            by_key["5h"] = row

    # 3P groups (e.g. Claude and GPT models): attach as scoped ticks or own row when touched
    for g in groups:
        if g is gemini:
            continue
        gname = str(g.get("displayName") or "").strip()
        short = "Claude/GPT" if "claude" in gname.lower() else (gname or "3P")
        for b in (g.get("buckets") or []):
            if not isinstance(b, dict):
                continue
            pct = _agy_bucket_used(b)
            if pct is None:
                continue
            w = str(b.get("window") or "").lower()
            target_key = "weekly" if "week" in w else "5h"
            if pct > 0:
                if target_key in by_key:
                    by_key[target_key]["scoped"].append({"title": short, "percent": pct})
                else:
                    rst = parse_time(b.get("resetTime") or b.get("reset_time"))
                    lbl = f"{short} 7d" if target_key == "weekly" else short
                    windows.append({
                        "key": f"3p_{target_key}",
                        "label": lbl,
                        "percent": pct,
                        "resets_at": rst.timestamp() if rst else None,
                        "scoped": [],
                    })

    # If still nothing at all (no Gemini anywhere), surface the 3P summary buckets directly
    if not windows and groups:
        for b in (groups[0].get("buckets") or []):
            if not isinstance(b, dict):
                continue
            pct = _agy_bucket_used(b)
            if pct is None:
                continue
            w = str(b.get("window") or "").lower()
            rst = parse_time(b.get("resetTime") or b.get("reset_time"))
            windows.append({
                "key": "weekly" if "week" in w else "5h",
                "label": "Weekly" if "week" in w else "Session",
                "percent": pct,
                "resets_at": rst.timestamp() if rst else None,
                "scoped": [],
            })
    return windows


def fetch_agy():
    entries = _agy_logins()
    now = time.time()
    fresh = sorted(
        [e for e in entries if e["access"] and (not e["expires"] or e["expires"] > now)],
        key=lambda e: -e["expires"],
    )
    lead = fresh[0] if fresh else (entries[0] if entries else None)
    if not lead:
        return {
            "id": "agy", "name": "Antigravity", "plan": "",
            "windows": [], "error": "", "auth_error": False, "status_note": "",
        }
    base = (os.environ.get("CLOUD_CODE_URL") or DEFAULT_CLOUD_CODE_URL).rstrip("/")
    if not base.startswith("https://"):
        base = DEFAULT_CLOUD_CODE_URL

    refused = False
    for entry in fresh:
        hdrs = {
            "Authorization": f"Bearer {entry['access']}",
            "Content-Type": "application/json",
            "User-Agent": "antigravity",
        }
        st1, assist = http_json(f"{base}/v1internal:loadCodeAssist", hdrs, {"metadata": {"ideType": "ANTIGRAVITY"}}, timeout=8)
        if st1 in (401, 403):
            refused = True
            continue
        if st1 != 200:
            return {
                "id": "agy", "name": "Antigravity", "plan": "",
                "windows": [], "error": f"HTTP {st1}" if st1 else "network error",
                "auth_error": False, "status_note": "",
            }
        tier = _agy_tier(assist)
        if not tier and entry["auth_method"] == "enterprise":
            tier = "Enterprise"
        elif not tier and entry["auth_method"] in ("cloud", "vertex"):
            tier = "Cloud"
        proj = assist.get("cloudaicompanionProject") if isinstance(assist, dict) else None
        if isinstance(proj, dict):
            proj = proj.get("id")
        body = {"project": proj.strip()} if isinstance(proj, str) and proj.strip() else {}
        st2, summary = http_json(f"{base}/v1internal:retrieveUserQuotaSummary", hdrs, body, timeout=8)
        if st2 in (401, 403):
            refused = True
            continue
        # Only query retrieveUserQuota if summary didn't include a Gemini group
        has_gemini_group = isinstance(summary, dict) and any(
            isinstance(g, dict) and "gemini" in str(g.get("displayName") or "").lower()
            for g in (summary.get("groups") or [])
        )
        raw_quota = None
        if not has_gemini_group:
            st3, q_raw = http_json(f"{base}/v1internal:retrieveUserQuota", hdrs, body, timeout=8)
            if st3 == 200 and isinstance(q_raw, dict):
                raw_quota = q_raw
        if st2 != 200 and raw_quota is None:
            return {
                "id": "agy", "name": "Antigravity", "plan": tier,
                "windows": [], "error": f"HTTP {st2}" if st2 else "network error",
                "auth_error": False, "status_note": "",
            }
        wins = _agy_extract_windows(summary if st2 == 200 else {}, raw_quota)
        return {
            "id": "agy", "name": "Antigravity", "plan": tier,
            "windows": wins, "error": "", "auth_error": False, "status_note": "",
        }

    if refused:
        return {
            "id": "agy", "name": "Antigravity", "plan": "",
            "windows": [], "error": "Sign-in expired", "auth_error": True, "status_note": "",
        }
    if lead["refresh"]:
        return {
            "id": "agy", "name": "Antigravity", "plan": "",
            "windows": [], "error": "Limits paused", "auth_error": False, "status_note": "Limits paused",
        }
    return {
        "id": "agy", "name": "Antigravity", "plan": "",
        "windows": [], "error": "Sign-in expired", "auth_error": True, "status_note": "",
    }


# ── OpenCode limits (from Omarchy omarchy-agent-usage-opencode) ───────────

def _opencode_read_auth_key(path):
    d = read_json(path, {})
    if not isinstance(d, dict):
        return ""
    for prov in ("opencode-go", "opencode"):
        val = d.get(prov)
        if isinstance(val, dict):
            val = val.get("key")
        if isinstance(val, str) and val.strip() and not val.strip().startswith(("!", "$")):
            return val.strip()
    return ""


def _opencode_credentials():
    creds = []
    for var in ("OPENCODE_API_KEY", "OPENCODE_GO_API_KEY"):
        v = os.environ.get(var, "").strip()
        if v:
            creds.append((v, f"{OPENCODE_API_BASE}/zen/go/v1/usage", {}))
    db = opencode_db_path()
    console = None
    if db.is_file():
        try:
            conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
            try:
                conn.execute("PRAGMA query_only = ON")
                rows = conn.execute(
                    "SELECT integration_id, value FROM credential WHERE active = 1 "
                    "AND integration_id IN ('opencode-go', 'opencode') "
                    "ORDER BY integration_id = 'opencode-go' DESC, time_updated DESC"
                ).fetchall()
                for _, raw in rows:
                    try:
                        val = json.loads(raw)
                    except Exception:
                        continue
                    if not isinstance(val, dict):
                        continue
                    if val.get("type") == "key" and str(val.get("key") or "").strip():
                        creds.append((str(val["key"]).strip(), f"{OPENCODE_API_BASE}/zen/go/v1/usage", {}))
                    elif val.get("type") == "oauth" and console is None and str(val.get("access") or "").strip():
                        meta = val.get("metadata") if isinstance(val.get("metadata"), dict) else {}
                        org = str(meta.get("orgID") or "").strip()
                        hdr = {"x-opencode-org-id": org} if org else {}
                        console = (str(val["access"]).strip(), f"{OPENCODE_API_BASE}/inference/go/v1/usage", hdr)
            except sqlite3.Error:
                pass
            finally:
                conn.close()
        except sqlite3.Error:
            pass
    for p in (data_home() / "opencode/auth.json", pi_agent_dir() / "auth.json"):
        k = _opencode_read_auth_key(p)
        if k:
            creds.append((k, f"{OPENCODE_API_BASE}/zen/go/v1/usage", {}))
    if console:
        creds.append(console)
    # Deduplicate by token
    out_creds, seen = [], set()
    for c in creds:
        if c[0] not in seen:
            seen.add(c[0])
            out_creds.append(c)
    return out_creds


def fetch_opencode(force=False):
    plan = opencode_providers_label()
    creds = _opencode_credentials()
    if not creds:
        return {
            "id": "opencode", "name": "OpenCode", "plan": plan,
            "windows": [], "error": "", "auth_error": False, "status_note": "",
        }
    noplan = read_json(NOPLAN_CACHE, {})
    if not force and time.time() - noplan.get("at", 0) < NOPLAN_TTL:
        return {
            "id": "opencode", "name": "OpenCode", "plan": plan,
            "windows": [], "error": "", "auth_error": False, "status_note": "",
        }
    refused = False
    for token, url, extra_hdr in creds:
        hdrs = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "agentsctl-opencode/1.0",
            **extra_hdr,
        }
        st, payload = http_json(url, hdrs, timeout=8)
        if st == 403:
            write_json(NOPLAN_CACHE, {"at": time.time()})
            return {
                "id": "opencode", "name": "OpenCode", "plan": plan,
                "windows": [], "error": "", "auth_error": False, "status_note": "",
            }
        if st == 401:
            refused = True
            continue
        if st == 200 and isinstance(payload, dict):
            usage = payload.get("usage") if isinstance(payload.get("usage"), dict) else payload
            windows = []
            for key, label in (("rolling", "Session"), ("weekly", "Weekly"), ("monthly", "Monthly")):
                w = usage.get(key) if isinstance(usage.get(key), dict) else payload.get(key + "Usage")
                if not isinstance(w, dict):
                    continue
                pct = w.get("percent", w.get("usagePercent"))
                if pct is None or isinstance(pct, bool):
                    continue
                try:
                    pct_f = float(pct)
                except (TypeError, ValueError):
                    continue
                if str(w.get("status") or "") == "rate-limited":
                    pct_f = 100.0
                rst = parse_time(w.get("resetsAt"))
                if rst is None and num(w.get("resetInSec")) > 0:
                    rst = datetime.now(timezone.utc) + timedelta(seconds=num(w.get("resetInSec")))
                windows.append({
                    "key": "5h" if key == "rolling" else key,
                    "label": label,
                    "percent": round(max(0.0, min(100.0, pct_f)), 1),
                    "resets_at": rst.timestamp() if rst else None,
                })
            if windows:
                return {
                    "id": "opencode", "name": "OpenCode", "plan": "Go",
                    "windows": windows, "error": "", "auth_error": False, "status_note": "",
                }
        return {
            "id": "opencode", "name": "OpenCode", "plan": plan,
            "windows": [], "error": f"HTTP {st}" if st else "network error",
            "auth_error": False, "status_note": "",
        }
    return {
        "id": "opencode", "name": "OpenCode", "plan": plan,
        "windows": [], "error": "Sign-in expired" if refused else "",
        "auth_error": refused, "status_note": "",
    }


def fetch_claude_or_codex(key):
    from agentnotify import limits as L
    try:
        u = L.FETCH[key]()
    except Exception as e:
        u = L.Usage(key, error=str(e))
    plan_fn = claude_plan if key == "claude" else codex_plan
    return {
        "id": key,
        "name": AGENTS[key]["name"],
        "plan": plan_fn(),
        "windows": [
            {
                "key": w.key,
                "label": WINDOW_LABELS.get(w.key, w.label.capitalize()),
                "percent": round(w.percent, 1),
                "resets_at": w.resets_at,
            }
            for w in u.windows
        ],
        "error": u.error,
        "auth_error": u.auth_error,
        "status_note": "",
    }


def fetch_pi():
    return {
        "id": "pi",
        "name": "Pi",
        "plan": pi_plan(),
        "windows": [],
        "error": "",
        "auth_error": False,
        "status_note": "",
    }


def fetch_limits(force=False):
    active_ids = [k for k in AGENT_ORDER if installed(k)]
    results = {}

    def worker(key):
        if key in ("claude", "codex"):
            return fetch_claude_or_codex(key)
        if key == "agy":
            return fetch_agy()
        if key == "opencode":
            return fetch_opencode(force=force)
        return fetch_pi()

    with ThreadPoolExecutor(max_workers=max(1, len(active_ids))) as pool:
        futs = {pool.submit(worker, k): k for k in active_ids}
        for fut, key in futs.items():
            try:
                results[key] = fut.result(timeout=20)
            except Exception as e:
                results[key] = {
                    "id": key, "name": AGENTS[key]["name"], "plan": "",
                    "windows": [], "error": str(e), "auth_error": False, "status_note": "",
                }

    agents = [results[k] for k in active_ids if k in results]
    return {"fetched_at": time.time(), "agents": agents}


def limits(refresh=False):
    cached = read_json(LIMITS_CACHE, None)
    if not refresh and cached and time.time() - cached.get("fetched_at", 0) < LIMITS_TTL:
        data = cached
    else:
        fresh = fetch_limits(force=refresh)
        old = {a["id"]: a for a in (cached or {}).get("agents", [])}
        for a in fresh["agents"]:
            prev = old.get(a["id"])
            if a["error"] and not a["windows"] and prev and prev.get("windows"):
                a["windows"] = prev["windows"]
                a["stale_since"] = prev.get("checked_at", cached.get("fetched_at"))
            if not a["plan"] and prev and prev.get("plan"):
                a["plan"] = prev["plan"]
            a["checked_at"] = fresh["fetched_at"] if not a["error"] else a.get("stale_since", 0)
        write_json(LIMITS_CACHE, fresh)
        data = fresh

    # Always overlay fresh live tmux sessions (cheap, local)
    live = live_sessions()
    for a in data.get("agents", []):
        a["live"] = live.get(a["id"])
    data["live_total"] = sum(v["count"] for v in live.values())
    return data


# ── stats across all 5 agents ─────────────────────────────────────────────

def bump(entry, day, tokens=0, prompts=0, model=None, session=None):
    d = entry["days"].setdefault(day, {"tokens": 0, "prompts": 0, "models": {}, "sessions": []})
    d["tokens"] += tokens
    d["prompts"] += prompts
    if model and tokens:
        d["models"][model] = d["models"].get(model, 0) + tokens
    if session and session not in d["sessions"]:
        d["sessions"].append(session)


def is_claude_prompt(rec):
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
        entry["last_id"] = mid
        tok = num(u.get("input_tokens")) + num(u.get("cache_creation_input_tokens")) + num(u.get("output_tokens"))
        bump(entry, day, tokens=tok, model=model, session=sid)
    elif rec.get("type") == "user" and is_claude_prompt(rec):
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
    sid = f"codex:{path.stem}"
    if p.get("type") == "token_count":
        u = ((p.get("info") or {}).get("last_token_usage")) or {}
        if not u:
            return
        tok = max(0, num(u.get("input_tokens")) - num(u.get("cached_input_tokens"))) + num(u.get("output_tokens"))
        bump(entry, day, tokens=tok, model=entry.get("model"), session=sid)
    elif p.get("type") == "item_completed" and (p.get("item") or {}).get("type") == "UserMessage":
        bump(entry, day, prompts=1, session=sid)


def _agy_model_key(name):
    key = re.sub(r"[\s_]+", "-", re.sub(r"[()]", " ", str(name or "")).strip().lower())
    return re.sub(r"-+", "-", key).strip("-")


def scan_agy(line, entry, path, parents):
    if (b'"input_tokens"' not in line and b'"output_tokens"' not in line
            and b'"prompt_token_count"' not in line and b'"USER_INPUT"' not in line
            and b'Model Selection' not in line):
        return
    step = json.loads(line)
    if not isinstance(step, dict):
        return
    # Track active model across steps
    for field in ("model", "model_name", "model_id"):
        v = step.get(field)
        if isinstance(v, str) and v.strip():
            entry["model"] = _agy_model_key(v)
            break
    else:
        content = step.get("content")
        if isinstance(content, str) and "Model Selection" in content:
            m = MODEL_SELECTION_RE.search(content)
            if m:
                entry["model"] = _agy_model_key(m.group(1))

    day = local_day(step.get("created_at") or step.get("timestamp"))
    if not day:
        return
    # Resolve conversation id (walking up subagent parent links)
    cid = path.parents[2].name if len(path.parents) >= 3 else path.stem
    seen = set()
    while cid in parents and cid not in seen:
        seen.add(cid)
        cid = parents[cid]
    sid = f"agy:{cid}"

    if step.get("type") == "USER_INPUT" and step.get("source") == "USER_EXPLICIT":
        bump(entry, day, prompts=1, session=sid)
        return

    usage = step.get("usage")
    tok = 0
    for src in ([usage] if isinstance(usage, dict) else []) + [step]:
        if "prompt_token_count" in src or "candidates_token_count" in src:
            prompt = num(src.get("prompt_token_count"))
            cached = min(prompt, num(src.get("cached_content_token_count")))
            out_t = num(src.get("candidates_token_count")) + num(src.get("thoughts_token_count"))
            tok = (prompt - cached) + out_t
            break
        if any(k in src for k in ("input_tokens", "output_tokens", "cache_write_tokens")):
            tok = num(src.get("input_tokens")) + num(src.get("cache_write_tokens")) + num(src.get("output_tokens"))
            break
    if tok > 0:
        bump(entry, day, tokens=tok, model=entry.get("model"), session=sid)


def scan_pi(line, entry, path):
    if b'"type":"message"' not in line and b'"type": "message"' not in line:
        return
    rec = json.loads(line)
    if rec.get("type") != "message":
        return
    msg = rec.get("message")
    if not isinstance(msg, dict):
        return
    role = msg.get("role")
    day = local_day(rec.get("timestamp") or msg.get("timestamp"))
    if not day:
        return
    sid = f"pi:{path.stem}"
    if role == "user":
        bump(entry, day, prompts=1, session=sid)
    elif role == "assistant":
        u = msg.get("usage") or {}
        if not isinstance(u, dict):
            return
        tok = num(u.get("input")) + num(u.get("cacheWrite")) + num(u.get("output")) + num(u.get("reasoning"))
        model = str(msg.get("responseModel") or msg.get("model") or "")
        if tok > 0:
            bump(entry, day, tokens=tok, model=model, session=sid)


def scan_jsonl(path, entry, kind, parents=None):
    st = path.stat()
    if st.st_size < entry.get("offset", 0):
        entry.clear()
        entry["kind"] = kind
    entry.setdefault("days", {})
    off = entry.get("offset", 0)
    if st.st_size == off:
        return
    with open(path, "rb") as f:
        f.seek(off)
        data = f.read()
    end = data.rfind(b"\n") + 1
    for line in data[:end].splitlines():
        try:
            if kind == "claude":
                scan_claude(line, entry)
            elif kind == "codex":
                scan_codex(line, entry, path)
            elif kind == "agy":
                scan_agy(line, entry, path, parents or {})
            elif kind == "pi":
                scan_pi(line, entry, path)
        except (ValueError, TypeError, AttributeError):
            continue
    entry["offset"] = off + end


def _agy_parent_map():
    db = agy_root() / "conversation_summaries.db"
    if not db.is_file():
        return {}
    try:
        conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=1.5)
        try:
            cols = {r[1] for r in conn.execute("PRAGMA table_info(conversation_summaries)")}
            if "conversation_id" in cols and "parent_conversation_id" in cols:
                return {
                    str(c): str(p)
                    for c, p in conn.execute(
                        "SELECT conversation_id, parent_conversation_id FROM conversation_summaries "
                        "WHERE parent_conversation_id IS NOT NULL"
                    )
                    if c and p
                }
        finally:
            conn.close()
    except sqlite3.Error:
        pass
    return {}


def scan_opencode_days(cutoff_ms):
    """Read last DAYS of OpenCode activity from opencode.db (both V2 and V1 stores)."""
    days = {}
    db = opencode_db_path()
    if not db.is_file():
        return days
    try:
        conn = sqlite3.connect(db.resolve().as_uri() + "?mode=ro", uri=True, timeout=2)
    except sqlite3.Error:
        return days
    entry = {"days": days}
    seen_ids = set()
    try:
        conn.execute("PRAGMA query_only = ON")
        tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        children = set()
        if "session" in tables:
            scols = {r[1] for r in conn.execute("PRAGMA table_info(session)")}
            if {"id", "parent_id"} <= scols:
                children = {str(r[0]) for r in conn.execute("SELECT id FROM session WHERE parent_id IS NOT NULL")}

        def handle_row(mid, sid, raw, row_type, created):
            mid_s = str(mid)
            if mid_s in seen_ids:
                return
            try:
                rec = json.loads(raw)
            except Exception:
                return
            if not isinstance(rec, dict):
                return
            role = rec.get("role") or row_type
            t = rec.get("time") if isinstance(rec.get("time"), dict) else {}
            day = local_day(t.get("created") if t.get("created") is not None else created)
            if not day:
                return
            seen_ids.add(mid_s)
            sess_key = f"opencode:{sid}"
            if role == "user":
                if str(sid) not in children:
                    bump(entry, day, prompts=1, session=sess_key)
                return
            if role not in ("assistant", "compaction"):
                return
            tokens = rec.get("tokens") if isinstance(rec.get("tokens"), dict) else {}
            cache = tokens.get("cache") if isinstance(tokens.get("cache"), dict) else {}
            tok = num(tokens.get("input")) + num(tokens.get("output")) + num(tokens.get("reasoning")) + num(cache.get("write"))
            nested = rec.get("model") if isinstance(rec.get("model"), dict) else {}
            model = str(rec.get("modelID") or nested.get("id") or nested.get("modelID") or "")
            if tok > 0:
                bump(entry, day, tokens=tok, model=model, session=sess_key)

        if "session_message" in tables:
            cols = {r[1] for r in conn.execute("PRAGMA table_info(session_message)")}
            if {"id", "session_id", "type", "data"} <= cols:
                where = "WHERE time_created >= ?" if "time_created" in cols else ""
                params = (cutoff_ms,) if "time_created" in cols else ()
                tcol = "time_created" if "time_created" in cols else "NULL"
                for mid, sid, rtype, tc, raw in conn.execute(
                    f"SELECT id, session_id, type, {tcol}, data FROM session_message {where}", params
                ):
                    handle_row(mid, sid, raw, str(rtype or ""), tc)

        if "message" in tables:
            cols = {r[1] for r in conn.execute("PRAGMA table_info(message)")}
            if {"id", "session_id", "data"} <= cols:
                where = "WHERE time_created >= ?" if "time_created" in cols else ""
                params = (cutoff_ms,) if "time_created" in cols else ()
                tcol = "time_created" if "time_created" in cols else "NULL"
                for mid, sid, tc, raw in conn.execute(
                    f"SELECT id, session_id, {tcol}, data FROM message {where}", params
                ):
                    handle_row(mid, sid, raw, "", tc)
    except sqlite3.Error:
        pass
    finally:
        conn.close()
    return days


def pretty_model(m):
    if not m:
        return ""
    # Strip provider prefix (e.g. "cline-free/mimo-v2.6-flash" or "xiaomi/mimo-v2.6-flash")
    m = str(m).rstrip("/").split("/")[-1].split(":")[0]
    low = m.lower()
    if low.startswith("claude-"):
        parts = m[7:].split("-")
        words = [p for p in parts if not p.isdigit() or len(p) < 3]
        name = words[0].capitalize() if words else m
        nums = [p for p in words[1:] if p.isdigit()]
        return f"{name} {'.'.join(nums)}".strip()
    if low.startswith("gpt-"):
        bits = m.split("-")
        return "GPT-" + bits[1] + "".join(" " + b.capitalize() for b in bits[2:])
    if low.startswith("gemini-"):
        bits = [b for b in m.split("-") if b.lower() not in ("low", "medium", "high", "xhigh", "max")]
        return " ".join(b.capitalize() if not b[0].isdigit() else b for b in bits if b)
    if low.startswith("mimo-"):
        bits = [b for b in m.split("-") if b.lower() != "free"]
        return "MiMo " + " ".join(b.capitalize() if not b.startswith("v") else b for b in bits[1:])
    if low.startswith("deepseek-"):
        bits = [b for b in m.split("-") if b.lower() != "free"]
        return "DeepSeek " + " ".join(b.capitalize() if not b.startswith("v") else b for b in bits[1:])
    if low.startswith("glm"):
        return "GLM" + m[3:].replace("-", " ")
    # Generic cleanup
    bits = [b for b in m.replace("_", "-").split("-") if b.lower() not in ("free", "preview", "latest")]
    return " ".join(b.capitalize() if b.isalpha() and len(b) > 2 else b for b in bits[:4]) or m


def stats():
    cache = read_json(STATS_CACHE, {"files": {}})
    files = cache.setdefault("files", {})
    cutoff = time.time() - DAYS * 86400
    seen = set()

    agy_parents = _agy_parent_map()
    jsonl_sources = [
        ("claude", HOME / ".claude/projects", "*.jsonl"),
        ("codex", HOME / ".codex/sessions", "*.jsonl"),
        ("agy", agy_root() / "brain", "*/.system_generated/logs/transcript.jsonl"),
    ]
    for pi_root in pi_session_roots():
        jsonl_sources.append(("pi", pi_root, "*.jsonl"))

    for kind, root, pattern in jsonl_sources:
        if not root.exists():
            continue
        it = root.glob(pattern) if "/" in pattern else root.rglob(pattern)
        for path in it:
            try:
                if path.stat().st_mtime < cutoff:
                    continue
            except OSError:
                continue
            key = str(path)
            seen.add(key)
            entry = files.setdefault(key, {"kind": kind})
            try:
                scan_jsonl(path, entry, kind, agy_parents if kind == "agy" else None)
            except OSError:
                pass

    for key in list(files):
        if key not in seen:
            del files[key]
    write_json(STATS_CACHE, cache)

    # Fold all 5 agents into overall + per_agent 7-day summaries
    today = date.today()
    today_iso = today.isoformat()
    week_list = [(today - timedelta(days=i)).isoformat() for i in range(6, -1, -1)]
    week_set = set(week_list)

    per_day, models = {}, {}
    prompts_today, sessions_today = 0, set()
    per_agent_acc = {
        k: {"days": {}, "models": {}, "prompts_today": 0, "sessions_today": set()}
        for k in AGENT_ORDER
    }

    def fold(kind, days_map):
        nonlocal prompts_today
        acc = per_agent_acc.get(kind)
        for day, d in days_map.items():
            if day not in week_set:
                continue
            tok = d.get("tokens", 0)
            per_day[day] = per_day.get(day, 0) + tok
            if acc:
                acc["days"][day] = acc["days"].get(day, 0) + tok
            for m, t in d.get("models", {}).items():
                models[m] = models.get(m, 0) + t
                if acc:
                    acc["models"][m] = acc["models"].get(m, 0) + t
            if day == today_iso:
                prompts_today += d.get("prompts", 0)
                sessions_today.update(d.get("sessions", []))
                if acc:
                    acc["prompts_today"] += d.get("prompts", 0)
                    acc["sessions_today"].update(d.get("sessions", []))

    for entry in files.values():
        fold(entry.get("kind"), entry.get("days", {}))

    # OpenCode SQLite (fast indexed query for last 8 days)
    fold("opencode", scan_opencode_days(int(cutoff * 1000)))

    per_agent = {}
    for k, acc in per_agent_acc.items():
        top_m = max(acc["models"], key=acc["models"].get) if acc["models"] else ""
        per_agent[k] = {
            "today_tokens": acc["days"].get(today_iso, 0),
            "week_tokens": sum(acc["days"].values()),
            "today_prompts": acc["prompts_today"],
            "sessions_today": len(acc["sessions_today"]),
            "top_model": pretty_model(top_m) if top_m else "",
            "daily_tokens": [acc["days"].get(d, 0) for d in week_list],
        }

    busiest = max(per_day, key=per_day.get) if per_day else None
    top = max(models, key=models.get) if models else None
    live = live_sessions()
    return {
        "week_tokens": sum(per_day.values()),
        "today_tokens": per_day.get(today_iso, 0),
        "top_model": pretty_model(top) if top else "",
        "busiest_day": date.fromisoformat(busiest).strftime("%A") if busiest and per_day[busiest] else "",
        "prompts_today": prompts_today,
        "sessions_today": len(sessions_today),
        "live_total": sum(v["count"] for v in live.values()),
        "live": live,
        "per_agent": per_agent,
    }


# ── bar + launching + focusing ────────────────────────────────────────────

def fmt_tokens(n):
    if n >= 1e9:
        return f"{n / 1e9:.1f}B"
    if n >= 1e6:
        return f"{n / 1e6:.1f}M"
    if n >= 1e4:
        return f"{round(n / 1e3)}k"
    if n >= 1e3:
        return f"{n / 1e3:.1f}k"
    return str(n)


def bar():
    data = read_json(LIMITS_CACHE, None)
    if not data or time.time() - data.get("fetched_at", 0) > 15 * 60:
        try:
            data = limits()
        except Exception:
            data = data or {"agents": []}
    live = live_sessions()
    lines, worst = [], 0
    for a in data.get("agents", []):
        parts = [f'{w["label"]} {w["percent"]:.0f}%' for w in a.get("windows", [])]
        worst = max([worst] + [w["percent"] for w in a.get("windows", [])])
        lv = live.get(a["id"])
        tag = f" ● {lv['state']}" if lv else ""
        if parts:
            lines.append(f'{a["name"]}{tag}: ' + " · ".join(parts))
        elif lv:
            lines.append(f'{a["name"]}{tag} ({lv["cwd"]})')
        elif a.get("error"):
            lines.append(f'{a["name"]}: {a["error"]}')
        elif a.get("plan"):
            lines.append(f'{a["name"]} ({a["plan"]}): ready')
        else:
            lines.append(f'{a["name"]}: ready')

    live_count = sum(v["count"] for v in live.values())
    cls = "spent" if worst >= 100 else "high" if worst >= 80 else "ok"
    text = f"󰚩 {live_count}" if live_count > 0 else "󰚩"
    out({
        "text": text,
        "class": cls,
        "tooltip": "\n".join(lines + ["", "Click: agents card · Right-click: start Claude Code"]),
    })


SESSION = "main"     # every kitty attaches to it (~/.zshrc)


def sh(*cmd):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
        return p.returncode == 0, p.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return False, ""


def terminal_for_tmux(session_name=SESSION):
    """Hyprland address of the kitty window showing the tmux session, or None."""
    ok, clients = sh("tmux", "list-clients", "-t", session_name, "-F", "#{client_pid}")
    if not ok or not clients:
        return None
    ok, js = sh("hyprctl", "clients", "-j")
    windows = {w["pid"]: w["address"] for w in json.loads(js or "[]")} if ok else {}
    for pid in clients.split():
        pid = int(pid)
        while pid > 1:
            if pid in windows:
                return windows[pid]
            try:
                with open(f"/proc/{pid}/stat") as f:
                    pid = int(f.read().rsplit(")", 1)[1].split()[1])
            except (OSError, ValueError, IndexError):
                break
    return None


def focus_tmux(target):
    """Focus a live agent: either a tmux pane (`tmux:session:win.pane`) or a Hyprland window (`hypr:0x...`)."""
    if target.startswith("hypr:"):
        addr = target[5:]
        if addr:
            sh("hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{addr}" }})')
        return
    if target.startswith("tmux:"):
        target = target[5:]
    sess = target.split(":", 1)[0] if ":" in target else SESSION
    win_target = target.rsplit(".", 1)[0] if "." in target else target
    sh("tmux", "select-window", "-t", win_target)
    sh("tmux", "select-pane", "-t", target)
    addr = terminal_for_tmux(sess)
    if addr:
        sh("hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{addr}" }})')
    else:
        subprocess.Popen(["kitty", "--directory", str(HOME), "tmux", "attach", "-t", sess],
                         start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def run_in_tmux(command):
    """Start `command` in a new window of the tmux session, always in ~, and
    bring a terminal showing it to the front (or open one)."""
    home = str(HOME)
    if not sh("tmux", "has-session", "-t", SESSION)[0]:
        sh("tmux", "new-session", "-d", "-s", SESSION, "-c", home)
    ok, pane = sh("tmux", "new-window", "-t", f"{SESSION}:", "-c", home, "-P", "-F", "#{pane_id}")
    if not ok:
        return subprocess.Popen(["kitty", "--directory", home, "sh", "-c", command], start_new_session=True)
    sh("tmux", "send-keys", "-t", pane, "-l", command)
    sh("tmux", "send-keys", "-t", pane, "Enter")
    addr = terminal_for_tmux()
    if addr:
        sh("hyprctl", "dispatch", f'hl.dsp.focus({{ window = "address:{addr}" }})')
    else:
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
    elif a[0] == "focus" and len(a) >= 2:
        focus_tmux(a[1])
    elif a[0] == "launch" and len(a) >= 2 and a[1] in AGENTS:
        cmd = AGENTS[a[1]]["cmd"]
        prompt = a[2] if len(a) > 2 else ""
        run_in_tmux(cmd + (" " + shlex.quote(prompt) if prompt else ""))
    elif a[0] == "login" and len(a) == 2 and a[1] in AGENTS:
        run_in_tmux(AGENTS[a[1]]["login"])
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
