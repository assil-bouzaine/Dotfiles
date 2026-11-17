# Themes and fonts

`theme` switches the desktop's colours, font and wallpaper, like Omarchy 4.5.
The eight themes are `tokyo-night` (default), `catppuccin`, `gruvbox`,
`everforest`, `nord`, `kanagawa`, `ristretto` and `matte-black`.
They come from Omarchy v4.5.0 (MIT; `home/theme/.config/theme/themes/LICENSE-omarchy.txt`).

```bash
theme                              # current theme and font
theme list                         # also accepts --json
theme set catppuccin
theme apply                        # re-render after editing templates, reload apps, run hooks
theme apply --render-only          # write generated files only
theme font                         # or: theme font current
theme font list                    # also accepts --json
theme font set "JetBrainsMono Nerd Font"
```

SUPER + CTRL + T / F open the Quickshell theme / font pickers.
The installer includes 12 monospace Nerd Fonts from `[extra]`.
The default is JetBrainsMono Nerd Font. Changing it updates kitty, waybar,
swaync, rofi, the cards, dock and pickers, hyprlock and floating titlebars.
It also sets the fontconfig `monospace` alias in
`~/.config/fontconfig/conf.d/60-theme-monospace.conf`.

Templates in `home/theme/.config/theme/templates/*.tpl` render into
`~/.local/state/theme/`: `kitty.conf`, `colors.css` (bar and share picker),
`swaync.css`, `rofi.rasi`, `hyprlock.conf`, `hyprland.lua`, `btop.theme`,
`gtk.css` and `kde.colors`. Apps include these files; Quickshell's
`cards/Theme.qml` watches the generated `theme.json` (`wallpicker/Theme.qml`
links to it). A switch reloads kitty (SIGUSR1), waybar
(SIGUSR2), swaync (`--reload-css`) and Hyprland (`hyprctl eval`, or
`hyprctl reload` with titlebars loaded). Hooks in `~/.config/theme/hooks/`
apply GTK (`adw-gtk3-dark`, `gtk.css`, `settings.ini`) and KDE colours
(`kdeglobals`, alternating `ThemeA` / `ThemeB`). For btop,
`templates/btop.theme.tpl` renders `btop.theme`. `hooks/btop` copies it to
`~/.config/btop/themes/current.theme` and sends btop SIGUSR2.
Each theme remembers its last wallpaper in `~/.local/state/theme/backgrounds.json`.

To add a theme, copy a folder under `home/theme/.config/theme/themes/` to a new
name. Edit its `colors.toml` (Omarchy's palette keys, plus `title` and
`accent2`), add a `preview.jpg` and images in `backgrounds/`, then run
`theme set NAME`. The pre-theme GTK / KDE settings from this desktop are
backed up in `~/.local/share/theme-backup-2026-11-17/`.
