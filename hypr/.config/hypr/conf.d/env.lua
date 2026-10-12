-- Environment variables
-- See https://wiki.hypr.land/configuring/core/environment-variables/

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("GNOME_KEYRING_CONTROL", "/run/user/1000/keyring")

-- KDE apps (Dolphin, Gwenview, ...) outside Plasma: Breeze theme/icons via
-- plasma-integration, and a menu file so "Open with" lists apps
-- (needs archlinux-xdg-menu).
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("XDG_MENU_PREFIX", "arch-")
