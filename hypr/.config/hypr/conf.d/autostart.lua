-- Autostart
-- See https://wiki.hypr.land/configuring/core/autostart/
-- Order kept identical to the old hyprland.conf exec-once lines.
-- (The dbus-update line had a missing space in the old conf:
--  `exec-once=dbus-...` — fixed here, same command.)

hl.on("hyprland.start", function()
    hl.exec_cmd("hypridle")
    hl.exec_cmd("sleep 1 && ~/.config/hypr/scripts/wallpaper-cycle.sh")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    hl.exec_cmd("xwaylandvideobridge &")
    hl.exec_cmd("brave --no-startup-window")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
end)
