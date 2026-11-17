"""Live usage windows: when Claude's or Codex's 5h / weekly limit comes back.

Claude  GET https://api.anthropic.com/api/oauth/usage
        Bearer token from ~/.claude/.credentials.json (refreshed when needed)
Codex   GET https://chatgpt.com/backend-api/wham/usage
        Bearer token from ~/.codex/auth.json (refreshed when needed)

Neither endpoint is public API: it is what the CLIs themselves ask. Both are read-only and
cheap, so limit-alerts polls them. A refresh writes the rotated token back to the CLI's own
file (mode 600, atomic) only if nobody else refreshed it meanwhile.

Nothing here sends messages; see ~/.local/bin/limit-alerts for the watcher.
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
CLAUDE_CRED = HOME / ".claude/.credentials.json"
CLAUDE_USAGE = "https://api.anthropic.com/api/oauth/usage"
CLAUDE_TOKEN = "https://platform.claude.com/v1/oauth/token"
CLAUDE_CLIENT = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"     # Claude Code's own client id
CODEX_AUTH = HOME / ".codex/auth.json"
CODEX_USAGE = "https://chatgpt.com/backend-api/wham/usage"
CODEX_TOKEN = "https://auth.openai.com/oauth/token"
CODEX_CLIENT = "app_EMoamEEZ73f0CkXaXp7hrann"               # Codex CLI's own client id
USER_AGENT = "limit-alerts/1.0"
LIMIT = 100.0          # utilization at or above this means the window is used up


class UsageError(Exception):
    pass


class AuthError(UsageError):
    """Not logged in / token expired / refresh rejected: the user must act."""


@dataclass
class Window:
    key: str                     # "5h", "weekly", ...
    label: str                   # as shown in a message
    percent: float
    resets_at: float | None      # unix seconds

    @property
    def spent(self):
        return self.percent >= LIMIT


@dataclass
class Usage:
    provider: str
    windows: list = field(default_factory=list)
    error: str = ""
    auth_error: bool = False
    checked_at: float = 0.0

    @property
    def ok(self):
        return not self.error

    def window(self, key):
        return next((w for w in self.windows if w.key == key), None)

    def blocker(self):
        """The window keeping you out right now, or None. With several spent windows the
        last one to reset wins: the 5h reset is useless while the week is used up."""
        spent = [w for w in self.windows if w.spent and w.resets_at]
        return max(spent, key=lambda w: w.resets_at) if spent else None


# ---- small helpers ----------------------------------------------------------

def _load(path):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, ValueError) as e:
        raise AuthError(f"can't read {path}: {e}") from None


def _request(url, data=None, headers=None, timeout=25):
    """(status, body bytes); 4xx/5xx are returned, network failures raise UsageError."""
    req = urllib.request.Request(url, data=data, headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except (OSError, ValueError) as e:
        raise UsageError(f"network: {e}".replace("\n", " ")[:200]) from None


def _post_json(url, payload):
    """OAuth token endpoints: JSON first, form encoding as a fallback."""
    body = json.dumps(payload).encode()
    status, data = _request(url, body, {"Content-Type": "application/json",
                                        "Accept": "application/json",
                                        "User-Agent": USER_AGENT}, timeout=30)
    if status in (400, 415):
        body = urllib.parse.urlencode(payload).encode()
        status, data = _request(url, body, {"Content-Type": "application/x-www-form-urlencoded",
                                            "Accept": "application/json",
                                            "User-Agent": USER_AGENT}, timeout=30)
    return status, data


def _json(data):
    try:
        return json.loads(data)
    except ValueError:
        return {}


def _write_private(path, obj):
    """Replace a credentials file atomically, always mode 600."""
    path = Path(path)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f, indent=2)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


def _iso_ts(value):
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except (TypeError, ValueError):
        return None


def _num(value, default=None):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def label_for(seconds):
    if not seconds:
        return "5h"
    if abs(seconds - 18_000) < 120:
        return "5h"
    if abs(seconds - 604_800) < 600:
        return "weekly"
    if seconds % 3600 == 0:
        return f"{int(seconds // 3600)}h"
    return f"{int(seconds // 60)}m"


# ---- Claude ----------------------------------------------------------------

def _claude_creds():
    creds = _load(CLAUDE_CRED)
    oauth = creds.get("claudeAiOauth") or {}
    if not oauth.get("accessToken"):
        raise AuthError("Claude Code isn't signed in (~/.claude/.credentials.json)")
    return creds, oauth


def _refresh_claude(used_token):
    creds, oauth = _claude_creds()
    refresh = oauth.get("refreshToken")
    if not refresh:
        raise AuthError("Claude token expired and there's no refresh token: open Claude Code")
    status, data = _post_json(CLAUDE_TOKEN, {
        "grant_type": "refresh_token", "refresh_token": refresh, "client_id": CLAUDE_CLIENT})
    fresh = _json(data)
    if status != 200 or not fresh.get("access_token"):
        detail = fresh.get("error_description") or fresh.get("error") or f"HTTP {status}"
        raise AuthError(f"Claude token refresh failed ({detail}); open Claude Code once")
    # Someone (Claude Code itself) may have refreshed while we were talking to the server.
    current = _load(CLAUDE_CRED)
    now_oauth = current.get("claudeAiOauth") or {}
    if now_oauth.get("accessToken") and now_oauth["accessToken"] != used_token:
        return now_oauth["accessToken"]
    now_oauth["accessToken"] = fresh["access_token"]
    if fresh.get("refresh_token"):
        now_oauth["refreshToken"] = fresh["refresh_token"]
    if fresh.get("expires_in"):
        now_oauth["expiresAt"] = int((time.time() + _num(fresh["expires_in"], 0)) * 1000)
    if fresh.get("refresh_token_expires_in"):
        now_oauth["refreshTokenExpiresAt"] = int(
            (time.time() + _num(fresh["refresh_token_expires_in"], 0)) * 1000)
    current["claudeAiOauth"] = now_oauth
    _write_private(CLAUDE_CRED, current)
    return now_oauth["accessToken"]


def _claude_token(force=False):
    _, oauth = _claude_creds()
    token = oauth["accessToken"]
    expires = (_num(oauth.get("expiresAt"), 0) or 0) / 1000
    if force or (expires and expires - time.time() < 60):
        return _refresh_claude(token)
    return token


def claude():
    try:
        status, data = _request(CLAUDE_USAGE, headers={
            "Authorization": "Bearer " + _claude_token(),
            "anthropic-beta": "oauth-2025-04-20",
            "Accept": "application/json", "User-Agent": USER_AGENT})
        if status in (401, 403):
            status, data = _request(CLAUDE_USAGE, headers={
                "Authorization": "Bearer " + _claude_token(force=True),
                "anthropic-beta": "oauth-2025-04-20",
                "Accept": "application/json", "User-Agent": USER_AGENT})
        payload = _json(data)
        if status != 200:
            err = payload.get("error") or payload.get("message") or f"HTTP {status}"
            raise AuthError(f"Claude usage rejected ({err}); open Claude Code once") \
                if status in (401, 403) else UsageError(f"Claude usage: HTTP {status}")
        windows = []
        for key, label, field_ in (("5h", "5h", "five_hour"),
                                   ("weekly", "weekly", "seven_day")):
            w = payload.get(field_) or {}
            percent = _num(w.get("utilization"))
            if percent is None:
                continue
            windows.append(Window(key, label, percent, _iso_ts(w.get("resets_at"))))
        if not windows:
            raise UsageError("Claude usage: no windows in the response")
        return Usage("claude", windows, checked_at=time.time())
    except AuthError as e:
        return Usage("claude", error=str(e), auth_error=True, checked_at=time.time())
    except UsageError as e:
        return Usage("claude", error=str(e), checked_at=time.time())
    except Exception as e:      # a watcher must not die on a surprise
        return Usage("claude", error=f"{type(e).__name__}: {e}", checked_at=time.time())


# ---- Codex -----------------------------------------------------------------

def _codex_tokens():
    auth = _load(CODEX_AUTH)
    tokens = auth.get("tokens") or {}
    if not tokens.get("access_token"):
        raise AuthError("Codex isn't signed in (~/.codex/auth.json)")
    return auth, tokens


def _refresh_codex(used_token):
    auth, tokens = _codex_tokens()
    refresh = tokens.get("refresh_token")
    if not refresh:
        raise AuthError("Codex token expired and there's no refresh token: run `codex login`")
    status, data = _post_json(CODEX_TOKEN, {
        "client_id": CODEX_CLIENT, "grant_type": "refresh_token",
        "refresh_token": refresh, "scope": "openid profile email"})
    fresh = _json(data)
    if status != 200 or not fresh.get("access_token"):
        detail = fresh.get("error_description") or fresh.get("error") or f"HTTP {status}"
        raise AuthError(f"Codex token refresh failed ({detail}); run `codex login`")
    current = _load(CODEX_AUTH)
    now_tokens = current.get("tokens") or {}
    if now_tokens.get("access_token") and now_tokens["access_token"] != used_token:
        return now_tokens["access_token"]
    now_tokens["access_token"] = fresh["access_token"]
    if fresh.get("refresh_token"):
        now_tokens["refresh_token"] = fresh["refresh_token"]
    if fresh.get("id_token"):
        now_tokens["id_token"] = fresh["id_token"]
    current["tokens"] = now_tokens
    current["last_refresh"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    _write_private(CODEX_AUTH, current)
    return now_tokens["access_token"]


def _codex_token(force=False):
    _, tokens = _codex_tokens()
    token = tokens["access_token"]
    if force:
        return _refresh_codex(token)
    return token


def codex():
    try:
        auth, tokens = _codex_tokens()
        headers = {"Authorization": "Bearer " + _codex_token(),
                   "chatgpt-account-id": tokens.get("account_id") or "",
                   "Accept": "application/json", "User-Agent": USER_AGENT}
        status, data = _request(CODEX_USAGE, headers=headers)
        if status in (401, 403):
            headers["Authorization"] = "Bearer " + _codex_token(force=True)
            status, data = _request(CODEX_USAGE, headers=headers)
        payload = _json(data)
        if status != 200:
            err = payload.get("detail") or payload.get("error") or f"HTTP {status}"
            raise AuthError(f"Codex usage rejected ({err}); run `codex login`") \
                if status in (401, 403) else UsageError(f"Codex usage: HTTP {status}")
        rate = payload.get("rate_limit") or {}
        now = time.time()
        windows = []
        for key, field_ in (("primary_window", "5h"), ("secondary_window", "weekly")):
            w = rate.get(key) or {}
            percent = _num(w.get("used_percent"))
            if percent is None:
                continue
            reset = _num(w.get("reset_at")) or (
                now + _num(w.get("reset_after_seconds"), 0) if w.get("reset_after_seconds") else None)
            label = label_for(_num(w.get("limit_window_seconds"))) if w.get("limit_window_seconds") else field_
            windows.append(Window(label, label, percent, reset))
        if rate.get("limit_reached") and windows and not any(w.spent for w in windows):
            # If weekly is already exhausted, do not invent a second 5h blocker.
            windows[0].percent = max(windows[0].percent, LIMIT)
        if not windows:
            raise UsageError("Codex usage: no windows in the response")
        return Usage("codex", windows, checked_at=now)
    except AuthError as e:
        return Usage("codex", error=str(e), auth_error=True, checked_at=time.time())
    except UsageError as e:
        return Usage("codex", error=str(e), checked_at=time.time())
    except Exception as e:
        return Usage("codex", error=f"{type(e).__name__}: {e}", checked_at=time.time())


FETCH = {"claude": claude, "codex": codex}


def codex_recent_windows(now, max_age):
    """Recover recent used windows from bounded local rollout tails; no transcript text.

    These are scheduling hints only. The watcher requires successful live usage
    before announcing availability, and ignores other metered model buckets.
    """
    from .usage import tail_json

    files = sorted((HOME / ".codex/sessions").glob("*/*/*/*.jsonl"),
                   key=lambda p: p.stat().st_mtime, reverse=True)[:30]
    found = {}
    for path in files:
        for event in tail_json(path, size=300_000):
            payload = event.get("payload") or {}
            rate = payload.get("rate_limits") or {}
            if payload.get("type") != "token_count" or rate.get("limit_id") not in (None, "codex"):
                continue
            for key, field in (("5h", "primary"), ("weekly", "secondary")):
                w = rate.get(field) or {}
                reset, percent = _num(w.get("resets_at")), _num(w.get("used_percent"), 0)
                if reset and percent > 0 and now - max_age < reset <= now:
                    found[(key, reset)] = Window(key, key, percent, reset)
    return list(found.values())
