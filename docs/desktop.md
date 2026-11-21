# The desktop: bar, cards, shortcuts, floating workspaces

## Bar, cards and shortcuts

The top bar is waybar with floating pills: Arch logo (app launcher),
workspaces, date and time, CPU / RAM / download speed, Wi-Fi, night light, Bluetooth, tray
and notifications. The launcher opens as a rofi card; Wi-Fi, Bluetooth and keybinds
use the resident Quickshell cards. Click outside a card (or press its key
again) to close it.

| Keys | Does |
|---|---|
| SUPER + D | app launcher card |
| SUPER + N | Wi-Fi card: `quickshell/cards/NetCard.qml` (networks, Wi-Fi on/off) |
| SUPER + T | task manager: `hypr/scripts/tasks` (btop in a floating kitty window) |
| SUPER + K | keybind card: `quickshell/cards/card keys` (search and run binds) |
| SUPER + B | Bluetooth card: `quickshell/cards/BtCard.qml` (power, scan, connect / pair) |
| SUPER + CTRL + A | agents card: `quickshell/cards/AgentsCard.qml` (Claude Code, Codex, Antigravity, OpenCode, Pi: limits, 7-day activity, live tmux jump & per-agent launch) |
| SUPER + L | lock screen |
| SUPER + 1…0 | workspaces (also clickable on the bar) |
| SUPER + CTRL + SPACE | wallpaper picker (current theme first) |
| SUPER + ALT + L | switch the current workspace between tiling and floating |
| SUPER + ALT + M | minimize the active window to the dock (floating workspaces) |
| SUPER + ALT + SPACE | app grid |
| SUPER + CTRL + T | theme picker |
| SUPER + CTRL + F | font picker |

SUPER + K opens `home/quickshell/.config/quickshell/cards/KeysCard.qml` through
`~/.config/quickshell/cards/card keys`. It lists every bind from
`home/hypr/.config/hypr/scripts/keybinds.lua --json`. Type to search descriptions,
keys or groups. Rows are grouped and show key chips. Press Enter or click
a row to run the bind. Lua-function, mouse and release binds are shown only.
Run `~/.config/hypr/scripts/keybinds.lua` without flags for plain text in a terminal.

SUPER + K used to focus up. Use SUPER + Up now. SUPER + h, j and ; still
focus left, down and right. SUPER + / is unbound.

SUPER + T or a click on the bar's CPU / RAM runs `~/.config/hypr/scripts/tasks`.
It opens btop in a floating kitty window. Press or click again to focus it,
or close it if it already has focus. The window class is `bar-tasks`.
The `bar-tasks-floating` rule in `conf.d/rules.lua` centres it.
Font size 11 keeps it usable on the 1366x768 panel.
The `btop` stow package supplies `home/btop/.config/btop/btop.conf`.
It uses Omarchy-style settings, memory sorting and vim keys. btop rewrites
this file when it exits.

On the bar: right-click Wi-Fi for `nm-connection-editor`, right-click
Bluetooth to turn it on/off, click the bell for the notification panel
(right-click: do not disturb).

Window rules worth knowing: kitty → 1, Brave → 2 (Brave windows stack as
tabs, other apps can't join that group), VSCode / Dolphin → 3, Gwenview → 8, Spotify → 4.

## Floating workspaces and the dock

Every boot starts with workspace 1 floating and all others tiling.
SUPER + ALT + L switches the current workspace between tiling and floating.
The choice lasts until the next reboot.
`conf.d/workspace-modes.lua` loads last. `DEFAULT_FLOATING` sets the boot defaults.
Modes live in `$XDG_RUNTIME_DIR/workspace-modes`, one `<id> floating` line
per floating workspace. A reboot clears the runtime directory.
On the first config load after boot, Hyprland writes `1 floating`.
Theme switches and `hyprctl reload` keep the current modes.
Floating windows open at a comfortable size, cascaded. Focus follows clicks.
Titlebars have close, maximize and minimize buttons; SUPER + ALT + M also
minimizes to the dock. Switching back to tiling restores minimized windows.

The Quickshell dock appears at the bottom only on floating workspaces.
It matches Omarchy 4.5's transparent borderless dock (bare floating icons with
no box or background), with pinned, running and minimized apps. Default pins: Brave, kitty, Dolphin, VS Code, Spotify,
Discord and Thunderbird (installed apps only). Click to focus, restore or
start an app; middle-click for a new window. Right-click for New window,
Keep in / Remove from dock, or Quit. Drag icons to reorder them.
Right-click the first button to set auto-hide; pins and auto-hide are saved
in `~/.local/state/dock.json`.

The first dock button or SUPER + ALT + SPACE opens the app grid. Type to
search, use the arrows and Enter to launch, or right-click to keep an app
in the dock. The helper `~/.config/quickshell/cards/card` accepts `apps`,
`themes`, `fonts` and `keys`.

Titlebars use `omacom/omarchy-hyprland-titlebars` v0.4.0, built from
`home/titlebars/.local/share/titlebars/PKGBUILD` and installed at
`/usr/lib/omarchy-hyprland-titlebars/titlebars.so`. The plugin loads at login
because workspace 1 starts floating. Run `titlebars-rebuild` as your user
after every Hyprland upgrade, then `hyprctl reload` or relog.
`titlebars-rebuild --check` reports whether the build matches Hyprland.
The pacman hook installed by `install.sh` only prints a reminder.
A failed build warns and leaves floating workspaces and the dock usable.

## Troubleshooting

- **Hyprland ignores `hyprland.lua`:** the lua-vs-legacy manager is chosen at
  startup. After adding the `.lua`, run `hyprctl reload full-reset` once (or relog).
- **Error overlay after editing:** `hyprctl configerrors` prints file + line.
- **Lua syntax check without reloading:** `luac -p ~/.config/hypr/hyprland.lua ~/.config/hypr/conf.d/*.lua`
- **Live Lua eval:** `hyprctl repl '1+1'` (proves the lua manager is active).
- **Bar workspace buttons do nothing:** waybar's built-in
  `hyprland/workspaces` sends old-style `dispatch workspace N`, which the Lua
  config rejects. That's why the bar uses `scripts/workspaces.py` + ten
  `custom/ws-N` modules instead; don't switch back.
- **Bluetooth card says it can't turn on:** check `rfkill list bluetooth`;
  the card runs `rfkill unblock bluetooth` first, which needs your user to be
  logged in on the active seat.
- **Rollback to legacy conf:** delete `hyprland.lua` + `conf.d/`, then
  `hyprctl reload full-reset` — the kept `hyprland.conf` takes over.
