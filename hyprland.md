# Hyprland (Lua) — cheat sheet

Config lives in the `hypr` stow package: `hypr/.config/hypr/`
(symlinked to `~/.config/hypr/` — edits apply instantly, no restow needed).

Requires Hyprland ≥ 0.55. Full option reference: https://wiki.hypr.land/configuring/

## Layout

```
hyprland.lua         # entry point — only loads modules, put nothing else here
conf.d/
  monitors.lua       # outputs, resolution, position, scale
  env.lua            # environment variables (hl.env)
  autostart.lua      # apps started once at login (hl.on + hl.exec_cmd)
  look.lua           # gaps, borders, blur, shadow, dwindle/master, groupbar, misc
  animations.lua     # bezier curves (hl.curve) + per-animation speed/style
  input.lua          # keyboard layouts/options, mouse, touchpad, gestures, per-device
  binds.lua          # all key/mouse/media bindings
  rules.lua          # window rules + workspace rules
hyprland.conf        # legacy backup — IGNORED while hyprland.lua exists
hyprlock.conf        # NOT lua — still hyprlang, edit as before
hypridle.conf        # NOT lua — still hyprlang, edit as before
scripts/             # helper shell scripts (e.g. wallpaper-cycle.sh)
```

## The 5-second workflow

1. Edit the relevant file under `conf.d/`.
2. Save — Hyprland **auto-reloads on save**. (Or run `hyprctl reload`.)
3. If something breaks, run `hyprctl configerrors` — it prints the file, line,
   and reason. Fix, save, done.

## Common changes

**Keybind** (`conf.d/binds.lua`):
```lua
hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"))
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

**Monitor** (`conf.d/monitors.lua`): get names with `hyprctl monitors`,
then e.g. `hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60",
position = "1366x0", scale = "1" })`.

**Window rule** (`conf.d/rules.lua`): find the class with `hyprctl clients`,
then e.g.
```lua
hl.window_rule({ match = { class = "^(discord)$" }, workspace = "5", float = true, center = true })
```

**Look** (`conf.d/look.lua`): everything is a Lua table inside `hl.config({...})`.
Gradient borders need the special shape:
`active_border = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }`,
while shadow color is a hex int: `color = 0xee1a1a1a` (= `rgba(1a1a1aee)`).

**Animation** (`conf.d/animations.lua`): define the curve first with `hl.curve`,
then reference it by name in `hl.animation({ leaf = "windows", speed = 4.79,
bezier = "easeOutQuint", style = "popin 87%" })`.

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
- **Keysym names, not characters.** `;` → `semicolon`, `Return` → `RETURN`.
- **`hl.bind` order matters on conflicts.** `SUPER+TAB` is bound twice here
  (group-next, then cycle-next wins) — remove one if you only want one behavior.
- **`initial_class` vs `class`** in window-rule matches: both accepted, but if a
  rule ever stops matching, try switching to `class`.

## Rollback

The old config is intact as `hyprland.conf`. To go back:
delete (or move away) `hyprland.lua` + `conf.d/`, then
`hyprctl reload full-reset`. Hyprland falls back to the `.conf` automatically.
