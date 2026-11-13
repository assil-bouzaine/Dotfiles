-- Keybindings
-- See https://wiki.hypr.land/configuring/core/binds/

local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "rofi -show drun"

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Drop-down cards shared with the waybar buttons (apps, Wi-Fi, Bluetooth).
-- Pressing the key again while a card is open closes it.
local cards = "pkill -x rofi || "

hl.bind(mainMod .. " + W",      hl.dsp.exec_cmd("brave"), { description = "Open Brave browser" })
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal), { description = "Open terminal (kitty)" })
hl.bind(mainMod .. " + C",      hl.dsp.window.close(), { description = "Close the active window" })
hl.bind(mainMod .. " + M",      hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"), { description = "Log out (exit Hyprland)" })
hl.bind(mainMod .. " + F",      hl.dsp.exec_cmd(fileManager), { description = "Open file manager (Dolphin)" })
hl.bind(mainMod .. " + V",      hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating for the active window" })
hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd(cards .. "rofi -show drun -theme ~/.config/waybar/scripts/launcher.rasi"), { description = "Open app launcher" })
hl.bind(mainMod .. " + N",      hl.dsp.exec_cmd(cards .. "~/.config/waybar/scripts/wifi.py"), { description = "Open Wi-Fi / network menu" })
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(cards .. "~/.config/waybar/scripts/bluetooth.py"), { description = "Open Bluetooth menu" })
hl.bind(mainMod .. " + P",      hl.dsp.window.pseudo(), { description = "Toggle pseudo-tiling for the active window" }) -- dwindle
hl.bind("SUPER + L",            hl.dsp.exec_cmd("hyprlock"), { description = "Lock the screen" })

-- Keybind cheat sheet: searchable list of every bind in this config.
-- SUPER + /. code:61 is the physical slash key, so it stays put on the ara
-- and fr layouts where "/" lives on another key.
hl.bind(mainMod .. " + code:61", hl.dsp.exec_cmd("~/.config/hypr/scripts/keybinds.sh"), { description = "Show this keybind cheat sheet" })

-- Hex dictation (Anomaly). Hyprland's GlobalShortcuts portal never assigns
-- keys to app shortcuts, so Hex reports "desktop did not grant this shortcut".
-- Bind Hex's CLI instead: hold SUPER + Z to talk, release to transcribe+paste.
hl.bind(mainMod .. " + Z",         hl.dsp.exec_cmd("hex dictation start"), { description = "Start voice dictation (hold to talk)" })
hl.bind(mainMod .. " + Z",         hl.dsp.exec_cmd("hex dictation stop"), { release = true, description = "Stop dictation and paste the text" })
-- Fallback when SUPER is let go before Z: the SUPER + Z release bind no longer
-- matches, so also stop on a bare Z release. non_consuming keeps Z typing
-- normally; `hex dictation stop` does nothing while Hex is idle.
hl.bind("Z", hl.dsp.exec_cmd("hex dictation stop"), { release = true, non_consuming = true, description = "Stop dictation (fallback if Super is released first)" })
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.exec_cmd("hex paste-last"), { description = "Paste the last dictation again" })
hl.bind(mainMod .. " + ALT + Z",   hl.dsp.exec_cmd("hex dictation cancel"), { description = "Cancel dictation" })

-- Window groups (tabbed windows)
hl.bind(mainMod .. " + G", hl.dsp.group.toggle(), { description = "Toggle window group (tabs)" })

-- SUPER + TAB: next tab when the focused window is in a group with 2+ windows
-- (stacked VSCode / Brave), otherwise cycle to the next window.
-- One bind on purpose — two binds on the same key both fire.
hl.bind(mainMod .. " + TAB", function()
    local win = hl.get_active_window()
    if win and win.group and win.group.size > 1 then
        hl.dispatch(hl.dsp.group.next())
    else
        hl.dispatch(hl.dsp.window.cycle_next())
    end
end, { description = "Next tab in a group, otherwise next window" })

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }), { description = "Move focus left" })
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }), { description = "Move focus up" })
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }), { description = "Move focus down" })

-- Move focus with mainMod + hjkl (note: `semicolon` is used for right, kept as-is)
hl.bind(mainMod .. " + h",         hl.dsp.focus({ direction = "left" }), { description = "Move focus left" })
hl.bind(mainMod .. " + semicolon", hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }), { description = "Move focus up" })
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }), { description = "Move focus down" })

-- Switch workspaces with mainMod + [0-9] (10 is on key 0)
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }), { description = "Go to workspace " .. i })
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Move window to workspace " .. i })
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"), { description = "Toggle scratchpad workspace" })
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }), { description = "Move window to scratchpad" })

-- Change keyboard layout
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"), { description = "Switch keyboard layout" })

-- Screenshots (grim + slurp + wl-copy)
-- Print: full screen, SHIFT + Print: area. Both save to ~/Pictures and copy to the clipboard.
local shot = 'mkdir -p ~/Pictures && f=~/Pictures/$(date +%F_%H-%M-%S).png && '
hl.bind("Print",         hl.dsp.exec_cmd(shot .. 'grim "$f" && wl-copy < "$f"'), { description = "Screenshot the full screen (saved and copied)" })
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(shot .. 'grim -g "$(slurp)" "$f" && wl-copy < "$f"'), { description = "Screenshot a selected area (saved and copied)" })

-- Send to phone (tg-drop): whatever is on the clipboard (copied files, a screenshot, text) goes to Telegram
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("/home/mclovin/.local/bin/tg-drop send --clip --notify"), { description = "Send clipboard to phone (Telegram)" })

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Go to next workspace" })
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), { description = "Go to previous workspace" })

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Drag to move window" })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Drag to resize window" })

-- Laptop multimedia keys for volume and LCD brightness (were `bindel`).
-- Mute keys do not repeat: holding them would flip mute on and off.
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true, description = "Volume up" })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true, description = "Volume down" })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, description = "Toggle mute" })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, description = "Toggle microphone mute" })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -d intel_backlight set +10%"),      { locked = true, repeating = true, description = "Brightness up" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d intel_backlight set 10%-"),       { locked = true, repeating = true, description = "Brightness down" })

-- Switch sound between laptop speakers and the monitor's headphone jack
-- (H for headphones; was SHIFT + O, too easy to confuse with SHIFT + 0)
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("~/.config/hypr/scripts/audio-output-toggle.sh"), { description = "Switch sound output (speakers / headphones)" })

-- Requires playerctl (were `bindl`)
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true, description = "Next track" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play / pause" })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true, description = "Play / pause" })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true, description = "Previous track" })
