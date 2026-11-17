# Hyprland (Lua) — cheat sheet

Config lives in the `hypr` stow package: `hypr/.config/hypr/`
(symlinked to `~/.config/hypr/` — edits apply instantly, no restow needed).

For Hyprland 0.57 (Lua config). Full option reference: https://wiki.hypr.land/configuring/

## Layout

```
hyprland.lua          # entry point — only loads modules, put nothing else here
conf.d/
  monitors.lua        # outputs, resolution, position, scale
  env.lua             # environment variables (hl.env)
  autostart.lua       # apps started once at login (hl.on + hl.exec_cmd)
  look.lua            # gaps, borders, blur, shadow, layouts, groupbar, generated theme
  animations.lua      # bezier curves (hl.curve) + per-animation speed/style
  input.lua           # keyboard layouts/options, mouse, touchpad, gestures, per-device
  binds.lua           # all key/mouse/media bindings
  rules.lua           # window rules + workspace rules
  workspace-modes.lua # loaded last: tiling / floating, titlebars, boot defaults
hyprland.conf         # legacy backup — IGNORED while hyprland.lua exists
hyprlock.conf         # NOT lua — still hyprlang, edit as before
hypridle.conf         # NOT lua — still hyprlang, edit as before
scripts/              # keybinds.lua, tasks, layout-toggle, window-minimize, etc.
```

## The 5-second workflow

1. Edit the relevant file under `conf.d/`.
2. Save — Hyprland **auto-reloads on save**. (Or run `hyprctl reload`.)
3. If something breaks, run `hyprctl configerrors` — it prints the file, line,
   and reason. Fix, save, done.

## Common changes

**Keybind** (`conf.d/binds.lua`):
```lua
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd("kitty"))
```
Format is `"MODIFIERS + key"`. Key names must be valid keysyms:
`RETURN`, `SPACE`, `TAB`, `semicolon` (not `;` — that one errors),
`mouse_down`, `mouse_up`, `mouse:272`, `XF86AudioRaiseVolume`, etc.
Common actions: `hl.dsp.window.close()`, `hl.dsp.window.float({ action = "toggle" })`,
`hl.dsp.focus({ direction = "left" })`, `hl.dsp.focus({ workspace = 3 })`,
`hl.dsp.window.move({ workspace = 3 })`, `hl.dsp.group.toggle()`,
`hl.dsp.workspace.toggle_special("magic")`, `hl.dsp.exit()`.
Mouse-drag binds need `{ mouse = true }`; keys that must work on the
lock screen / while held need `{ locked = true }` / `{ repeating = true }`.

**Autostart** (`conf.d/autostart.lua`): add a line inside the
`hl.on("hyprland.start", function() ... end)` block:
```lua
hl.exec_cmd("waybar")
```
Only runs at login (reload won't re-trigger it — launch the app manually
once to test).
The resident Quickshell cards instance starts here with `qs -c cards -d`.
It runs the dock, app grid, network / Bluetooth / keybind cards and theme / font pickers.
The wallpaper is restored by `~/.config/quickshell/wallpicker/wallctl.py restore`.

**Monitor** (`conf.d/monitors.lua`): get names with `hyprctl monitors`,
then e.g. `hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60",
position = "1366x0", scale = "1" })`.

**Window rule** (`conf.d/rules.lua`): find the class with `hyprctl clients`,
then e.g.
```lua
hl.window_rule({ match = { class = "^(discord)$" }, workspace = "5", float = true, center = true })
```

**Look** (`conf.d/look.lua`): base options are a Lua table inside `hl.config({...})`.
Gradient borders need the special shape:
`active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }`,
while shadow color is a hex int: `color = 0xee1a1a1a` (= `rgba(1a1a1aee)`).
The generated theme file runs at the end and overrides the border and group colours.

**Animation** (`conf.d/animations.lua`): define the curve first with `hl.curve`,
then reference it by name in `hl.animation({ leaf = "windows", speed = 4.79,
bezier = "easeOutQuint", style = "popin 87%" })`.

## Themes and fonts

`~/.local/bin/theme` renders `~/.config/theme/templates/hyprland.lua.tpl`
to `~/.local/state/theme/hyprland.lua`. `conf.d/look.lua` runs it last with
`pcall(dofile, ...)`, so the base colours still work before the first render.
It sets borders, group colours and `THEME` (colours and font for titlebars).
Edit the palette or template, then run `theme apply`; generated files are
overwritten. `theme apply --render-only` writes files without reloading apps
or running hooks. `install.sh` runs `theme apply` after stow to install the
GTK, KDE and btop themes.

A theme or font switch runs the generated Lua with `hyprctl eval`.
When the titlebars plugin is loaded, it uses `hyprctl reload` so the titlebar
buttons pick up the colours too. `hyprlock.conf` sources the generated
`~/.local/state/theme/hyprlock.conf`; `wallctl.py` keeps its wallpaper at
`~/.local/state/wallpaper-current`. Themes, fonts and GTK / KDE / btop hooks are
covered in README.md.

## Floating workspaces

`hyprland.lua` loads `conf.d/workspace-modes.lua` after all other modules.
It provides tiling and floating modes, based on Omarchy 4.5's workspace
layouts. Every boot starts with workspace 1 floating and all others tiling.
`DEFAULT_FLOATING` in this file sets the boot defaults.
`scripts/layout-toggle [workspace-id]` (SUPER + ALT + L) switches the
focused workspace by default. Changes last until the next reboot.
It saves `$XDG_RUNTIME_DIR/workspace-modes` as one `<id> floating` line per
floating workspace, then calls `workspace_mode()` through `hyprctl eval`.
A reboot clears the runtime directory. On the first config load after
boot, Hyprland writes `1 floating`. Theme switches and `hyprctl reload`
restore the current modes from the file.

On a floating workspace, windows open at a comfortable size, cascaded,
with titlebars when the plugin is installed. Focus follows clicks and the
Quickshell dock shows at the bottom. Returning to tiling tiles windows
floated by the mode; dialogs and apps with their own float rules stay floating.
`scripts/window-minimize [window-address]` moves the active window by default
to `special:minimized` and tags its original workspace. It only works on
floating workspaces. The dock restores the window when clicked; switching
back to tiling also restores minimized windows.

The titlebars plugin is `omacom/omarchy-hyprland-titlebars` v0.4.0 at
`/usr/lib/omarchy-hyprland-titlebars/titlebars.so`. The `titlebars` stow
package supplies its PKGBUILD and `titlebars-rebuild`. `workspace-modes.lua`
loads the plugin at login because workspace 1 starts floating.
Run `titlebars-rebuild` as your user after every Hyprland upgrade, then
`hyprctl reload` or relog. Plugins must match the installed Hyprland build.
`titlebars-rebuild --check` reports
current (exit 0), stale (1), or not installed (2). The pacman hook at
`/etc/pacman.d/hooks/titlebars-rebuild.hook` only prints a reminder.
`install.sh` builds the plugin and installs the hook. A failed build warns;
floating workspaces and the dock work without titlebars.

## Desktop shortcuts

These cards and helpers are bound in `conf.d/binds.lua`.

| Keys | Does |
|---|---|
| SUPER + K | `quickshell/cards/card keys`: search and run keybinds |
| SUPER + T | `scripts/tasks`: open, focus or close the btop task manager |
| SUPER + ALT + L | `scripts/layout-toggle`: tiling / floating for this workspace |
| SUPER + ALT + M | `scripts/window-minimize`: minimize to the dock |
| SUPER + ALT + SPACE | `quickshell/cards/card apps`: app grid |
| SUPER + CTRL + T | `quickshell/cards/card themes`: theme picker |
| SUPER + CTRL + F | `quickshell/cards/card fonts`: font picker |

SUPER + K opens `quickshell/.config/quickshell/cards/KeysCard.qml`.
It lists every bind from `hypr/.config/hypr/scripts/keybinds.lua --json`.
Type to search descriptions, keys or groups. Rows are grouped and show
key chips. Press Enter or click a row to run the bind. Lua-function,
mouse and release binds are shown only. Run
`~/.config/hypr/scripts/keybinds.lua` without flags for plain text in a terminal.

SUPER + K used to focus up. Up is now only SUPER + Up.
SUPER + h, j and ; still focus left, down and right. SUPER + / is unbound.

SUPER + T and clicks on the bar's CPU / RAM run `~/.config/hypr/scripts/tasks`.
It opens btop in a floating kitty window with class `bar-tasks`.
Press or click again to focus it, or close it if it already has focus.
The `bar-tasks-floating` rule in `conf.d/rules.lua` centres and sizes it.
The helper sets font size 11 so it fits the 1366x768 panel.
Install the pacman package `btop` and stow the `btop` package.
`btop/.config/btop/btop.conf` uses Omarchy-style settings, sorts by memory
and enables vim keys. btop rewrites this file when it exits.
`theme/.config/theme/templates/btop.theme.tpl` renders `btop.theme`.
`theme/.config/theme/hooks/btop` copies it to
`~/.config/btop/themes/current.theme` and sends btop SIGUSR2 to reload it.

## Debugging

- `hyprctl configerrors` — first thing to run when the error overlay appears.
- `hyprctl getoption <section>:<name>` — e.g. `general:gaps_in`,
  `input:kb_layout`. Confirms a value actually applied.
- `hyprctl binds` — lists binds (lua ones show as `dispatcher: __lua`).
- `hyprctl workspacerules` — lists workspace rules (note: `layout` isn't shown).
- `hyprctl repl '<lua>'` — e.g. `hyprctl repl '1+1'`. Live Lua eval for
  experimenting (only works with the lua config active).
- `luac -p conf.d/*.lua hyprland.lua` — syntax check without touching Hyprland.

## Gotchas (learned during the migration)

- **Switching managers needs a full reset.** If `hyprland.lua` appears while the
  session is running on legacy, plain `reload` won't pick it up — use
  `hyprctl reload full-reset` once (or just relog).
- **One `workspace_rule()` per workspace.** Two calls for the same workspace
  overwrite each other — merge them into a single call.
- **`hyprctl dispatch` takes Lua now.** `hyprctl dispatch dpms off` silently
  fails — use `hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'` (also in
  scripts / hypridle.conf). Full API stubs: `/usr/share/hypr/stubs/hl.meta.lua`.
- **The GlobalShortcuts portal never assigns keys.** Apps that ask for a
  shortcut (e.g. Hex: "the desktop did not grant this shortcut") get nothing.
  Bind the app's CLI in `binds.lua` instead (see the Hex section below).
- **Keysym names, not characters.** `;` → `semicolon`, `Return` → `RETURN`.
- **Two binds on the same key both fire.** Use one bind with a Lua function
  instead (see `SUPER+TAB` in `binds.lua`: next group tab, else cycle windows).
- **`initial_class` vs `class`** in window-rule matches: both accepted, but if a
  rule ever stops matching, try switching to `class`.

## Hex (voice-to-text)

AUR package `hex-bin`; it runs as a systemd user service. Open it once with
`hex app` and download a model. Hyprland's portal never gives Hex the keys it
asks for, so `conf.d/binds.lua` calls Hex's CLI instead:

- Hold **SUPER + Z**, talk, let go → `hex dictation start` / `stop`
  (the stop bind uses `{ release = true }`; a bare `Z` release bind with
  `non_consuming` also stops it, so letting go of SUPER first is fine).
- **SUPER + SHIFT + Z** → `hex paste-last`
- **SUPER + ALT + Z** → `hex dictation cancel`

Hex types the text with `wtype`. Check it with `hex status` or
`journalctl --user -u hex`.

## Rollback

The old config is intact as `hyprland.conf`. To go back:
delete (or move away) `hyprland.lua` + `conf.d/`, then
`hyprctl reload full-reset`. Hyprland falls back to the `.conf` automatically.
