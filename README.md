# Dotfiles

GNU Stow–managed dotfiles (Arch Linux + Hyprland). Each top-level folder is a
stow package that mirrors `$HOME`:

| Package | Manages | Needs (beyond base) |
|---|---|---|
| `hypr` | `~/.config/hypr/` (Lua config, hyprlock, hypridle, wallpaper scripts) | hyprland, hypridle, hyprlock, awww, kitty, dolphin + gwenview + archlinux-xdg-menu, polkit-kde-agent, rofi, brave-bin (AUR), handy-bin (AUR) + wtype, xwaylandvideobridge (AUR), xdg-desktop-portal-hyprland, gnome-keyring, brightnessctl, pipewire + wireplumber (wpctl), playerctl |
| `waybar` | `~/.config/waybar/` (top bar, app launcher / Wi-Fi / Bluetooth cards, workspace script) | waybar, networkmanager + nm-connection-editor, bluez + bluez-utils + blueman, networkmanager-dmenu-git + rofi-bluetooth-git (AUR), swaync + libnotify, htop, python, hyprsunset, rofi, CaskaydiaCove Nerd Font |
| `swaync` | `~/.config/swaync/` (small toasts styled like the bar, 4s timeout, no grouping) | swaync |
| `kitty` | `~/.config/kitty/` | kitty, CaskaydiaCove Nerd Font |
| `tmux` | `~/.tmux.conf` | tmux, wl-clipboard (Wayland copy) |
| `vim` | `~/.vimrc` | vim |
| `zsh` | `~/.zshrc` | zsh, oh-my-zsh + plugins (see below), fzf, zsh-syntax-highlighting |

Shared: CaskaydiaCove Nerd Font (kitty, waybar, rofi cards, notifications, lock
screen); JetBrains Mono Nerd Font is the fallback.
Details per app: `hyprland.md` covers the Hyprland Lua config and the Handy setup.

## One-command install

On a fresh Arch install, logged in as your user, in a normal terminal:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/assil-bouzaine/Dotfiles/main/install.sh)
```

`install.sh` does steps 1–5 below for you: packages (pacman + yay/AUR),
services, zsh + oh-my-zsh, clone to `~/.dotfiles` + stow, the Handy
input/uinput setup and the wallpapers. sudo asks for the password once. Files
that are in stow's way are moved to `~/.dotfiles-backup/<time>/`, not deleted.
It's safe to re-run (from a clone: `~/.dotfiles/install.sh`). Afterwards: log
out and back in, then do the bits it prints (monitors, Handy settings).

## Fresh machine setup (copy-paste in order)

The manual version of what `install.sh` does.

Needs Arch Linux and **Hyprland ≥ 0.55** (the config is Lua). Run everything in
a normal terminal. Commands with `sudo` need a real terminal to ask for the
password, so don't run them through Claude's `!` prompt.

### 1. Base packages (official repos)

```bash
sudo pacman -S --needed git base-devel stow zsh tmux vim curl fzf lua \
  hyprland hypridle hyprlock awww \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  kitty dolphin gwenview archlinux-xdg-menu plasma-integration polkit-kde-agent rofi gnome-keyring \
  pipewire pipewire-pulse wireplumber brightnessctl playerctl \
  wl-clipboard wtype zsh-syntax-highlighting \
  waybar networkmanager nm-connection-editor bluez bluez-utils blueman \
  swaync libnotify htop python hyprsunset \
  ttf-jetbrains-mono-nerd ttf-cascadia-code-nerd
```

What the less obvious ones are for:
- **xdg-desktop-portal-hyprland / -gtk:** screen sharing (Meet etc.) and file pickers.
- **pipewire-pulse, wireplumber:** audio and the volume keys (`wpctl`).
- **wtype:** lets Handy type the transcribed text.
- **fzf:** the fuzzy `cd` function in `.zshrc` and the vim fzf plugin.
- **dolphin, gwenview, plasma-integration, archlinux-xdg-menu:** file manager
  and image viewer; the last two give them Breeze styling and a working
  "Open with" menu outside Plasma (see `conf.d/env.lua`).
- **polkit-kde-agent:** password prompts for pkexec and settings apps.
- **lua:** gives `luac`, used to syntax-check the Hyprland config.
- **zsh-syntax-highlighting:** `.zshrc` sources it from `/usr/share/zsh/plugins/`.
- **networkmanager, bluez, blueman, swaync:** what the bar's Wi-Fi,
  Bluetooth and notification buttons open. swaync starts by itself (D-Bus)
  on the first notification.
- **python:** runs the bar's workspace buttons (`waybar/.../scripts/workspaces.py`).
- **htop:** opens when you click CPU / RAM on the bar.
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
yay -S brave-bin handy-bin xwaylandvideobridge networkmanager-dmenu-git rofi-bluetooth-git
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
stow hypr waybar swaync kitty tmux vim zsh
```

Check with `ls -la ~/.config/hypr`. You should see a `hypr -> ../.dotfiles/...`
symlink (stow folds whole directories when the target doesn't exist yet).

> If a target file already exists (e.g. a stock `~/.tmux.conf` or
> `~/.config/kitty/kitty.conf`), stow will refuse. Move it away first
> (`mv ~/.tmux.conf ~/.tmux.conf.stock`), then re-run stow.

### 5. Things that live outside this repo (do these manually)

- **Wallpapers:** download the set (10 calm cabin / misty lake images from
  wallhaven.cc) into `~/Pictures/Wallpapers/`:
  ```bash
  ~/.config/hypr/scripts/get-wallpapers.sh
  ```
  `wallpaper-cycle.sh` rotates them every 60s. `hyprlock.conf` uses
  `wallhaven-2e6wgx.jpg` and hard-codes `/home/mclovin/...`, so fix that path
  if your username differs.
- **Monitors:** `conf.d/monitors.lua` assumes `1366x768@60` + `HDMI-A-1` on the
  right. Run `hyprctl monitors`, fix names/modes, `hyprctl reload`.
- **Handy (voice-to-text, SUPER+A):** needs the `input` group, a udev rule
  and a few Handy settings. Follow the step-by-step guide in `hyprland.md`
  ("Handy (voice-to-text) on a new machine").
- **Optional extras referenced in `.zshrc`:** nvm (`~/.nvm`), Android SDK
  (`~/Android/sdk`), `~/.local/bin`, `~/.opencode/bin`. Only needed if you use them.

### 6. Log into Hyprland and verify

```bash
hyprctl configerrors   # must be empty
hyprctl monitors       # fix conf.d/monitors.lua if names differ
hyprctl binds | grep -c modmask   # expect 59
```

- **vim:** the first launch downloads vim-plug and installs the plugins by
  itself (needs internet).
- **kitty:** every new window auto-attaches to the tmux session `main`.

First login autostarts: `hypridle`, waybar, the wallpaper cycler,
gnome-keyring, xwaylandvideobridge, brave (hidden window) and handy (hidden,
tray icon).

## Bar, cards and shortcuts

The top bar is waybar with floating pills: Arch logo (app launcher),
workspaces, date and time, CPU / RAM / download speed, Wi-Fi, night light, Bluetooth, tray
and notifications. The launcher, Wi-Fi and Bluetooth open as rofi "cards"
under the bar; click anywhere outside a card (or press its key again) to close
it.

| Keys | Does |
|---|---|
| SUPER + D | app launcher card |
| SUPER + N | Wi-Fi card: [networkmanager-dmenu](https://github.com/firecat53/networkmanager-dmenu) (pick a network, rescan, Wi-Fi on/off) |
| SUPER + B | Bluetooth card: [rofi-bluetooth](https://github.com/nickclyde/rofi-bluetooth) (power, scan, pick a device to connect / pair / trust) |
| SUPER + L | lock screen |
| SUPER + 1…0 | workspaces (also clickable on the bar) |

On the bar: right-click Wi-Fi for `nm-connection-editor`, right-click
Bluetooth to turn it on/off, click the bell for the notification panel
(right-click: do not disturb).

Window rules worth knowing: kitty → 1, Brave → 2 (Brave windows stack as
tabs, other apps can't join that group), VSCode / Dolphin → 3, Gwenview → 8, Spotify → 4.

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
