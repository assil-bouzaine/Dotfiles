# Dotfiles

My Arch Linux + Hyprland desktop: every config file, the full package list,
and one script that turns a fresh Arch install into this exact setup.

## New PC: one command

Install Arch (archinstall is fine: any network setup, a user with sudo), log in
as that user (a plain TTY is enough) and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/assil-bouzaine/Dotfiles/main/install.sh)
```

It asks for the sudo password (and, if it isn't set yet, your git email) at the
start, then runs on its own. Then reboot and pick Hyprland on the login screen.
The script is safe to run again, and nothing gets deleted: files in the way of a
link move to `~/.dotfiles-backup/<time>/`, and replaced `/etc` files keep a
`.pre-dotfiles` copy.

What it does (`~/.dotfiles/install.sh help`):

| Step | Does |
|---|---|
| `packages` | pacman packages from `packages/*.txt`, plus the video driver for this GPU |
| `system` | copies `system/etc/` into `/etc` (zram swap, disk scheduler, pacman hook) |
| `stow` | links every `home/<app>/` folder into `~` |
| `shell` | zsh as the login shell, oh-my-zsh |
| `aur` | yay, the AUR packages, the VS Code extensions |
| `agents` | Claude Code, Codex, their settings and hooks, Node LTS |
| `theme` | renders the theme (Tokyo Night, JetBrainsMono) for every app |
| `titlebars` | builds the titlebars plugin for floating workspaces |
| `wallpapers` | downloads the wallpaper set |
| `services` | ly login screen, NetworkManager, Bluetooth, idle lock, charger alert |
| `bots` | restores the Telegram bots if `~/Downloads/bots-*.tar.gpg` exists ([agent-notify](docs/agent-notify.md#moving-the-bots-to-another-machine-bots)) |

Only some steps: `~/.dotfiles/install.sh stow theme`. If a step fails, the
script names it and prints the command that carries on from there.

What's left by hand: sign in (`claude` then `/login`, `codex login`,
`gh auth login`), download a Hex model, and fix `conf.d/monitors.lua` if the
monitors differ. The user name `mclovin` is written in one place:
the `Exec` line of `home/discord/.local/share/applications/discord.desktop`.

## Layout

```
install.sh    the one command
packages/     what gets installed, one list per kind; comments say why
home/         one folder per app, laid out like ~ (linked in with GNU Stow)
system/       files for /etc (install.sh copies them, they need root)
docs/         how things work
```

| `home/` | Gives you |
|---|---|
| `hypr` | Hyprland: Lua config, binds, rules, workspace modes, hyprlock, hypridle, scripts |
| `waybar` | the top bar and its scripts |
| `quickshell` | dock, app grid, Wi-Fi / Bluetooth / agents / keybind cards, theme, font and wallpaper pickers |
| `swaync` | notifications |
| `theme` | the `theme` command, 8 themes, templates for every app |
| `titlebars` | builds the floating-window titlebars plugin (`titlebars-rebuild`) |
| `kitty`, `tmux`, `zsh`, `vim`, `btop` | terminal, multiplexer (+ project / agent pickers), shell, editor, task manager |
| `git` | shared git settings (the email stays in `~/.gitconfig`, outside the repo) |
| `agent-notify` | Claude / Codex alerts on the desktop and in Telegram, `bots` |
| `claude`, `codex` | status line and settings for the two agents |
| `share-picker` | the screen sharing picker |
| `discord` | Discord launcher with the H.264 decode fix |
| `brave`, `spotify` | Wayland flags |
| `vscode` | VS Code settings (extensions: `packages/vscode.txt`) |
| `wireplumber` | prefer the headset jack's microphone |
| `makepkg` | AUR builds on every CPU thread, no debug packages |
| `charger-alert` | a warning while a laptop runs on battery |

## Day to day

- Files in `~` are links into this repo: edit them in place, and `git status`
  shows the change. Folders like `~/.config/hypr` are linked whole, so new files
  there land in the repo by themselves.
- New file for an app: put it under `home/<app>/` at the same path it has in
  `~`, then `~/.dotfiles/install.sh stow`. A new app is just a new folder.
- New package: add it to the right `packages/*.txt` (AUR ones to `aur.txt`),
  then `install.sh packages` (or `install.sh aur`).
- Two files are merged instead of linked, because the apps rewrite them:
  `home/claude/settings.json` (missing keys are added to `~/.claude/settings.json`)
  and `home/codex/config.toml` (copied when `~/.codex/config.toml` doesn't exist).
- `~/.dotfiles/install.sh check` lists what this PC is missing or does
  differently from the repo, and changes nothing.
- Never in the repo: tokens (they move with `bots`), the git email, browser and
  mail profiles, projects.

## Docs

- [desktop.md](docs/desktop.md): the bar, cards, keyboard shortcuts, floating workspaces and dock, troubleshooting
- [theme.md](docs/theme.md): themes and fonts
- [hyprland.md](docs/hyprland.md): the Hyprland Lua config, Hex dictation
- [agent-notify.md](docs/agent-notify.md): Claude / Codex alerts, Telegram commands, moving the bots
- [titlebars.md](docs/titlebars.md): the titlebars plugin
