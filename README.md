# Dotfiles

GNU Stow–managed dotfiles (Arch Linux + Hyprland). Each top-level folder is a
stow package that mirrors `$HOME`:

| Package | Manages | Needs (beyond base) |
|---|---|---|
| `hypr` | `~/.config/hypr/` (Lua config, hyprlock, hypridle, scripts) | hyprland, hypridle, hyprlock, awww, kitty, thunar, rofi, brave-bin (AUR), handy-bin (AUR) + wtype, xwaylandvideobridge (AUR), xdg-desktop-portal-hyprland, gnome-keyring, brightnessctl, pipewire + wireplumber (wpctl), playerctl |
| `kitty` | `~/.config/kitty/` | kitty, CaskaydiaCove Nerd Font |
| `tmux` | `~/.tmux.conf` | tmux, wl-clipboard (Wayland copy) |
| `vim` | `~/.vimrc` | vim |
| `zsh` | `~/.zshrc` | zsh, oh-my-zsh + plugins (see below), fzf, zsh-syntax-highlighting |

Shared: a Nerd Font (JetBrains Mono for the lock screen, CaskaydiaCove for kitty).
Details per app: `hyprland.md` covers the Hyprland Lua config and the Handy setup.

## Fresh machine setup (copy-paste in order)

Needs Arch Linux and **Hyprland ≥ 0.55** (the config is Lua). Run everything in
a normal terminal. Commands with `sudo` need a real terminal to ask for the
password, so don't run them through Claude's `!` prompt.

### 1. Base packages (official repos)

```bash
sudo pacman -S --needed git base-devel stow zsh tmux vim curl fzf lua \
  hyprland hypridle hyprlock awww \
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  kitty thunar rofi gnome-keyring \
  pipewire pipewire-pulse wireplumber brightnessctl playerctl \
  wl-clipboard wtype zsh-syntax-highlighting \
  ttf-jetbrains-mono-nerd ttf-cascadia-code-nerd
```

What the less obvious ones are for:
- **xdg-desktop-portal-hyprland / -gtk:** screen sharing (Meet etc.) and file pickers.
- **pipewire-pulse, wireplumber:** audio and the volume keys (`wpctl`).
- **wtype:** lets Handy type the transcribed text.
- **fzf:** the fuzzy `cd` function in `.zshrc` and the vim fzf plugin.
- **lua:** gives `luac`, used to syntax-check the Hyprland config.
- **zsh-syntax-highlighting:** `.zshrc` sources it from `/usr/share/zsh/plugins/`.

### 2. AUR packages (not in the official repos)

```bash
git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
(cd /tmp/yay-bin && makepkg -si)
yay -S brave-bin handy-bin xwaylandvideobridge
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
stow hypr kitty tmux vim zsh
```

Check with `ls -la ~/.config/hypr`. You should see a `hypr -> ../.dotfiles/...`
symlink (stow folds whole directories when the target doesn't exist yet).

> If a target file already exists (e.g. a stock `~/.tmux.conf` or
> `~/.config/kitty/kitty.conf`), stow will refuse. Move it away first
> (`mv ~/.tmux.conf ~/.tmux.conf.stock`), then re-run stow.

### 5. Things that live outside this repo (do these manually)

- **Wallpapers:** copy your collection to `~/Pictures/Wallpapers/`. The
  `wallpaper-cycle.sh` script and `hyprlock.conf` use it. `hyprlock.conf`
  hard-codes `/home/mclovin/...`, so fix that path if your username differs.
- **Rofi launcher theme:** `SUPER+D` runs
  `~/.config/rofi/launchers/type-2/launcher.sh` (adi1090x style). Install it or
  rebind it in `hypr/.config/hypr/conf.d/binds.lua`.
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
hyprctl binds | grep -c modmask   # expect 57
```

- **vim:** the first launch downloads vim-plug and installs the plugins by
  itself (needs internet).
- **kitty:** every new window auto-attaches to the tmux session `main`.

First login autostarts: `hypridle`, the wallpaper cycler, gnome-keyring,
xwaylandvideobridge, brave (hidden window) and handy (hidden, tray icon).

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
- **Rollback to legacy conf:** delete `hyprland.lua` + `conf.d/`, then
  `hyprctl reload full-reset` — the kept `hyprland.conf` takes over.
