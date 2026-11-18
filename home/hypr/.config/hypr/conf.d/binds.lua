-- Keybindings
-- See https://wiki.hypr.land/configuring/core/binds/

local terminal    = "kitty"
local fileManager = "dolphin"
local menu        = "~/.config/quickshell/cards/card menu" -- the Arch menu (bar logo): apps, settings, power

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Drop-down cards shared with the waybar buttons (Arch menu, Wi-Fi, Bluetooth).
-- Pressing the key again while a card is open closes it.

hl.bind(mainMod .. " + W",      hl.dsp.exec_cmd("brave"), { description = "Open Brave browser" })
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal), { description = "Open terminal (kitty)" })
hl.bind(mainMod .. " + Q",      hl.dsp.window.close(), { description = "Close the active window" })
hl.bind(mainMod .. " + M",      hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"), { description = "Log out (exit Hyprland)" })
hl.bind(mainMod .. " + F",      hl.dsp.exec_cmd(fileManager), { description = "Open file manager (Dolphin)" })
hl.bind(mainMod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle floating for the active window" })
hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd(menu), { description = "Open the Arch menu (type to find an app or setting)" })
hl.bind(mainMod .. " + N",      hl.dsp.exec_cmd("~/.config/quickshell/cards/card netcard"), { description = "Open / close the network card" })
hl.bind(mainMod .. " + B",      hl.dsp.exec_cmd("~/.config/quickshell/cards/card bluetooth"), { description = "Open / close the Bluetooth card" })
hl.bind(mainMod .. " + SHIFT + SPACE", hl.dsp.exec_cmd("~/.config/waybar/scripts/bar-toggle.sh"), { description = "Show / hide the top bar" })
hl.bind(mainMod .. " + CTRL + A", hl.dsp.exec_cmd("~/.config/quickshell/cards/card agents"), { description = "Open / close the agents card (limits, usage, start an agent)" })
hl.bind(mainMod .. " + CTRL + I", hl.dsp.exec_cmd("~/.config/waybar/scripts/awake.sh toggle"), { description = "Stay awake on / off (no lock, screen off or sleep)" })
hl.bind(mainMod .. " + CTRL + SPACE", hl.dsp.exec_cmd("~/.config/quickshell/wallpicker/wallpicker"), { description = "Pick a wallpaper" })
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd("~/.config/hypr/scripts/tasks"), { description = "Task manager (btop): open, focus, or close" })
hl.bind(mainMod .. " + P",      hl.dsp.window.pseudo(), { description = "Toggle pseudo-tiling for the active window" }) -- dwindle

-- Omarchy 4.5-style layouts, dock and pickers (on SUPER + ALT / SUPER + CTRL so
-- none of the keys above change). Floating workspaces: conf.d/workspace-modes.lua.
-- Dock, app grid and pickers: ~/.config/quickshell/cards. Themes: ~/.local/bin/theme.
hl.bind(mainMod .. " + ALT + L",     hl.dsp.exec_cmd("~/.config/hypr/scripts/layout-toggle"), { description = "Switch this workspace between tiling and floating (dock + titlebars)" })
hl.bind(mainMod .. " + ALT + M",     hl.dsp.exec_cmd("~/.config/hypr/scripts/window-minimize"), { description = "Minimize the window to the dock (floating workspaces)" })
hl.bind(mainMod .. " + ALT + SPACE", hl.dsp.exec_cmd("~/.config/quickshell/cards/card apps"), { description = "Open / close the app grid (all apps)" })
hl.bind(mainMod .. " + CTRL + T",    hl.dsp.exec_cmd("~/.config/quickshell/cards/card themes"), { description = "Pick a theme (colours, wallpaper, terminal, bar, apps)" })
hl.bind(mainMod .. " + CTRL + F",    hl.dsp.exec_cmd("~/.config/quickshell/cards/card fonts"), { description = "Pick a font (terminal, bar, dock, cards, lock screen)" })
hl.bind("SUPER + L",            hl.dsp.exec_cmd("hyprlock"), { description = "Lock the screen" })

-- Keybinds card (SUPER + K, like Omarchy): every bind in this config, search
-- as you type, Enter runs the one you pick. quickshell/cards/KeysCard.qml reads
-- them from scripts/keybinds.lua, so there's nothing to keep in sync.
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("~/.config/quickshell/cards/card keys"), { description = "Show every keybind (search, Enter runs it)" })

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

-- Move focus with mainMod + h j ; (semicolon is right). Up is only SUPER + up:
-- SUPER + K opens the keybinds card.
hl.bind(mainMod .. " + h",         hl.dsp.focus({ direction = "left" }), { description = "Move focus left" })
hl.bind(mainMod .. " + semicolon", hl.dsp.focus({ direction = "right" }), { description = "Move focus right" })
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
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("~/.local/bin/tg-drop send --clip --notify"), { description = "Send clipboard to phone (Telegram)" })

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

-- Universal copy / paste / cut / select all (as in Omarchy 4.5): SUPER + C/V/X/A
-- send CTRL + C/V/X/A to the focused window, or CTRL + SHIFT + C/V in a
-- terminal. Keys go down and up as two steps because send_shortcut can leave a
-- synthetic key stuck; wtype won't do (the held SUPER merges into its chord).
-- Close window moved to SUPER + Q and floating to SUPER + SHIFT + V for this.
local terminals = { kitty = true, Alacritty = true, foot = true, ["com.mitchellh.ghostty"] = true, wezterm = true }

local function send_once(mods, key)
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
        hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
end

local function clipboard_key(key, terminal_too)
    return function()
        local win = hl.get_active_window()
        if terminal_too and win and terminals[win.class] then
            send_once("CTRL SHIFT", key)
        else
            send_once("CTRL", key)
        end
    end
end

hl.bind(mainMod .. " + C", clipboard_key("C", true),  { description = "Copy (any app, terminals too)" })
hl.bind(mainMod .. " + V", clipboard_key("V", true),  { description = "Paste (any app, terminals too)" })
hl.bind(mainMod .. " + X", clipboard_key("X", false), { description = "Cut" })
hl.bind(mainMod .. " + A", clipboard_key("A", false), { description = "Select all" })
