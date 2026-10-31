-- Keybindings
-- See https://wiki.hypr.land/configuring/core/binds/

local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "rofi -show drun"

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Drop-down cards shared with the waybar buttons (apps, Wi-Fi, Bluetooth).
-- Pressing the key again while a card is open closes it.
local cards = "pkill -x rofi || "

hl.bind(mainMod .. " + W",      hl.dsp.exec_cmd("brave"))
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C",      hl.dsp.window.close())
hl.bind(mainMod .. " + M",      hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + F",      hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V",      hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd(cards .. "rofi -show drun -theme ~/.config/waybar/scripts/launcher.rasi"))
hl.bind(mainMod .. " + N",      hl.dsp.exec_cmd(cards .. "networkmanager_dmenu --config ~/.config/waybar/networkmanager-dmenu.ini"))
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd(cards .. "rofi-bluetooth -theme ~/.config/waybar/scripts/card.rasi -l 8"))
hl.bind(mainMod .. " + P",      hl.dsp.window.pseudo()) -- dwindle
hl.bind("SUPER + L",            hl.dsp.exec_cmd("hyprlock"))

-- Hex dictation (Anomaly). Hyprland's GlobalShortcuts portal never assigns
-- keys to app shortcuts, so Hex reports "desktop did not grant this shortcut".
-- Bind Hex's CLI instead: hold SUPER + Z to talk, release to transcribe+paste.
hl.bind(mainMod .. " + Z",         hl.dsp.exec_cmd("hex dictation start"))
hl.bind(mainMod .. " + Z",         hl.dsp.exec_cmd("hex dictation stop"), { release = true })
-- Fallback when SUPER is let go before Z: the SUPER + Z release bind no longer
-- matches, so also stop on a bare Z release. non_consuming keeps Z typing
-- normally; `hex dictation stop` does nothing while Hex is idle.
hl.bind("Z", hl.dsp.exec_cmd("hex dictation stop"), { release = true, non_consuming = true })
hl.bind(mainMod .. " + SHIFT + Z", hl.dsp.exec_cmd("hex paste-last"))
hl.bind(mainMod .. " + ALT + Z",   hl.dsp.exec_cmd("hex dictation cancel"))

-- Window groups (tabbed windows)
hl.bind(mainMod .. " + G", hl.dsp.group.toggle())

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
end)

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Move focus with mainMod + hjkl (note: `semicolon` is used for right, kept as-is)
hl.bind(mainMod .. " + h",         hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + semicolon", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9] (10 is on key 0)
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Change keyboard layout
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))

-- Screenshots (grim + slurp + wl-copy)
-- Print: full screen, SHIFT + Print: area. Both save to ~/Pictures and copy to the clipboard.
local shot = 'mkdir -p ~/Pictures && f=~/Pictures/$(date +%F_%H-%M-%S).png && '
hl.bind("Print",         hl.dsp.exec_cmd(shot .. 'grim "$f" && wl-copy < "$f"'))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd(shot .. 'grim -g "$(slurp)" "$f" && wl-copy < "$f"'))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness (were `bindel`)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -d intel_backlight set +10%"),      { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -d intel_backlight set 10%-"),       { locked = true, repeating = true })

-- Switch sound between laptop speakers and the monitor's headphone jack
-- (H for headphones; was SHIFT + O, too easy to confuse with SHIFT + 0)
hl.bind(mainMod .. " + SHIFT + H", hl.dsp.exec_cmd("~/.config/hypr/scripts/audio-output-toggle.sh"))

-- Requires playerctl (were `bindl`)
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })
