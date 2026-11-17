# Titlebars

Builds Omarchy's Hyprland titlebar plugin v0.4.0 for Arch's official `[extra]`
Hyprland, installing `/usr/lib/omarchy-hyprland-titlebars/titlebars.so`.
Requires `base-devel`, `cmake`, `pkgconf`, and the PKGBUILD's runtime dependencies.

After `stow titlebars`, run `titlebars-rebuild` as your user to build and install.
Rebuild after every Hyprland upgrade: plugins require the exact Hyprland build.
The package records its full Hyprland version in the adjacent `built-for` file.
`titlebars-rebuild --check` exits 0 for current, 1 for stale, or 2 for not installed.

Files: `home/titlebars/.local/bin/titlebars-rebuild` and
`home/titlebars/.local/share/titlebars/PKGBUILD`. The pacman hook
`system/etc/pacman.d/hooks/titlebars-rebuild.hook` only prints a reminder after
Hyprland upgrades; `install.sh system` copies it to `/etc/pacman.d/hooks/`.
