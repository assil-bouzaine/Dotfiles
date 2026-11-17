"""Telegram side: bot config, sending, reply routes and the alert log.

Secrets (never in git)  ~/.config/tg-notify/<bot>.env       TG_TOKEN=...  TG_CHAT=...
Mute switches           ~/.config/tg-notify/muted           every bot  (tg-notify off)
                        ~/.config/tg-notify/muted.<bot>     one bot    (tg-notify --bot X off)
State (safe to delete)  ~/.local/state/tg-notify/routes.<bot>   which tmux pane sent each alert
                        ~/.local/state/tg-notify/log            one line per alert
"""
import html
import fcntl
import json
import os
import re
import shlex
import time
import urllib.error
import urllib.parse
import urllib.request
from contextlib import contextmanager
from pathlib import Path

BOTS = ("claude", "codex")
HOME = Path.home()
CONF = Path(os.environ.get("XDG_CONFIG_HOME") or HOME / ".config") / "tg-notify"
STATE = Path(os.environ.get("XDG_STATE_HOME") or HOME / ".local/state") / "tg-notify"
LIMIT = 4096          # Telegram's cap, counted on the text after the HTML is parsed


class TelegramError(Exception):
    def __init__(self, msg, code=None):
        super().__init__(msg)
        self.code = code


def config(bot):
    """(token, chat id) from <bot>.env, or None when that bot isn't set up."""
    try:
        lines = (CONF / f"{bot}.env").read_text().splitlines()
    except OSError:
        return None
    env = {}
    for line in lines:
        key, _, val = line.partition("=")
        if val.strip():
            env[key.strip()] = shlex.split(val)[0]
    try:
        return env["TG_TOKEN"], int(env["TG_CHAT"])
    except (KeyError, ValueError):
        return None


def muted(bot):
    return (CONF / "muted").exists() or (CONF / f"muted.{bot}").exists()


def strip_html(text):
    return html.unescape(re.sub(r"<[^>]+>", "", text))


class Bot:
    def __init__(self, name, conf=None):
        conf = conf or config(name)
        if not conf:
            raise TelegramError(f"the {name} bot isn't set up (tg-notify --bot {name} setup)")
        self.name, (self.token, self.chat) = name, conf

    def api(self, method, retries=0, http_timeout=20, **params):
        """Call a Bot API method. Network errors, 429 and 5xx are retried with backoff."""
        data = urllib.parse.urlencode({
            k: json.dumps(v) if isinstance(v, (dict, list, bool)) else v
            for k, v in params.items() if v is not None}).encode()
        url = f"https://api.telegram.org/bot{self.token}/{method}"
        for attempt in range(retries + 1):
            wait = 2 ** (attempt + 1)
            try:
                with urllib.request.urlopen(url, data=data, timeout=http_timeout) as r:
                    return json.load(r)["result"]
            except urllib.error.HTTPError as e:
                try:
                    body = json.load(e)
                except ValueError:
                    body = {}
                err = TelegramError(body.get("description") or f"HTTP {e.code}", e.code)
                if e.code != 429 and e.code < 500:
                    raise err from None
                wait = max(wait, (body.get("parameters") or {}).get("retry_after") or 0)
            except (OSError, ValueError) as e:      # offline, timeout, garbled reply
                err = TelegramError(str(e).replace(self.token, "<token>"))
            if attempt < retries:
                time.sleep(wait)
        raise err

    def send(self, text, html_mode=False, buttons=None, silent=False, reply_to=None):
        """Send a message, return its id. Markup Telegram rejects is resent as plain text."""
        extra = dict(
            chat_id=self.chat,
            link_preview_options={"is_disabled": True},
            disable_notification=True if silent else None,
            reply_markup={"inline_keyboard": buttons} if buttons else None,
            reply_parameters={"message_id": reply_to, "allow_sending_without_reply": True}
            if reply_to else None)
        if html_mode:
            try:
                return self.api("sendMessage", retries=3, text=text, parse_mode="HTML",
                                **extra)["message_id"]
            except TelegramError as e:
                if e.code != 400:
                    raise
                text = strip_html(text)      # bad markup: better plain than lost
        return self.api("sendMessage", retries=3, text=text[:LIMIT] or "(empty)",
                        **extra)["message_id"]


def state_dir(sub=""):
    """~/.local/state/tg-notify (private: it holds the commands that wait for approval)."""
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    path = STATE / sub
    path.mkdir(mode=0o700, exist_ok=True)
    return path


# ---- routes: which pane sent which alert (tg-bridge reads them) ------------

@contextmanager
def file_lock(name):
    fd = os.open(state_dir() / (name + ".lock"), os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield

def remember(bot, message_id, **info):
    path = state_dir() / f"routes.{bot}"
    with file_lock(f"routes.{bot}"):
        with open(path, "a") as f:
            f.write(json.dumps({"mid": message_id, "t": int(time.time()), **info}) + "\n")
        _trim(path, keep=300, max_bytes=150_000)


def routes(bot):
    """Recorded alerts, newest first."""
    try:
        with file_lock(f"routes.{bot}"):
            lines = (STATE / f"routes.{bot}").read_text().splitlines()
    except OSError:
        return []
    out = []
    for line in reversed(lines):
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def route(bot, message_id):
    return next((r for r in routes(bot) if r.get("mid") == message_id), None)


def queue_alert(bot, texts, buttons=None, route=None):
    from .store import Store
    return Store(state_dir() / "bridge.sqlite3").enqueue(bot, dict(
        texts=texts, buttons=buttons, route=route, next=0))


def flush_outbox(bot):
    """Both hooks and the bridge can drain it; one sender per bot owns the lock."""
    from .store import Store
    from . import tmux
    fd = os.open(state_dir() / f"outbox-{bot}.lock", os.O_CREAT | os.O_RDWR, 0o600)
    with os.fdopen(fd, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        store, sender = Store(state_dir() / "bridge.sqlite3"), Bot(bot)
        for job in store.pending(bot):
            payload, route = job["payload"], job["payload"].get("route")
            if muted(bot):
                continue
            if route and route.get("kind") in ("approval", "question"):
                p = next((p for p in tmux.panes() if p["id"] == route["pane"]), None)
                if time.time() - job["created"] > 600 or not p or not tmux.same(p, route) \
                        or str(route.get("server")) != tmux.server() \
                        or (route.get("prompt") and p.get("prompt") != route["prompt"]) \
                        or (not route.get("opts") and p.get("state") != "waiting") \
                        or (route.get("opts") and not tmux.dialog_is(
                            p["id"], route["opts"], route.get("anchor") or "")):
                    store.remove(job["id"])
                    log(bot, "outbox", "expired prompt discarded")
                    continue
            try:
                while payload["next"] < len(payload["texts"]):
                    n = payload["next"]
                    last = n == len(payload["texts"]) - 1
                    mid = sender.send(payload["texts"][n], html_mode=True,
                                      buttons=payload.get("buttons") if last else None, silent=n > 0)
                    if route:
                        remember(bot, mid, **route)
                    payload["next"] += 1
                    store.checkpoint(job["id"], payload)
                store.remove(job["id"])
                log(bot, "outbox", "alert delivered")
            except TelegramError as e:
                if e.code in (400, 401, 403):
                    store.remove(job["id"])
                    log(bot, "outbox", f"FAILED permanently: {e}")
                else:
                    store.retry(job["id"], job["attempts"])
                    log(bot, "outbox", f"retry queued: {e}")
                break


# ---- log: one line per alert, for "why didn't I get that?" ------------------

def log(bot, kind, outcome):
    try:
        with file_lock("log"):
            with open(state_dir() / "log", "a") as f:
                f.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')}  {bot:<6}  {kind:<8}  {outcome}\n")
            _trim(STATE / "log", keep=500, max_bytes=100_000)
    except OSError:
        pass


def log_lines(n=20, bot=None):
    try:
        lines = (STATE / "log").read_text().splitlines()
    except OSError:
        return []
    if bot:
        lines = [l for l in lines if l.split()[2:3] == [bot]]
    return lines[-n:]


def _trim(path, keep, max_bytes):
    """Cut a file back to its last `keep` lines once it passes max_bytes."""
    try:
        if path.stat().st_size < max_bytes:
            return
        lines = path.read_text().splitlines()[-keep:]
        tmp = path.parent / (path.name + ".tmp")
        tmp.write_text("\n".join(lines) + "\n")
        tmp.replace(path)
    except OSError:
        pass
