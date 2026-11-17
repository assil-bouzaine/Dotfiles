# Agent notifications: desktop + Telegram

Claude Code and Codex tell you when they finish or need you: a desktop toast, a
tag on the tmux pane (status bar, `prefix Space`), and a Telegram message, one bot
per agent. Reply in Telegram and the text is typed into the agent's tmux pane.

Everything lives in the `agent-notify` stow package. Bot tokens don't: they stay in
`~/.config/tg-notify/` and never go in git.

## What reaches your phone

| When | Message | Buttons |
|---|---|---|
| A turn ends | **Claude finished** + project, then the whole final reply formatted for a phone (code blocks, tables as rows, `~` paths). Nothing is trimmed: a long reply is split over several messages marked 1/3, 2/3…, only the first one buzzes, the footer is on the last | Continue, Show screen, Task controls, Switch session (reply to any part to continue) |
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

## Limit reset pings

`limit-alerts` (systemd: `limit-alerts.service`) watches both agents' usage windows,
asking the same endpoints their CLIs use every 2 minutes — every 20 seconds around a
reset. Every used window is tracked, even below 100%: when it resets you get
**Claude is back** / **Codex is back** with the other window's state. When a window
runs out you also get **Claude: 5h limit used up** with the time it comes back.

- It watches the **5h and the weekly** window. If the week is used up, the 5h reset
  doesn't help, so the ping follows whichever resets last.
- Failed reset deliveries stay pending until Telegram accepts them, including across
  service restarts. Recent Codex rollout usage recovers resets missed during the last
  two hours before the watcher was first started; a live check gates the alert.
- One message per window, not per poll: a reset time that moves means the limit was
  extended (a new message), and restarting the bot doesn't repeat what it already sent.
- It reads the OAuth tokens the CLIs store and refreshes them when they expire,
  writing the rotated token back to `~/.claude/.credentials.json` / `~/.codex/auth.json`
  atomically and mode 600 — and only if the CLI hasn't refreshed meanwhile.
- If a login really can't be refreshed, one message every 6 hours says what to run.
  `tg-notify off` mutes it like every other alert.
- One-way on purpose: the bots' update stream belongs to `tg-bridge`, so this never
  competes with your replies.

## Answering from Telegram

Each bot starts with its own agent selected. `/list` can explicitly select a Claude
or Codex session in either chat. Only your own account in your private chat is
accepted. Agents must run in tmux.

| You send | Happens |
|---|---|
| `/new` | starts a new session of this chat's agent: buttons for the folder, the model and the effort (below) |
| a reply to an alert | typed into the session that sent it, then Enter |
| a plain message | typed into your selected session; another session finishing never changes the destination |
| a screenshot or document, with an optional caption | saved privately on the PC and passed to the selected agent as a local attachment path plus your caption (up to 20 MB) |
| tap a choice under an alert | that choice is pressed, if the same dialog is still on screen; the button then says "Answered: …". "Type something." opens the answer field: send your answer as the next message |
| `/clear` · `/compact [notes]` | the agent's own command; you get back what it printed. `/compact` says "compacting", then again (with a buzz) when it's done |
| `/model` | the agent's model menu as buttons (Codex: model, then effort); a tap picks it and the reply says what it changed to. Cancel closes the menu. `/model sonnet` sets it straight |
| `/effort` | effort levels as buttons; or `/effort high` straight. Codex has no `/effort`: the bridge sends `/model --reasoning=high` |
| any other `/command` | typed into the agent as is (`/context`, `/usage`, `/resume` ...), what it prints comes back |
| `/screen` | the bottom of the agent's screen, in monospace |
| `/key 1` · `/key Escape` · `/key Down Enter` | raw keys (letters, digits, Enter, Escape, Tab, Space, BSpace, arrows, Home/End, PageUp/PageDown, C-x) |
| `/list` | clickable session picker, eight per page; your selection survives bridge restarts |
| `/control` | a task card with Stop, Continue, Show screen, Refresh status and Switch session |
| `/stop` | request an interrupt with Escape and cancel requests already waiting to be typed into that session |
| `/continue` | send "Continue with the current task" once the selected agent is idle |
| `/claude text` · `/codex text` | type into the other agent from either chat (`/claude /clear` works too) |

The bridge keeps `/new`, `/screen`, `/key`, `/list`, `/control`, `/stop`, `/continue`, `/help`, `/start`, `/claude`, `/codex`
for itself; every other `/command` goes to the agent. (Codex's own `/new`, a fresh chat,
is the same as its `/clear`; `/codex /new` still sends it.) Reply to an alert to aim it at
that session when several are open. What sticks:
- Claude: a `/model` pick and `/effort <level>` are saved as the default for new
  sessions (effort per model; `max` is this session only). `/clear` keeps the old session
  in `/resume`.
- Codex: a pick in the `/model` menu is saved as the default; the typed forms
  (`/effort high`, `/model <name> --reasoning=<level>`) are for this session only.

### Task cards and attachments

After a message is sent, its task card names the agent, project, folder and window.
While it is working, the card updates every 10 seconds with the terminal's working
line, elapsed time and update time. It stops updating when the task finishes, needs
an answer, or the session closes. `/control` opens a fresh card, including choices
for an open prompt. Continue sends a new instruction; it does not resume a suspended
operating-system process. Stop leaves an open approval or question for you to answer
explicitly, and it does not kill the agent or tmux.

Screenshots, image documents and other documents are downloaded into
`~/.local/state/tg-notify/attachments/`, with unique filenames and mode 600. The
agent receives the local path and your caption so its own tools can inspect the
file. A missing caption asks it to inspect the image or file. Downloads have a
20 MB cap, including when Telegram omits the file size. Files stay there for later
reference; they are not automatically deleted. Voice transcription and outgoing
artifact downloads are not part of this version.

Downloads run outside the polling loop. Stop and callback buttons remain available
while a file downloads. A pending message keeps the destination it had when it was
received, even if you select another session meanwhile. Stop cancels pending input
for that session across both bots; a new message sent after Stop can start work again.

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
- Routes also check the foreground process start time, boot ID, known conversation
  ID and a generation changed by `/clear`. Alerts from before this update have no
  process identity: use `/list` or a fresh alert instead. If a selected session ends,
  the bridge asks you to choose another rather than choosing one automatically.
- `/claude text` and `/codex text` use the same prompt guards as ordinary messages.
  Paste buffers are unique to each request; terminal actions are locked per pane
  across both services and failures are reported instead of acknowledged as sent.
- Prompt hooks record a request marker. A button cannot also confirm a replacement
  prompt that appeared after its initial keypress. Prompt buttons expire after
  10 minutes; `/control` refreshes them. Full command anchors are checked.
- Only panes where `claude` / `codex` is the running command count, so a stale tag on
  a shell never gets typed into.
- Messages older than 10 minutes are dropped, so nothing old fires after the PC was off.

### Delivery and restart recovery

Ordinary hook alerts now enter a SQLite outbox before sending. Transient network
failures retry in the background, including after a bridge restart. Multipart
replies checkpoint each delivered part; retries start at the first unfinished
part. Expired or replaced approval prompts are discarded. Permanent Telegram
errors (such as a blocked bot) are logged rather than retried forever.

Incoming updates are recorded before dispatch and their cursor is persisted. A
request interrupted by a crash is not automatically replayed: on restart a message
asks you to check the screen before sending it again. This favors avoiding duplicate
terminal actions. Telegram provides no idempotency key for outgoing messages, so a
crash after Telegram accepts a message but before the local checkpoint can still
duplicate that message. The queue starts after the hook has composed an alert; it
cannot recover a hook killed before that point.

The new state is `~/.local/state/tg-notify/bridge.sqlite3`. It holds selections,
task cards, incoming receipts and the outbox; keep it across bridge restarts.

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
limit-alerts status           # what's used now, when it resets, what was announced
limit-alerts check            # fetch once and print; sends and records nothing
limit-alerts --dry-run        # one watcher pass, print the messages instead of sending
limit-alerts test             # test message through both bots
```

## Files

```
agent-notify/                          (stow package)
  .local/bin/agent-notify              the hook: tmux tag, desktop toast, Telegram alert
  .local/bin/codex-notify -> agent-notify   name Codex's hooks.json calls (see below)
  .local/bin/tg-notify                 CLI: send, setup, on/off, status, test, log
  .local/bin/tg-bridge                 Telegram -> tmux, one per bot
  .local/bin/limit-alerts              limit reset watcher + its status/check/test CLI
  .local/lib/agent-notify/agentnotify/
    telegram.py   bot config, sending (retries, falls back to plain text), routes, log
    store.py      persistent selections, incoming receipts and outgoing alert queue
    media.py      private downloads of phone screenshots and documents
    tmux.py       agent panes, screens, a dialog's choices (numbered or not), busy or not,
                  what a command printed, new windows (starts tmux if needed)
    launch.py     /new: recent folders, each agent's models and effort levels, the
                  command line
    markdown.py   reply Markdown -> Telegram HTML (parts(): whole reply, split per message)
    usage.py      the context / 5h / weekly footer
    limits.py     live 5h / weekly windows from both CLIs, token refresh, what's blocking
  .config/systemd/user/tg-bridge@.service   tg-bridge@claude, tg-bridge@codex
  .config/systemd/user/limit-alerts.service the reset watcher

Outside the repo
  ~/.config/tg-notify/<bot>.env        TG_TOKEN + TG_CHAT (chmod 600), muted flags
  ~/.local/state/tg-notify/            routes.<bot> (alert -> pane), log, pending/,
                                       limits.json (what was already announced)
  ~/.claude/settings.json              hooks (below)
  ~/.codex/hooks.json                  hooks (below)
  ~/.claude/statusline-command.sh      saves ~/.cache/agent-usage/claude/<session>.json,
                                       where Claude's 5h / weekly numbers come from
  tmux package: agent-state            sets the pane tag both agents use
```

## Moving the bots to another machine: `bots`

The Claude, Codex and tg-drop bots run on one machine at a time (Telegram gives a bot's
messages to one reader only). `bots` moves all of them, with the same bots and tokens:

1. On the machine they run on now: `bots move`. It asks for a passphrase, stops the four
   services (`tg-drop`, `tg-bridge@claude`, `tg-bridge@codex`, `limit-alerts`), packs the
   tokens, tg-drop's config + state (its place in the chat, so nothing is downloaded twice)
   and tg-drop's code (a git bundle, so no GitHub login is needed) into
   `~/bots-<host>-<date>.tar.gpg` (AES-256 with that passphrase) and sends the file to your
   Claude chat.
2. On the new machine (Arch): save that file to `~/Downloads`, then
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/assil-bouzaine/Dotfiles/main/agent-notify/.local/bin/bots) install
   ```
   It installs the packages, clones `~/.dotfiles` and stows `agent-notify` + `tmux`, installs
   Claude Code and Codex if missing, restores the tokens (mode 600), clones tg-drop into
   `~/Projects/tg-drop` and installs its service, adds the hooks below to both agents, starts
   everything with linger, and says so in the Claude chat. Safe to re-run.
3. By hand afterwards: log in to the agents (`claude` → `/login`, `codex login`), trust the
   new hooks in Codex (`/hooks`), and for the remote's episode buttons load
   `~/Projects/tg-drop/extension` in Brave.

`bots off` / `bots on` / `bots status` stop, start and show the four services; `bots pack`
only writes the file. To take the bots back: `bots off` on one machine, `bots on` on the other.
If both run at once, the bridges fight over replies and tg-drop saves each file twice.

## Setup on a new machine (by hand, new bots)

1. `stow agent-notify` (`install.sh` does it). Needs python, tmux, libnotify; the
   sound needs libpulse (`paplay`) and sound-theme-freedesktop.
2. Make a bot per agent: in Telegram, message **@BotFather**, send `/newbot`, and
   do it twice (Claude, Codex). Send each new bot `/start`, then in a terminal:
   ```bash
   tg-notify --bot claude setup     # asks for the token; finds your chat id
   tg-notify --bot codex setup      # starts tg-bridge@codex, sends a test
   ```
   Then `systemctl --user enable --now limit-alerts` for the reset pings (it reads the
   CLIs' own tokens, so nothing else to configure).
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
- **Old buttons say the session ended:** choose the session again with `/list`.
  Old routes without a process identity are intentionally refused. If several
  Codex sessions share one working directory and none has a known conversation tag,
  their hook alerts remain unrouted until they can be identified; `/list` and
  `/control` still let you explicitly control the pane you chose.
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

- **No limit ping?** `limit-alerts status` shows both windows and what was announced;
  `journalctl --user -u limit-alerts -f` shows polls and send failures, and
  `tg-notify log` has a `limit` line for each message.

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
- **Sends retry** on network errors (2, 4, 8 s), then hook alerts remain in the
  persistent outbox for background retries. Bad markup is resent as plain text.
- **Limit pings use the CLIs' own OAuth tokens and endpoints**, not the public API —
  neither vendor exposes usage there. The tokens are refreshed the way the CLIs do it,
  so the watcher keeps working while you're away from the machine.
- **Codex's effort is typed, not passed:** its only way to set it on the command line is
  `-c model_reasoning_effort=...`, and any `-c` makes Codex run without its shared
  background server ("requires embedded mode"). `-m` doesn't, so `/new` starts
  `codex -m <model>` and sends `/model --reasoning=<level>` (this session only) once
  it's up.
- **A tmux the bridge starts gets its own systemd scope:** started from inside the
  bridge's service it would belong to it, and a bridge restart would kill tmux with every
  agent in it. It starts through an interactive zsh (with `TMUX` set so `~/.zshrc`
  doesn't try to attach), so it gets the same full PATH as one kitty starts.

## Checking and loading changes

From the dotfiles repository root:

```sh
python3 -B -m unittest discover -s agent-notify/tests -v
systemctl --user restart tg-bridge@claude.service tg-bridge@codex.service
```

The checks use temporary state, mocked Telegram calls and isolated terminal
processes. They never type into your running agents or send test messages to your
bots. The library directory is stowed as a symlink, so no reinstall is needed;
restarting the two bridges loads the new commands and controls. Hook subprocesses
read the updated source on their next invocation.
