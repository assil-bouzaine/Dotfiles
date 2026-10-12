-- Autostart
-- See https://wiki.hypr.land/configuring/core/autostart/
-- dbus-update runs first so portals / keyring see the Wayland env.

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("waybar") -- top bar, config in ~/.config/waybar (stow package: waybar)
    hl.exec_cmd("sleep 1 && ~/.config/hypr/scripts/wallpaper-cycle.sh")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1") -- password prompts for pkexec / system settings
    hl.exec_cmd("xwaylandvideobridge")
    hl.exec_cmd("brave --no-startup-window")
    hl.exec_cmd("handy --start-hidden") -- voice-to-text, toggled with SUPER + A
end)
