# Agent notifications: desktop + Telegram

Claude Code and Codex tell you when they finish or need you: a desktop toast, a
tag on the tmux pane (status bar, `prefix Space`), and a Telegram message, one bot
per agent. Reply in Telegram and the text is typed into the agent's tmux pane.

Everything lives in the `agent-notify` stow package. Bot tokens don't: they stay in
`~/.config/tg-notify/` and never go in git.

## What reaches your phone

| When | Message | Buttons |
|---|---|---|
| A turn ends | **Claude finished** + project, then the whole final reply formatted for a phone (code blocks, tables as rows, `~` paths). Nothing is trimmed: a long reply is split over several messages marked 1/3, 2/3…, only the first one buzzes, the footer is on the last | none (reply to any part to continue) |
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
| `/new` | starts a new session of this chat's agent: buttons for the folder, the model and the effort (below) |
| a reply to an alert | typed into the session that sent it, then Enter |
| a plain message | typed into that agent (the session that alerted last, if several are open) |
| tap a choice under an alert | that choice is pressed, if the same dialog is still on screen; the button then says "Answered: …". "Type something." opens the answer field: send your answer as the next message |
| `/clear` · `/compact [notes]` | the agent's own command; you get back what it printed. `/compact` says "compacting", then again (with a buzz) when it's done |
| `/model` | the agent's model menu as buttons (Codex: model, then effort); a tap picks it and the reply says what it changed to. Cancel closes the menu. `/model sonnet` sets it straight |
| `/effort` | effort levels as buttons; or `/effort high` straight. Codex has no `/effort`: the bridge sends `/model --reasoning=high` |
| any other `/command` | typed into the agent as is (`/context`, `/usage`, `/resume` ...), what it prints comes back |
| `/screen` | the bottom of the agent's screen, in monospace |
| `/key 1` · `/key Escape` · `/key Down Enter` | raw keys (letters, digits, Enter, Escape, Tab, Space, BSpace, arrows, Home/End, PageUp/PageDown, C-x) |
| `/list` | open agents and their state |
| `/claude text` · `/codex text` | type into the other agent from either chat (`/claude /clear` works too) |

The bridge keeps `/new`, `/screen`, `/key`, `/list`, `/help`, `/start`, `/claude`, `/codex`
for itself; every other `/command` goes to the agent. (Codex's own `/new`, a fresh chat,
is the same as its `/clear`; `/codex /new` still sends it.) Reply to an alert to aim it at
that session when several are open. What sticks:
- Claude: a `/model` pick and `/effort <level>` are saved as the default for new
  sessions (effort per model; `max` is this session only). `/clear` keeps the old session
  in `/resume`.
- Codex: a pick in the `/model` menu is saved as the default; the typed forms
  (`/effort high`, `/model <name> --reasoning=<level>`) are for this session only.

### Starting a session: `/new`

Send `/new` in the Claude chat for Claude, in the Codex chat for Codex. One message asks,
with buttons, and updates as you tap (Back and Cancel on each step):

1. **Folder:** the 8 you used last, with either agent or in `~/Projects` (`~` always).
   *Other folder…* asks you to type one: a project name (`radar`, any case), `~/code/app`
   or `/mnt/data/app`. A folder that doesn't exist yet gets a *Create it* button.
2. **Model:** Claude: Opus, Sonnet, Fable, Haiku (always the newest of each), your default
   marked. Codex: the list from its own `/model` menu.
3. **Effort:** Default, or a level the model takes.

Or say it all at once, in any order and any case: `/new radar opus max`,
`/new ~/.dotfiles sonnet`, `/new /mnt/data/app gpt-6-luna low`. Whatever you leave out is
asked. Replying to the `/new` message with any of these works too.

It opens a window named `<folder>:<agent>` in the tmux session `main` (the one kitty
attaches to), the way `prefix f` does: a shell with the agent started in it, so quitting
the agent leaves a shell. The window isn't focused, so it doesn't pull the PC away from
what's on screen. If tmux isn't running (after a reboot, say), the bridge starts it.
If the agent asks something before it starts (Claude: "trust this folder?" in a new
folder), you get that as buttons. Then **Claude is ready** says the model and effort it
runs with ("Sonnet 5.5 with high effort") and the window; your next message goes to
that session.

The model and effort are for that session only; your defaults don't change. Claude gets
`--model`/`--effort`; Codex gets `-m`, and the bridge types `/model --reasoning=<level>`
once it's up (Codex has no effort flag, see below).

Safety rules in the bridge:
- Text is never typed into a prompt that's waiting for a choice: Enter would pick its
  highlighted answer ("Yes"). That covers any numbered dialog on screen, alert or not
  (one with a cursor that hides the input box), and unnumbered lists like Claude's folder
  trust check, where Enter means "No, exit". You get the choices as buttons instead.
- Slash commands wait for a free agent: none is typed while it's mid-turn (its spinner is
  on screen); you're told to send it again later or stop it with `/key Escape`. A bare
  `/` is refused (Enter would run whatever the command list shows first).
- A command that leaves a panel open (`/status`, `/config` ...) says so: anything you
  send next would go into the panel. `/key Escape` closes it.
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
    tmux.py       agent panes, screens, a dialog's choices (numbered or not), busy or not,
                  what a command printed, new windows (starts tmux if needed)
    launch.py     /new: recent folders, each agent's models and effort levels, the
                  command line
    markdown.py   reply Markdown -> Telegram HTML (parts(): whole reply, split per message)
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
- **A `/command` from the phone did nothing:** `tg-notify log` has a "phone" line for
  each one: typed, or held back (prompt on screen / agent working). Not in the `/`
  menu? The bridge registers it on start: `systemctl --user restart tg-bridge@claude`.
- **See what a hook gets:** pipe a payload to `agent-notify --dry-run claude`; it
  prints the message, buttons and route without sending or touching anything.
- **`/new` didn't come up:** the bridge says why (the agent exited, never started, or
  isn't ready after a minute: see `/screen`), and `tg-notify log` has a "phone" line with
  the command it typed and the window. No `/new` in the `/` menu: restart the bridge.

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
- **Codex's effort is typed, not passed:** its only way to set it on the command line is
  `-c model_reasoning_effort=...`, and any `-c` makes Codex run without its shared
  background server ("requires embedded mode"). `-m` doesn't, so `/new` starts
  `codex -m <model>` and sends `/model --reasoning=<level>` (this session only) once
  it's up.
- **A tmux the bridge starts gets its own systemd scope:** started from inside the
  bridge's service it would belong to it, and a bridge restart would kill tmux with every
  agent in it. It starts through an interactive zsh (with `TMUX` set so `~/.zshrc`
  doesn't try to attach), so it gets the same full PATH as one kitty starts.
