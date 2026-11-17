#!/usr/bin/env bash
# One-command setup for a fresh Arch machine (the README's "Fresh machine
# setup", steps 1–5, in a script). Safe to re-run: every step skips what is
# already done.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/assil-bouzaine/Dotfiles/main/install.sh)
#   ~/.dotfiles/install.sh          # or from a clone
#
# Files that are in the way of stow are moved to ~/.dotfiles-backup/<time>/.
# Run it as your user in a real terminal: sudo asks for the password once.

set -euo pipefail

REPO=https://github.com/assil-bouzaine/Dotfiles.git
PACKAGES=(hypr waybar swaync kitty tmux vim zsh agent-notify quickshell share-picker theme titlebars btop)

PACMAN_PKGS=(
    git base-devel stow zsh tmux vim curl fzf fd lua jq cmake
    hyprland hypridle hyprlock awww
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    kitty dolphin gwenview archlinux-xdg-menu plasma-integration polkit-kde-agent rofi gnome-keyring
    pipewire pipewire-pulse wireplumber brightnessctl playerctl
    wl-clipboard wtype grim slurp zsh-syntax-highlighting
    waybar networkmanager nm-connection-editor bluez bluez-utils blueman
    quickshell qrencode
    swaync libnotify htop btop python python-gobject hyprsunset sound-theme-freedesktop
    ttf-jetbrains-mono-nerd ttf-cascadia-code-nerd
    ttf-firacode-nerd otf-geist-mono-nerd ttf-victor-mono-nerd
    otf-commit-mono-nerd ttf-martian-mono-nerd ttf-0xproto-nerd
    ttf-lilex-nerd ttf-hack-nerd ttf-ibmplex-mono-nerd ttf-adwaitamono-nerd
    adwaita-fonts adw-gtk-theme
)
AUR_PKGS=(brave-bin hex-bin hyprland-preview-share-picker-git)

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*"; }

# Everything runs from main, called on the last line, so bash has read the
# whole script before anything can read stdin (matters for curl | bash).
main() {
    [[ $EUID -ne 0 ]] || { echo "Run as your user, not root (sudo is used where needed)."; exit 1; }
    command -v pacman >/dev/null || { echo "This script is for Arch Linux (no pacman found)."; exit 1; }

    step "sudo (asked once, kept alive while the script runs)"
    sudo -v
    while sudo -n true 2>/dev/null; do sleep 50; done &
    SUDO_LOOP=$!
    trap 'kill "$SUDO_LOOP" 2>/dev/null' EXIT

    step "Official packages"
    sudo pacman -Syu --needed --noconfirm "${PACMAN_PKGS[@]}"

    find_dotfiles
    services
    aur
    zsh_setup
    stow_all
    theme_setup
    titlebars_setup
    wallpapers
    finish
}

# The clone this script was started from, or ~/.dotfiles (cloned if missing)
find_dotfiles() {
    step "Dotfiles repo"
    local here
    here=$(cd "$(dirname "${BASH_SOURCE[0]:-.}")" 2>/dev/null && pwd || true)
    if [[ -n $here && -d $here/hypr && -d $here/waybar ]]; then
        DOTFILES=$here
    else
        DOTFILES=$HOME/.dotfiles
        if [[ -d $DOTFILES/.git ]]; then
            git -C "$DOTFILES" pull --ff-only || warn "couldn't update $DOTFILES, using it as is"
        else
            git clone "$REPO" "$DOTFILES"
        fi
    fi
    info "$DOTFILES"
}

services() {
    step "NetworkManager + Bluetooth"
    # iwd from the Arch install fights NetworkManager, unless NM uses it as its backend
    if systemctl is-enabled iwd >/dev/null 2>&1 &&
       ! grep -rqs 'wifi.backend *= *iwd' /etc/NetworkManager/; then
        sudo systemctl disable --now iwd
        info "disabled iwd"
    fi
    sudo systemctl enable --now NetworkManager bluetooth
}

aur() {
    step "AUR packages"
    if ! command -v yay >/dev/null; then
        local tmp; tmp=$(mktemp -d)
        git clone https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
    yay -S --needed --noconfirm --sudoloop "${AUR_PKGS[@]}"
}

zsh_setup() {
    step "zsh + oh-my-zsh"
    if [[ $(getent passwd "$USER" | cut -d: -f7) != */zsh ]]; then
        sudo chsh -s /usr/bin/zsh "$USER"
        info "login shell is now zsh"
    fi
    if [[ ! -d $HOME/.oh-my-zsh ]]; then
        # KEEP_ZSHRC: leave a stowed .zshrc alone; a stock one is backed up by stow_all
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
            "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    local plugins=$HOME/.oh-my-zsh/custom/plugins name
    for name in zsh-autosuggestions zsh-syntax-highlighting; do
        [[ -d $plugins/$name ]] || git clone "https://github.com/zsh-users/$name" "$plugins/$name"
    done
}

# Moves anything stow would refuse to overwrite into the backup folder, then
# (re)stows. Targets that already resolve into the repo are left alone.
stow_all() {
    step "Stow: ${PACKAGES[*]}"
    local backup=$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)
    local pkg src rel dst moved=0
    for pkg in "${PACKAGES[@]}"; do
        while IFS= read -r -d '' src; do
            rel=${src#"$DOTFILES/$pkg/"}
            # titlebars' notes and system hook are ignored by stow.
            [[ $pkg == titlebars && $rel != .local/* ]] && continue
            dst=$HOME/$rel
            [[ -e $dst || -L $dst ]] || continue
            [[ $(realpath -m "$dst") == "$(realpath -m "$src")" ]] && continue
            mkdir -p "$backup/$(dirname "$rel")"
            mv "$dst" "$backup/$rel"
            info "backed up ~/$rel"
            moved=1
        done < <(find "$DOTFILES/$pkg" \( -type f -o -type l \) -print0)
    done
    (( moved )) && info "old files are in $backup"
    # Shared dirs must exist first, or stow links the whole dir into the repo and
    # everything other apps put there later would land in the repo too.
    # ~/.config/btop too: the theme hook writes btop's themes/ next to btop.conf.
    mkdir -p "$HOME/.local/bin" "$HOME/.local/lib" "$HOME/.local/share" "$HOME/.config/systemd/user" "$HOME/.config/btop"
    stow -d "$DOTFILES" -t "$HOME" --restow "${PACKAGES[@]}"
}

theme_setup() {
    step "Theme"
    # Workspace modes need no setup: Hyprland writes the boot defaults
    # (workspace 1 floating) to $XDG_RUNTIME_DIR on its first config load.
    # Renders every app's colours and runs the hooks (GTK, KDE, btop). Nothing
    # graphical runs yet, so there is nothing to reload.
    "$HOME/.local/bin/theme" apply || warn "theme apply failed; run it again after logging in"
}

titlebars_setup() {
    step "Floating window titlebars"
    if "$HOME/.local/bin/titlebars-rebuild" --check >/dev/null 2>&1; then
        info "titlebars already match Hyprland"
    else
        "$HOME/.local/bin/titlebars-rebuild" || \
            warn "couldn't build titlebars; floating workspaces still work. Re-run titlebars-rebuild later."
    fi
    sudo install -Dm644 "$DOTFILES/titlebars/pacman-hook/titlebars-rebuild.hook" /etc/pacman.d/hooks/titlebars-rebuild.hook
}

wallpapers() {
    step "Wallpapers"
    "$DOTFILES/hypr/.config/hypr/scripts/get-wallpapers.sh" || warn "some wallpapers failed, re-run later"
}

finish() {
    step "Done. Still manual:"
    info "- Log out and back in (zsh shell, input group), then start Hyprland."
    info "- Monitors: check 'hyprctl monitors', fix conf.d/monitors.lua."
    info "- Hex: open it once (hex app) and download a model; keys are in hyprland.md."
    info "- After every Hyprland upgrade: titlebars-rebuild (check with --check)."
    info "- Telegram alerts: one @BotFather bot per agent, then"
    info "  tg-notify --bot claude setup; tg-notify --bot codex setup   (agent-notify.md)"
    info "- Verify: hyprctl configerrors   (must be empty)"
}

main "$@"
