# Agent notifications: desktop + Telegram

Claude Code and Codex tell you when they finish or need you: a desktop toast, a
tag on the tmux pane (status bar, `prefix Space`), and a Telegram message, one bot
per agent. Reply in Telegram and the text is typed into the agent's tmux pane.

Everything lives in the `agent-notify` stow package. Bot tokens don't: they stay in
`~/.config/tg-notify/` and never go in git.

## What reaches your phone

| When | Message | Buttons |
|---|---|---|
| A turn ends | **Claude finished** + project, then the final reply formatted for a phone (code blocks, tables as rows, `~` paths) | none (reply to continue) |
| A permission prompt has waited 6 s | **Claude needs approval**: what it wants to run, edit, fetch or search, with the exact command or diff | the dialog's own choices + Show screen |
| Claude asks a question (AskUserQuestion) | **Claude has a question** (or **has 3 questions**): every question with its options | the first question's options + Show screen; each tap brings the next question's buttons, then Submit |
| Codex approval still open after 6 s | **Codex needs approval**: the command, or the files a patch touches + the diff | same as Claude |
| Codex asks a question | **Codex has a question**: question + options | same |

Every message ends with **Context** (% and tokens), **5h limit** and **Weekly** (used % and
time to reset). No emojis.

Not sent to the phone (desktop toast only): Claude's "waiting for your input"
reminder, which only repeats "finished" a minute later, plus auth and computer-use
notices. If you answer a prompt at the PC within 6 s, the phone stays quiet:
Claude waits 6 s itself, and for Codex agent-notify waits and checks.

## Answering from Telegram

Each bot only talks to its own agent, and only from your chat id. Agents must run
in tmux.

| You send | Happens |
|---|---|
| a reply to an alert | typed into the session that sent it, then Enter |
| a plain message | typed into that agent (the session that alerted last, if several are open) |
| tap a choice under an alert | that choice is pressed, if the same dialog is still on screen; the button then says "Answered: …". "Type something." opens the answer field: send your answer as the next message |
| `/screen` | the bottom of the agent's screen, in monospace |
| `/key 1` · `/key Escape` · `/key Down Enter` | raw keys (letters, digits, Enter, Escape, Tab, Space, BSpace, arrows, Home/End, PageUp/PageDown, C-x) |
| `/list` | open agents and their state |
| `/claude text` · `/codex text` | type into the other agent from either chat |

Safety rules in the bridge:
- Text is never typed into a prompt that's waiting for a choice: Enter would pick its
  highlighted answer ("Yes"). You get the choices as buttons instead.
- A reply to an alert from a session that has since closed (or from before a reboot:
  tmux reuses pane ids) is refused instead of landing in some other pane.
- Only panes where `claude` / `codex` is the running command count, so a stale tag on
  a shell never gets typed into.
- Messages older than 10 minutes are dropped, so nothing old fires after the PC was off.

## Command line

```bash
tg-notify status              # bots, bridges, mute state, last alert
tg-notify log                 # last 20 alerts (sent / not sent and why / FAILED) + phone actions
tg-notify off                 # mute all Telegram alerts (desktop toasts stay); `on` undoes
tg-notify --bot codex off     # mute one bot
tg-notify --bot codex test    # test message
tg-notify "build done"        # message yourself from any script (Claude bot by default)
long-job | tg-notify --md     # pipe Markdown in, sent formatted
agent-notify --dry-run claude < payload.json   # show the alert a hook payload would make
```

## Files

```
agent-notify/                          (stow package)
  .local/bin/agent-notify              the hook: tmux tag, desktop toast, Telegram alert
  .local/bin/codex-notify -> agent-notify   name Codex's hooks.json calls (see below)
  .local/bin/tg-notify                 CLI: send, setup, on/off, status, test, log
  .local/bin/tg-bridge                 Telegram -> tmux, one per bot
  .local/lib/agent-notify/agentnotify/
    telegram.py   bot config, sending (retries, falls back to plain text), routes, log
    tmux.py       agent panes, screens, spotting a dialog's numbered choices
    markdown.py   reply Markdown -> Telegram HTML
    usage.py      the context / 5h / weekly footer
  .config/systemd/user/tg-bridge@.service   tg-bridge@claude, tg-bridge@codex

Outside the repo
  ~/.config/tg-notify/<bot>.env        TG_TOKEN + TG_CHAT (chmod 600), muted flags
  ~/.local/state/tg-notify/            routes.<bot> (alert -> pane), log, pending/
  ~/.claude/settings.json              hooks (below)
  ~/.codex/hooks.json                  hooks (below)
  ~/.claude/statusline-command.sh      saves ~/.cache/agent-usage/claude/<session>.json,
                                       where Claude's 5h / weekly numbers come from
  tmux package: agent-state            sets the pane tag both agents use
```

## Setup on a new machine

1. `stow agent-notify` (`install.sh` does it). Needs python, tmux, libnotify; the
   sound needs libpulse (`paplay`) and sound-theme-freedesktop.
2. Make a bot per agent: in Telegram, message **@BotFather**, send `/newbot`, and
   do it twice (Claude, Codex). Send each new bot `/start`, then in a terminal:
   ```bash
   tg-notify --bot claude setup     # asks for the token; finds your chat id
   tg-notify --bot codex setup      # starts tg-bridge@codex, sends a test
   ```
3. Claude Code hooks, in `~/.claude/settings.json` under `"hooks"`:
   ```json
   "Stop":              [{"hooks": [{"type": "command", "command": "~/.local/bin/agent-notify claude", "async": true}]}],
   "Notification":      [{"hooks": [{"type": "command", "command": "~/.local/bin/agent-notify claude", "async": true}]}],
   "PermissionRequest": [{"hooks": [{"type": "command", "command": "~/.local/bin/agent-notify claude", "async": true}]}],
   "UserPromptSubmit":  [{"hooks": [{"type": "command", "command": "~/.local/bin/agent-state claude working", "async": true}]}],
   "PostToolUse":       [{"hooks": [{"type": "command", "command": "~/.local/bin/agent-state claude working", "async": true}]}],
   "SessionEnd":        [{"hooks": [{"type": "command", "command": "~/.local/bin/agent-state claude clear"}]}]
   ```
   `PermissionRequest` only records what the prompt is about; it never answers it.
4. Codex hooks, in `~/.codex/hooks.json` (and `[features] hooks = true` in
   `config.toml`): `/usr/bin/python3 /home/<you>/.local/bin/codex-notify` with
   `"timeout": 5` for `PermissionRequest`, `Stop`, `UserPromptSubmit`, `PostToolUse`,
   and `PreToolUse` with matcher `(^|[.:])request_user_input(_async)?$`; `SessionEnd`
   runs `/home/<you>/.local/bin/agent-state codex clear`. Codex asks you to review new
   hooks once (`/hooks`).

## Troubleshooting

- **No alert?** `tg-notify log` says what happened to each one ("not sent: muted",
  "answered within 6 s", "FAILED: ..."). `tg-notify status` shows mute and bridges.
  A muted state lingers in `~/.config/tg-notify/muted*`.
- **Nothing logged at all:** the hook didn't run. Claude: check the `hooks` block.
  Codex: the hook may need review in Codex's `/hooks`.
- **Replies don't arrive:** `journalctl --user -u tg-bridge@claude -f`, and the agent
  must run inside tmux.
- **Footer missing for Claude:** the status line hasn't written its snapshot yet
  (`~/.cache/agent-usage/claude/`); it appears after the first reply.
- **No buttons on an approval:** the alert still arrives; the dialog on screen
  couldn't be read (agent outside tmux, or the screen showed a different prompt).
  Use `/screen` and `/key`.
- **See what a hook gets:** pipe a payload to `agent-notify --dry-run claude`; it
  prints the message, buttons and route without sending or touching anything.

## Why it's built this way

- **One hook for both agents** (`agent-notify`), so Claude and Codex alerts look and
  behave the same. The Telegram part runs in a background fork: Codex waits for its
  hooks, Claude runs them async, and neither is ever slowed down or blocked.
- **`codex-notify` is a symlink, not a rename:** Codex trusts each hook by a hash of
  its exact command line. Changing that line would switch the hooks off until you
  re-approved them in `/hooks`.
- **Codex hooks run in its background app-server**, whose `TMUX_PANE` points wherever
  that server started, so agent-notify finds the Codex pane by its working
  directory, and `agent-state codex clear` won't clear a pane codex still runs in.
- **Buttons check the screen before pressing:** the choices and the command they're
  about must still be on screen, or nothing is pressed. If a digit only moves the
  cursor, Enter confirms it.
- **Sends retry** on network errors (2, 4, 8 s), and bad markup is resent as plain
  text, so an alert isn't lost to a hiccup.
