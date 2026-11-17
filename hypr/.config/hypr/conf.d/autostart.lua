-- Autostart
-- See https://wiki.hypr.land/configuring/core/autostart/
-- dbus-update runs first so portals / keyring see the Wayland env.

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- hypridle runs as a systemd user service (hypridle.service); starting it here too ran two.
    hl.exec_cmd("waybar") -- top bar, config in ~/.config/waybar (stow package: waybar)
    hl.exec_cmd("qs -c cards -d") -- dock, app grid, theme/font pickers, bar cards (~/.config/quickshell/cards)
    hl.exec_cmd("~/.config/quickshell/wallpicker/wallctl.py restore") -- last wallpaper picked with SUPER + CTRL + SPACE
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1") -- password prompts for pkexec / system settings
    -- xwaylandvideobridge removed 2026-11-17: Discord captures through its own
    -- PipeWire path, so the bridge only cost ~76 MB (Omarchy ships without it too).
    hl.exec_cmd("brave --no-startup-window")
end)
