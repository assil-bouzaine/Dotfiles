# Dotfiles

GNU Stow–managed dotfiles (Arch Linux + Hyprland). Each top-level folder is a
stow package that mirrors `$HOME`:

| Package | Manages | Needs (beyond base) |
|---|---|---|
| `hypr` | `~/.config/hypr/` (Lua config, hyprlock, hypridle, scripts) | hyprland, hypridle, hyprlock, awww, kitty, thunar, rofi, brave, xwaylandvideobridge, gnome-keyring, brightnessctl, wireplumber (wpctl), playerctl |
| `kitty` | `~/.config/kitty/` | kitty, CaskaydiaCove Nerd Font |
| `tmux` | `~/.tmux.conf` | tmux, wl-clipboard (Wayland copy) |
| `vim` | `~/.vimrc` | vim |
| `zsh` | `~/.zshrc` | zsh, oh-my-zsh + plugins (see below) |

Shared: a Nerd Font (JetBrains Mono for the lock screen, CaskaydiaCove for kitty).
Details per app: `hyprland.md` covers the Hyprland Lua config.

## Fresh machine setup (copy-paste in order)

### 1. Base packages

```bash
sudo pacman -S --needed git stow zsh tmux vim \
  hyprland hypridle hyprlock awww xwaylandvideobridge \
  kitty thunar rofi brave gnome-keyring \
  brightnessctl wireplumber playerctl wl-clipboard \
  ttf-jetbrains-mono-nerd ttf-cascadia-code-nerd
```

### 2. Oh-my-zsh + plugins (required by `.zshrc`)

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

(`.zshrc` uses `plugins=(git zsh-autosuggestions zsh-syntax-highlighting)`.)

### 3. Clone + stow

```bash
git clone <your-repo-url> ~/.dotfiles
cd ~/.dotfiles
stow hypr kitty tmux vim zsh
```

Check with `ls -la ~/.config/hypr` — you should see a `hypr -> ../.dotfiles/...`
symlink (stow folds whole directories when the target doesn't exist yet).

> If a target file already exists (e.g. stock `~/.zshrc`), stow will refuse.
> Back it up first: `mv ~/.zshrc ~/.zshrc.stock`, then re-run stow.

### 4. Stuff that lives outside this repo (do these manually)

- **Wallpapers:** `~/Pictures/Wallpapers/` — the `wallpaper-cycle.sh` script and
  `hyprlock.conf` point here. Copy your collection over (hyprlock falls back to
  a solid color if the file is missing).
- **Rofi launcher theme:** `SUPER+D` runs
  `~/.config/rofi/launchers/type-2/launcher.sh` (adi1090x style). Install it or
  rebind `menu` in `hypr/.config/hypr/conf.d/binds.lua`.
- **Monitors:** `conf.d/monitors.lua` assumes `1366x768@60` + `HDMI-A-1` on the
  right. Run `hyprctl monitors`, fix names/modes, `hyprctl reload`.
- **Optional extras referenced in `.zshrc`:** nvm (`~/.nvm`), Android SDK
  (`~/Android/sdk`), `~/.local/bin`, `~/.opencode/bin` — only needed if you use them.

### 5. Log into Hyprland and verify

```bash
hyprctl configerrors   # must be empty
hyprctl monitors       # fix conf.d/monitors.lua if names differ
hyprctl binds | grep -c modmask   # expect 57
```

First login autostarts: `hypridle`, wallpaper cycler, gnome-keyring,
xwaylandvideobridge, brave (hidden window).

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
