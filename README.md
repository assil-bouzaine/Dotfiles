# Dotfiles

GNU Stow–managed dotfiles (Arch Linux + Hyprland). Each top-level folder is a
stow package that mirrors `$HOME`:

| Package | Manages | Needs (beyond base) |
|---|---|---|
| `hypr` | `~/.config/hypr/` (Lua config, hyprlock, hypridle, workspace modes, keybinds, task manager, wallpaper scripts) | hyprland, hypridle, hyprlock, awww, jq, kitty, btop, dolphin + gwenview + archlinux-xdg-menu, polkit-kde-agent, rofi, brave-bin (AUR), hex-bin (AUR) + wtype, xdg-desktop-portal-hyprland, gnome-keyring, brightnessctl, pipewire + wireplumber (wpctl), playerctl, grim + slurp + wl-clipboard (screenshots) |
| `waybar` | `~/.config/waybar/` (top bar, rofi app launcher, workspace script) | waybar, networkmanager + nm-connection-editor, bluez + bluez-utils + blueman, swaync + libnotify, btop, python + python-gobject, hyprsunset, rofi, theme |
| `swaync` | `~/.config/swaync/` (small toasts styled like the bar, 10s timeout, no grouping) | swaync |
| `kitty` | `~/.config/kitty/` | kitty, theme |
| `btop` | `~/.config/btop/` (task manager, Omarchy-style settings) | btop, kitty, theme |
| `quickshell` | `~/.config/quickshell/` (dock, app grid, Wi-Fi / Bluetooth / keybind cards, theme / font / wallpaper pickers) | quickshell, qrencode, python, networkmanager, bluez |
| `share-picker` | `~/.config/hyprland-preview-share-picker/` (screen sharing picker) | hyprland-preview-share-picker-git (AUR), theme |
| `theme` | `~/.local/bin/theme`, `~/.config/theme/` (palettes, templates, GTK / KDE / btop hooks) | python, fontconfig, adw-gtk-theme, Nerd Fonts (below) |
| `titlebars` | `~/.local/bin/titlebars-rebuild`, `~/.local/share/titlebars/` (plugin PKGBUILD) | hyprland, base-devel, cmake, pkgconf |
| `tmux` | `~/.tmux.conf` | tmux, wl-clipboard (Wayland copy) |
| `vim` | `~/.vimrc` | vim |
| `zsh` | `~/.zshrc` | zsh, oh-my-zsh + plugins (see below), fzf, fd (fast Ctrl+F folder search, falls back to find), zsh-syntax-highlighting |
| `agent-notify` | `~/.local/bin/{agent-notify,tg-notify,tg-bridge}`, `~/.local/lib/agent-notify/`, `tg-bridge@.service`: Claude Code / Codex alerts on the desktop and in Telegram, answer from the phone | python, tmux, libnotify, libpulse (`paplay`), sound-theme-freedesktop |

Shared colours and fonts come from `theme` (default: Tokyo Night and
JetBrainsMono Nerd Font). Adwaita Sans and CaskaydiaCove Nerd Font are also installed.
Details per app: `hyprland.md` covers the Hyprland Lua config and the Hex dictation setup;
`agent-notify.md` covers the agent alerts (what gets sent, Telegram commands, setup).

## One-command install

On a fresh Arch install, logged in as your user, in a normal terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/assil-bouzaine/Dotfiles/main/install.sh)
```

`install.sh` does steps 1–5 below for you: packages (pacman + yay/AUR),
services, zsh + oh-my-zsh, clone to `~/.dotfiles` + stow, theme rendering,
titlebars and the wallpapers. sudo asks for the password once. Files
that are in stow's way are moved to `~/.dotfiles-backup/<time>/`, not deleted.
It's safe to re-run (from a clone: `~/.dotfiles/install.sh`). Afterwards: log
out and back in, then do the bits it prints (monitors, Hex model).

## Fresh machine setup (copy-paste in order)

The manual version of what `install.sh` does.

For Arch Linux and **Hyprland 0.57** (the config is Lua). Run everything in
a normal terminal. Commands with `sudo` need a real terminal to ask for the
password, so don't run them through Claude's `!` prompt.

### 1. Base packages (official repos)

```bash
sudo pacman -S --needed git base-devel stow zsh tmux vim curl fzf fd lua jq cmake \
  hyprland hypridle hyprlock awww \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  kitty dolphin gwenview archlinux-xdg-menu plasma-integration polkit-kde-agent rofi gnome-keyring \
  pipewire pipewire-pulse wireplumber brightnessctl playerctl \
  wl-clipboard wtype grim slurp zsh-syntax-highlighting \
  waybar networkmanager nm-connection-editor bluez bluez-utils blueman \
  quickshell qrencode \
  swaync libnotify htop btop python python-gobject hyprsunset sound-theme-freedesktop \
  ttf-jetbrains-mono-nerd ttf-cascadia-code-nerd \
  ttf-firacode-nerd otf-geist-mono-nerd ttf-victor-mono-nerd \
  otf-commit-mono-nerd ttf-martian-mono-nerd ttf-0xproto-nerd \
  ttf-lilex-nerd ttf-hack-nerd ttf-ibmplex-mono-nerd ttf-adwaitamono-nerd \
  adwaita-fonts adw-gtk-theme
```

What the less obvious ones are for:
- **xdg-desktop-portal-hyprland / -gtk:** screen sharing (Meet etc.) and file pickers.
- **pipewire-pulse, wireplumber:** audio and the volume keys (`wpctl`).
- **wtype:** lets Hex type the transcribed text.
- **grim, slurp:** the screenshot keys (Print = full screen, Shift+Print = area);
  wl-clipboard copies the shot.
- **fzf:** the fuzzy `cd` function in `.zshrc` and the vim fzf plugin.
- **dolphin, gwenview, plasma-integration, archlinux-xdg-menu:** file manager
  and image viewer; the last two give them Breeze styling and a working
  "Open with" menu outside Plasma (see `conf.d/env.lua`).
- **polkit-kde-agent:** password prompts for pkexec and settings apps.
- **lua:** gives `luac`, used to syntax-check the Hyprland config.
- **jq:** reads Hyprland's JSON in the workspace layout and minimize scripts.
- **cmake + base-devel:** build the floating window titlebars plugin.
- **quickshell:** the resident cards, dock, app grid and pickers.
- **adw-gtk-theme:** provides `adw-gtk3-dark` for the theme's GTK hook.
- **zsh-syntax-highlighting:** `.zshrc` sources it from `/usr/share/zsh/plugins/`.
- **networkmanager, bluez, blueman, swaync:** what the bar's Wi-Fi,
  Bluetooth and notification buttons open. swaync starts by itself (D-Bus)
  on the first notification.
- **python + python-gobject:** run the bar's workspace buttons and the apps pill next to them (`waybar/.../scripts/workspaces.py`; python-gobject finds the app icons).
- **btop:** the task manager on SUPER + T or a click on CPU / RAM on the bar.
- **hyprsunset:** the bar's night light (moon button: click on/off, scroll warmer/cooler).

Enable the network and Bluetooth services (if you used iwd during the Arch
install, disable it first so it doesn't fight NetworkManager):

```bash
sudo systemctl disable --now iwd 2>/dev/null
sudo systemctl enable --now NetworkManager bluetooth
```

### 2. AUR packages (not in the official repos)

```bash
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
(cd /tmp/yay-bin && makepkg -si)
yay -S brave-bin hex-bin hyprland-preview-share-picker-git
```

Optional: `hyprshutdown` (SUPER+M uses it if installed, otherwise plain exit),
`xclip` (tmux copy fallback outside Wayland).

### 3. Make zsh your shell + install oh-my-zsh

```bash
chsh -s /usr/bin/zsh
RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
mv ~/.zshrc ~/.zshrc.omz-default   # the installer writes one; stow needs the spot free
```

(`.zshrc` uses `plugins=(git zsh-autosuggestions zsh-syntax-highlighting)`.)

### 4. Clone + stow

```bash
git clone git@github.com:assil-bouzaine/Dotfiles.git ~/.dotfiles
# no SSH key on the new PC yet? use: https://github.com/assil-bouzaine/Dotfiles.git
cd ~/.dotfiles
mkdir -p ~/.local/bin ~/.local/lib ~/.local/share ~/.config/systemd/user \
  ~/.config/btop   # shared dirs stay out of the repo
stow hypr waybar swaync kitty tmux vim zsh agent-notify quickshell share-picker theme titlebars btop
~/.local/bin/theme apply
~/.local/bin/titlebars-rebuild
sudo install -Dm644 ~/.dotfiles/titlebars/pacman-hook/titlebars-rebuild.hook \
  /etc/pacman.d/hooks/titlebars-rebuild.hook
```

Check with `ls -la ~/.config/hypr`. You should see a `hypr -> ../.dotfiles/...`
symlink (stow folds whole directories when the target doesn't exist yet).
Create `~/.config/btop` before stow so its generated themes stay out of the
repo. `theme apply` runs the hooks, including btop's theme copy.

> If a target file already exists (e.g. a stock `~/.tmux.conf` or
> `~/.config/kitty/kitty.conf`), stow will refuse. Move it away first
> (`mv ~/.tmux.conf ~/.tmux.conf.stock`), then re-run stow.

### 5. Things that live outside this repo (do these manually)

- **Extra wallpapers:** download the set (10 calm cabin / misty lake images from
  wallhaven.cc) into `~/Pictures/Wallpapers/`:
  ```bash
  ~/.config/hypr/scripts/get-wallpapers.sh
  ```
  Pick one with SUPER + CTRL + SPACE (quickshell/wallpicker). It lists the
  current theme's wallpapers first, then `~/Pictures/Wallpapers/`.
  `wallctl.py` keeps `~/.local/state/wallpaper-current` pointing at the
  selected wallpaper; hyprlock shows it too.
- **Monitors:** `conf.d/monitors.lua` assumes `1366x768@60` + `HDMI-A-1` on the
  right. Run `hyprctl monitors`, fix names/modes, `hyprctl reload`.
- **Hex (voice-to-text, hold SUPER+Z):** open it once and download a model.
  The keys are Hyprland binds, see `hyprland.md` ("Hex (voice-to-text)").
- **Telegram alerts from Claude / Codex:** make one bot per agent with
  @BotFather, then `tg-notify --bot claude setup` and `tg-notify --bot codex setup`
  (tokens stay in `~/.config/tg-notify/`, never in the repo). The hook entries for
  `~/.claude/settings.json` and `~/.codex/hooks.json` are in `agent-notify.md`.
- **Optional extras referenced in `.zshrc`:** nvm (`~/.nvm`), Android SDK
  (`~/Android/sdk`), `~/.local/bin`, `~/.opencode/bin`. Only needed if you use them.

### 6. Log into Hyprland and verify

```bash
hyprctl configerrors   # must be empty
hyprctl monitors       # fix conf.d/monitors.lua if names differ
hyprctl binds          # check the shortcuts
```

- **vim:** the first launch downloads vim-plug and installs the plugins by
  itself (needs internet).
- **kitty:** every new window auto-attaches to the tmux session `main`.

First login autostarts: waybar, Quickshell cards (`qs -c cards -d`), the last
wallpaper, gnome-keyring, the polkit agent, and brave (hidden window).
hypridle and Hex run as systemd user services (`hypridle.service`, `hex.service`).

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
| SUPER + L | lock screen |
| SUPER + 1…0 | workspaces (also clickable on the bar) |
| SUPER + CTRL + SPACE | wallpaper picker (current theme first) |
| SUPER + ALT + L | switch the current workspace between tiling and floating |
| SUPER + ALT + M | minimize the active window to the dock (floating workspaces) |
| SUPER + ALT + SPACE | app grid |
| SUPER + CTRL + T | theme picker |
| SUPER + CTRL + F | font picker |

SUPER + K opens `quickshell/.config/quickshell/cards/KeysCard.qml` through
`~/.config/quickshell/cards/card keys`. It lists every bind from
`hypr/.config/hypr/scripts/keybinds.lua --json`. Type to search descriptions,
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
The `btop` stow package supplies `btop/.config/btop/btop.conf`.
It uses Omarchy-style settings, memory sorting and vim keys. btop rewrites
this file when it exits.

On the bar: right-click Wi-Fi for `nm-connection-editor`, right-click
Bluetooth to turn it on/off, click the bell for the notification panel
(right-click: do not disturb).

Window rules worth knowing: kitty → 1, Brave → 2 (Brave windows stack as
tabs, other apps can't join that group), VSCode / Dolphin → 3, Gwenview → 8, Spotify → 4.

## Themes and fonts

`theme` switches the desktop's colours, font and wallpaper, like Omarchy 4.5.
The eight themes are `tokyo-night` (default), `catppuccin`, `gruvbox`,
`everforest`, `nord`, `kanagawa`, `ristretto` and `matte-black`.
They come from Omarchy v4.5.0 (MIT; `theme/.config/theme/themes/LICENSE-omarchy.txt`).

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

Templates in `theme/.config/theme/templates/*.tpl` render into
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

To add a theme, copy a folder under `theme/.config/theme/themes/` to a new
name. Edit its `colors.toml` (Omarchy's palette keys, plus `title` and
`accent2`), add a `preview.jpg` and images in `backgrounds/`, then run
`theme set NAME`. The pre-theme GTK / KDE settings from this desktop are
backed up in `~/.local/share/theme-backup-2026-11-17/`.

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
It uses the same ink island style as the bar, with pinned, running and
minimized apps. Default pins: Brave, kitty, Dolphin, VS Code, Spotify,
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
`titlebars/.local/share/titlebars/PKGBUILD` and installed at
`/usr/lib/omarchy-hyprland-titlebars/titlebars.so`. The plugin loads at login
because workspace 1 starts floating. Run `titlebars-rebuild` as your user
after every Hyprland upgrade, then `hyprctl reload` or relog.
`titlebars-rebuild --check` reports whether the build matches Hyprland.
The pacman hook installed by `install.sh` only prints a reminder.
A failed build warns and leaves floating workspaces and the dock usable.

## Day-to-day stow usage

```bash
cd ~/.dotfiles
stow <pkg>        # link a package in
stow -D <pkg>     # unlink a package (removes symlinks only)
stow -R <pkg>     # restow (use after adding/removing files in a package)
stow -n -v <pkg>  # dry run — shows what would happen, changes nothing
```

New files inside an already-stowed directory appear automatically (directory
symlink). New top-level paths need `stow -R`.

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
