#!/usr/bin/env bash
# The one command: turns a fresh Arch Linux install into this desktop.
#
#   On a new PC, logged in as your user (a plain TTY is fine), with internet:
#     bash <(curl -fsSL https://raw.githubusercontent.com/assil-bouzaine/Dotfiles/main/install.sh)
#   or, the same thing by hand:
#     git clone https://github.com/assil-bouzaine/Dotfiles.git ~/.dotfiles && ~/.dotfiles/install.sh
#
#   install.sh               every step, in order (safe to re-run: done work is skipped)
#   install.sh STEP...       only these steps, e.g.  install.sh stow theme
#   install.sh check         what this PC is missing compared with the repo (changes nothing)
#   install.sh help          the list of steps
#
# Nothing gets deleted: a file in the way of a link moves to ~/.dotfiles-backup/<time>/,
# and an /etc file that gets replaced keeps a copy next to it (<name>.pre-dotfiles).

set -euo pipefail

REPO=https://github.com/assil-bouzaine/Dotfiles.git
DEST=$HOME/.dotfiles

STEPS=(packages system stow shell aur agents theme titlebars wallpapers services bots)
declare -A ABOUT=(
    [packages]="pacman packages from packages/*.txt, plus the video driver for this GPU"
    [system]="copy system/etc/ into /etc (zram swap, disk scheduler, pacman hook)"
    [stow]="link every home/<app> folder into ~ with GNU Stow"
    [shell]="zsh as the login shell, oh-my-zsh and its two plugins"
    [aur]="yay, the AUR packages (packages/aur.txt) and the VS Code extensions"
    [agents]="Claude Code and Codex, their settings and hooks, Node LTS"
    [theme]="render the theme (Tokyo Night, JetBrainsMono) for every app"
    [titlebars]="build the titlebars plugin for floating workspaces"
    [wallpapers]="download the wallpaper set into ~/Pictures/Wallpapers"
    [services]="turn on the login screen, network, Bluetooth, idle lock, charger alert"
    [bots]="restore the Telegram bots if a bots-*.tar.gpg is in ~/Downloads"
)

# Folders other programs also write into. They must be real folders: if stow
# linked the whole folder into the repo, everything written there would end
# up in git (vim plugins, Claude's history, VS Code state, ...).
REAL_DIRS=(
    .claude .vim .local/bin .local/lib .local/share/applications .local/share/wireplumber
    .config/btop .config/Code/User .config/git .config/kitty .config/pacman
    .config/systemd/user .config/wireplumber
)

NOTES=()      # printed at the very end
FAILED=()     # steps or packages that didn't work out
GIT_EMAIL=

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m    ! %s\033[0m\n' "$*" >&2; }
die()  { printf '\033[1;31minstall.sh: %s\033[0m\n' "$*" >&2; exit 1; }

# The package names in list files: one or more per line, "#" starts a comment.
read_list() { sed -e 's/#.*//' -e 's/[[:space:]]\+/\n/g' "$@" | sed '/^$/d'; }

# Everything runs from main (last line), so bash has read the whole file
# before any step can read from the terminal.
main() {
    [[ $EUID -ne 0 ]] || die "run it as your user, not as root (it calls sudo itself)"
    command -v pacman >/dev/null || die "this is for Arch Linux (no pacman here)"

    case ${1:-} in
        help|-h|--help) usage; exit 0 ;;
        check) bootstrap "$@"; check; exit ;;
    esac
    local s
    for s in "$@"; do
        [[ -n ${ABOUT[$s]:-} ]] || die "unknown step '$s' (see: install.sh help)"
    done
    bootstrap "$@"

    local steps=("$@")
    (( ${#steps[@]} )) || steps=("${STEPS[@]}")
    ask_first "${steps[@]}"

    trap 'on_exit $?' EXIT
    for s in "${steps[@]}"; do
        CURRENT=$s
        "step_$s"
    done
    CURRENT=
    if (( $# )); then summary; else finish; fi
}

usage() {
    sed -n '2,15p' "${BASH_SOURCE[0]}" 2>/dev/null | sed 's/^# \{0,1\}//'
    printf '\nSteps, in order:\n'
    local s
    for s in "${STEPS[@]}"; do printf '  %-11s %s\n' "$s" "${ABOUT[$s]}"; done
}

CURRENT=
# A step that stops the script says so, and how to carry on from there.
on_exit() {
    (( $1 )) && [[ -n $CURRENT ]] || return 0
    local left=() s seen=0
    for s in "${STEPS[@]}"; do
        [[ $s == "$CURRENT" ]] && seen=1
        (( seen )) && left+=("$s")
    done
    printf '\n\033[1;31m    The "%s" step stopped (see the error above).\033[0m\n' "$CURRENT" >&2
    printf '    Fix that, then carry on with:  %s/install.sh %s\n' "$DOTFILES" "${left[*]}" >&2
}

# Started through curl there is no repo yet: get git, clone (or update)
# ~/.dotfiles and run the install.sh in there, so every file comes from the repo.
bootstrap() {
    local here=
    if [[ -n ${BASH_SOURCE[0]:-} && -f ${BASH_SOURCE[0]} ]]; then
        here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
    fi
    if [[ -n $here && -d $here/home && -d $here/packages && -d $here/system ]]; then
        DOTFILES=$here
        return
    fi
    step "Getting the dotfiles"
    command -v git >/dev/null || sudo pacman -Syu --needed --noconfirm git
    if [[ -d $DEST/.git ]]; then
        git -C "$DEST" pull --ff-only || warn "couldn't update $DEST, using it as it is"
    else
        git clone "$REPO" "$DEST"
    fi
    # Through "curl | bash" stdin is the pipe; give the questions the terminal back.
    if [[ ! -t 0 ]] && { : </dev/tty; } 2>/dev/null; then
        exec bash "$DEST/install.sh" "$@" </dev/tty
    fi
    exec bash "$DEST/install.sh" "$@"
}

# The questions come first, so a long unattended run never stops halfway to ask.
ask_first() {
    local s
    for s in "$@"; do
        case $s in
            packages|system|shell|aur|titlebars|services|bots)
                step "sudo (asked once)"
                sudo -v
                # Keeps sudo's password cache fresh until this script ends.
                ( while kill -0 "$$" 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
                break ;;
        esac
    done
    for s in "$@"; do
        [[ $s == stow ]] || continue
        if [[ -t 0 ]] && ! git config --file "$HOME/.gitconfig" --get user.email >/dev/null 2>&1; then
            printf '\n'
            read -rp "    Email for your git commits (Enter to skip): " GIT_EMAIL || true
        fi
    done
}

# ------------------------------------------------------------------ steps

step_packages() {
    step "Packages (pacman)"
    local files=() f pkgs
    for f in "$DOTFILES"/packages/*.txt; do
        case ${f##*/} in aur.txt|vscode.txt) ;; *) files+=("$f") ;; esac
    done
    mapfile -t pkgs < <(read_list "${files[@]}"; gpu_packages)
    info "${#pkgs[@]} packages from: ${files[*]##*/}"
    if grep -qsx 0x10de /sys/class/drm/card*/device/vendor; then
        NOTES+=("NVIDIA GPU: its driver isn't installed by this script: https://wiki.archlinux.org/title/NVIDIA")
    fi
    # --ask 4 answers "yes" when a listed package replaces a conflicting one
    # (vim -> gvim, jack2 -> pipewire-jack); every other question gets its default.
    sudo pacman -Syu --needed --noconfirm --ask 4 "${pkgs[@]}"
}

# Video decoding and Vulkan for the GPU(s) in this PC.
gpu_packages() {
    local v
    for v in /sys/class/drm/card*/device/vendor; do
        [[ -r $v ]] || continue
        case $(<"$v") in
            0x8086) printf '%s\n' intel-media-driver vulkan-intel ;;
            0x1002) printf '%s\n' vulkan-radeon ;;          # VA-API comes with mesa
        esac
    done | sort -u
}

step_system() {
    step "System files: system/etc -> /etc"
    local src dst changed=()
    while IFS= read -r -d '' src; do
        dst=${src#"$DOTFILES/system"}
        [[ -f $dst ]] && cmp -s "$src" "$dst" && continue
        if [[ -e $dst && ! -e $dst.pre-dotfiles ]]; then
            sudo cp -a "$dst" "$dst.pre-dotfiles"
            info "kept the old one as $dst.pre-dotfiles"
        fi
        sudo install -Dm644 "$src" "$dst"
        info "$dst"
        changed+=("$dst")
    done < <(find "$DOTFILES/system" -type f -print0 | sort -z)
    if (( ! ${#changed[@]} )); then info "all up to date"; return; fi
    case " ${changed[*]}" in *" /etc/udev/"*)
        sudo udevadm control --reload
        sudo udevadm trigger --subsystem-match=block --action=change || true ;;
    esac
    case " ${changed[*]}" in *" /etc/sysctl.d/"*)
        sudo sysctl --system >/dev/null || warn "sysctl --system failed; the values apply after a reboot" ;;
    esac
    case " ${changed[*]}" in *zram-generator*)
        NOTES+=("zram swap: the new size applies after a reboot") ;;
    esac
}

step_stow() {
    step "Links: home/<app> -> ~ (GNU Stow)"
    local pkgs=() d
    for d in "$DOTFILES"/home/*/; do d=${d%/}; pkgs+=("${d##*/}"); done
    for d in "${REAL_DIRS[@]}"; do mkdir -p "$HOME/$d"; done

    # Anything stow refuses to replace moves to the backup folder first.
    local backup out target found moved=0 try
    backup=$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)
    for try in 1 2 3 4; do
        out=$(stow -n -d "$DOTFILES/home" -t "$HOME" --restow "${pkgs[@]}" 2>&1) && break
        (( try < 4 )) || { printf '%s\n' "$out" >&2; die "stow still finds conflicts"; }
        found=0
        while IFS= read -r target; do
            [[ -n $target ]] && [[ -e $HOME/$target || -L $HOME/$target ]] || continue
            mkdir -p "$backup/$(dirname -- "$target")"
            mv -- "$HOME/$target" "$backup/$target"
            info "moved ~/$target out of the way"
            found=1 moved=1
        done < <(sed -nE \
            -e 's/^  \* existing target is not owned by stow: (.+)$/\1/p' \
            -e 's/^  \* existing target is stowed to a different package: (.+) => .*$/\1/p' \
            -e 's/^  \* cannot stow .+ over existing (directory |non-directory )?target (.+) since .*$/\2/p' \
            -e 's/^  \* cannot stow .+ over existing (directory |non-directory )?target (.+)$/\2/p' \
            <<<"$out")
        (( found )) || { printf '%s\n' "$out" >&2; die "stow can't link everything (see above)"; }
    done
    stow -d "$DOTFILES/home" -t "$HOME" --restow "${pkgs[@]}"
    info "linked ${#pkgs[@]} apps: ${pkgs[*]}"
    (( moved )) && info "the files that were in the way are in $backup"

    if [[ -n $GIT_EMAIL ]]; then
        git config --file "$HOME/.gitconfig" user.email "$GIT_EMAIL"
        info "git email saved in ~/.gitconfig (kept out of the repo)"
    fi
    return 0
}

step_shell() {
    step "zsh + oh-my-zsh"
    if [[ $(getent passwd "$USER" | cut -d: -f7) != */zsh ]]; then
        sudo chsh -s /usr/bin/zsh "$USER"
        info "zsh is the login shell from the next login"
    fi
    if [[ ! -d $HOME/.oh-my-zsh ]]; then
        # KEEP_ZSHRC: leaves the linked ~/.zshrc alone.
        RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
            "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    # The two plugins .zshrc loads are the pacman ones (packages/base.txt).
    local name dst
    for name in zsh-autosuggestions zsh-syntax-highlighting; do
        dst=$HOME/.oh-my-zsh/custom/plugins/$name
        [[ -e $dst || -L $dst ]] || ln -s "/usr/share/zsh/plugins/$name" "$dst"
    done
    info "oh-my-zsh with zsh-autosuggestions + zsh-syntax-highlighting"
}

step_aur() {
    step "AUR packages (yay)"
    if ! command -v yay >/dev/null; then
        local tmp; tmp=$(mktemp -d)
        git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$tmp/yay-bin"
        (cd "$tmp/yay-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
    # One at a time, so one broken AUR package doesn't stop the rest.
    local pkg
    while IFS= read -r pkg; do
        if pacman -Q "$pkg" >/dev/null 2>&1; then info "$pkg: installed"; continue; fi
        yay -S --needed --noconfirm --sudoloop --answerclean None --answerdiff None "$pkg" ||
            { warn "$pkg didn't install"; FAILED+=("AUR package $pkg (try: yay -S $pkg)"); }
    done < <(read_list "$DOTFILES/packages/aur.txt")
    vscode_extensions
}

vscode_extensions() {
    command -v code >/dev/null || { warn "no 'code' command, skipped the VS Code extensions"; return 0; }
    local have ext
    have=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
    while IFS= read -r ext; do
        grep -qxF "${ext,,}" <<<"$have" && continue
        if code --install-extension "$ext" >/dev/null 2>&1; then info "VS Code: $ext"
        else warn "VS Code: couldn't install $ext"; FAILED+=("VS Code extension $ext"); fi
    done < <(read_list "$DOTFILES/packages/vscode.txt")
    info "VS Code extensions: done"
}

step_agents() {
    step "Claude Code + Codex"
    export PATH=$HOME/.local/bin:$PATH
    # Codex's settings go in before Codex, so its first start already uses them.
    if [[ -e $HOME/.codex/config.toml ]]; then
        info "~/.codex/config.toml: kept as it is"
    else
        install -Dm600 "$DOTFILES/home/codex/config.toml" "$HOME/.codex/config.toml"
        info "~/.codex/config.toml: written from home/codex/config.toml"
    fi
    if command -v claude >/dev/null; then info "claude: installed"
    else curl -fsSL https://claude.ai/install.sh | bash; fi
    if command -v codex >/dev/null; then info "codex: installed"
    else curl -fsSL https://chatgpt.com/codex/install.sh | sh; fi

    if ! command -v fnm >/dev/null; then
        warn "no fnm, skipped Node (it comes with the packages step)"
    elif fnm default >/dev/null 2>&1; then
        info "Node: $(fnm default) is the default"
    else
        fnm install --lts
        local v; v=$(fnm list | grep -o 'v[0-9][0-9.]*' | sort -V | tail -1)
        fnm default "$v"
        info "Node: $v is the default"
    fi

    # The hook entries first: on a new PC that creates settings.json, so
    # nothing needs a backup copy.
    "$DOTFILES/home/agent-notify/.local/bin/bots" hooks

    # Claude rewrites settings.json, so it's merged rather than linked:
    # keys already there win, missing ones come from home/claude/settings.json.
    python3 - "$DOTFILES/home/claude/settings.json" "$HOME/.claude/settings.json" <<'PY'
import json, sys
from pathlib import Path
base = json.loads(Path(sys.argv[1]).read_text())
path = Path(sys.argv[2])
cur = json.loads(path.read_text()) if path.exists() else {}
def merge(dst, src, prefix=""):
    added = []
    for key, value in src.items():
        if key not in dst:
            dst[key] = value
            added.append(prefix + key)
        elif isinstance(dst[key], dict) and isinstance(value, dict):
            added += merge(dst[key], value, prefix + key + ".")
    return added
added = merge(cur, base)
if added:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(cur, indent=2) + "\n")
print("    ~/.claude/settings.json: " + ("added " + ", ".join(added) if added else "has everything already"))
PY
}

step_theme() {
    step "Theme"
    # GTK apps: Breeze icons and Noto Sans, like on the first PC (Plasma set
    # these there). Only for a missing settings.ini; the theme hook adds the rest.
    local v f
    for v in 3.0 4.0; do
        f=$HOME/.config/gtk-$v/settings.ini
        [[ -e $f ]] && continue
        mkdir -p "${f%/*}"
        printf '[Settings]\ngtk-icon-theme-name=breeze\ngtk-cursor-theme-name=breeze_cursors\ngtk-cursor-theme-size=24\ngtk-font-name=Noto Sans,  10\n' >"$f"
        info "~/.config/gtk-$v/settings.ini: Breeze icons, Noto Sans"
    done
    if command -v gsettings >/dev/null; then
        gsettings set org.gnome.desktop.interface icon-theme breeze 2>/dev/null || true
        gsettings set org.gnome.desktop.interface font-name 'Noto Sans  10' 2>/dev/null || true
    fi
    # Renders every app's colours and runs the GTK / KDE / btop hooks. Nothing
    # graphical has to run for this.
    "$HOME/.local/bin/theme" apply ||
        { warn "theme apply failed; run 'theme apply' after logging in"; FAILED+=("theme apply"); }
}

step_titlebars() {
    step "Titlebars for floating workspaces"
    if "$HOME/.local/bin/titlebars-rebuild" --check >/dev/null 2>&1; then
        info "already built for this Hyprland"
    elif "$HOME/.local/bin/titlebars-rebuild"; then
        info "built"
    else
        warn "couldn't build them; floating workspaces still work without titlebars"
        FAILED+=("titlebars plugin (try: titlebars-rebuild)")
    fi
}

step_wallpapers() {
    step "Wallpapers"
    "$DOTFILES/home/hypr/.config/hypr/scripts/get-wallpapers.sh" ||
        { warn "some wallpapers didn't download"; FAILED+=("wallpapers (try: ~/.config/hypr/scripts/get-wallpapers.sh)"); }
}

step_services() {
    step "Services"
    # NetworkManager runs the network. Switching over right now could drop the
    # connection this script still needs, so then it only switches at the reboot.
    local now=1
    if systemctl is-active -q iwd && ! grep -rqs 'wifi.backend *= *iwd' /etc/NetworkManager/; then
        sudo systemctl disable iwd >/dev/null 2>&1 || true
        now=0
    fi
    if systemctl is-active -q systemd-networkd; then
        sudo systemctl disable systemd-networkd.service systemd-networkd.socket >/dev/null 2>&1 || true
        now=0
    fi
    if (( now )); then
        sudo systemctl enable --now NetworkManager.service
    else
        sudo systemctl enable NetworkManager.service
        NOTES+=("Network: NetworkManager takes over after the reboot. Wi-Fi: SUPER + N.")
    fi
    sudo systemctl enable --now bluetooth.service fstrim.timer
    info "NetworkManager, bluetooth, fstrim.timer"

    # Login screen. Never --now: it would take over tty1, maybe the one running this.
    if [[ -L /etc/systemd/system/display-manager.service ]]; then
        warn "another login screen is set up ($(readlink -f /etc/systemd/system/display-manager.service)), so ly stays off"
    else
        sudo systemctl enable ly@tty1.service
        info "ly login screen on tty1 (from the next boot)"
    fi

    if systemctl --user daemon-reload 2>/dev/null; then
        systemctl --user enable hypridle.service charger-alert.service
        systemctl --user try-restart charger-alert.service || true
        info "hypridle (lock, screen off, suspend), charger-alert (exits by itself without a battery)"
    else
        warn "your user's systemd isn't reachable from here"
        NOTES+=("After logging in: systemctl --user enable hypridle.service charger-alert.service")
    fi
}

step_bots() {
    step "Telegram bots"
    if systemctl --user is-active -q tg-bridge@claude.service 2>/dev/null; then
        info "they already run here"
        return
    fi
    local bundle
    bundle=$(ls -t "$HOME"/Downloads/bots-*.tar.gpg "$HOME"/bots-*.tar.gpg 2>/dev/null | head -1 || true)
    if [[ -z $bundle ]]; then
        info "no bots-*.tar.gpg in ~/Downloads, skipped. To move them here later:"
        info "'bots move' on the old PC, put the file in ~/Downloads, then: bots install"
        return
    fi
    "$HOME/.local/bin/bots" install "$bundle" ||
        { warn "bots install failed"; FAILED+=("Telegram bots (try: bots install)"); }
}

# ------------------------------------------------------------------ end

summary() {
    local n
    for n in "${NOTES[@]}"; do info "$n"; done
    if (( ${#FAILED[@]} )); then
        printf '\n\033[1;33m    Needs another try:\033[0m\n'
        for n in "${FAILED[@]}"; do info "- $n"; done
    fi
    return 0
}

finish() {
    step "Done"
    info "1. Reboot. On the ly login screen pick Hyprland."
    info "2. Sign in: claude (then /login), codex login, gh auth login."
    info "3. Wrong monitor layout? hyprctl monitors, then fix ~/.config/hypr/conf.d/monitors.lua."
    info "4. Hex (voice to text): open it once and download a model; hold SUPER + Z to talk."
    info "5. Later, to see what's missing or out of date: ~/.dotfiles/install.sh check"
    summary
}

# ------------------------------------------------------------------ check

check() {
    step "Comparing this PC with $DOTFILES"
    local bad=0 pkgs missing out f dst s

    local lists=()
    for f in "$DOTFILES"/packages/*.txt; do [[ ${f##*/} == vscode.txt ]] || lists+=("$f"); done
    mapfile -t pkgs < <(read_list "${lists[@]}"; gpu_packages)
    missing=$(pacman -T "${pkgs[@]}" 2>/dev/null || true)
    if [[ -z $missing ]]; then ok "all ${#pkgs[@]} packages installed"
    else no "packages missing: $(echo $missing)"; bad=1; fi

    if command -v code >/dev/null; then
        local have ext gone=()
        have=$(code --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' || true)
        while IFS= read -r ext; do grep -qxF "${ext,,}" <<<"$have" || gone+=("$ext"); done \
            < <(read_list "$DOTFILES/packages/vscode.txt")
        if (( ${#gone[@]} )); then no "VS Code extensions missing: ${gone[*]}"; bad=1
        else ok "VS Code extensions installed"; fi
    fi

    local apps=() d
    for d in "$DOTFILES"/home/*/; do d=${d%/}; apps+=("${d##*/}"); done
    if out=$(stow -n -v -d "$DOTFILES/home" -t "$HOME" "${apps[@]}" 2>&1); then
        out=$(grep -E '^(LINK|UNLINK|MKDIR|RMDIR):' <<<"$out" || true)
        if [[ -z $out ]]; then ok "all ${#apps[@]} home/ apps linked"
        else no "links missing (run: install.sh stow):"; sed 's/^/        /' <<<"$out"; bad=1; fi
    else
        no "files in the way of links (install.sh stow moves them aside):"
        grep '^  \*' <<<"$out" | sed 's/^  \* /        /'; bad=1
    fi

    local diff=()
    while IFS= read -r -d '' f; do
        dst=${f#"$DOTFILES/system"}
        cmp -s "$f" "$dst" 2>/dev/null || diff+=("$dst")
    done < <(find "$DOTFILES/system" -type f -print0 | sort -z)
    if (( ${#diff[@]} )); then no "/etc files differ from system/: ${diff[*]}"; bad=1
    else ok "system/ files are in /etc"; fi

    local off=()
    for s in NetworkManager.service bluetooth.service fstrim.timer ly@tty1.service; do
        systemctl is-enabled -q "$s" 2>/dev/null || off+=("$s")
    done
    for s in hypridle.service charger-alert.service; do
        systemctl --user is-enabled -q "$s" 2>/dev/null || off+=("$s (user)")
    done
    if (( ${#off[@]} )); then no "services not enabled: ${off[*]}"; bad=1
    else ok "services enabled"; fi

    if "$HOME/.local/bin/titlebars-rebuild" --check >/dev/null 2>&1; then ok "titlebars plugin matches Hyprland"
    else no "titlebars plugin missing or built for another Hyprland (run: titlebars-rebuild)"; bad=1; fi

    [[ $(getent passwd "$USER" | cut -d: -f7) == */zsh ]] && ok "zsh is the login shell" || { no "login shell isn't zsh"; bad=1; }

    (( bad )) && printf '\n    Fix: %s/install.sh (or only the step named above)\n' "$DOTFILES"
    return $bad
}
ok() { printf '    \033[32mok\033[0m  %s\n' "$*"; }
no() { printf '    \033[31m--\033[0m  %s\n' "$*"; }

main "$@"
