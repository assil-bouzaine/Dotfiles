-- Hyprland Lua config (requires Hyprland >= 0.55).
-- Ported 1:1 from hyprland.conf — no behavior changes on purpose.
-- Managed with GNU Stow from ~/.dotfiles (package: hypr).
-- This file only loads the modules in conf.d/ in order.
-- hyprlock.conf / hypridle.conf stay in hyprlang (unchanged by the Lua migration).

local HYPR_DIR = os.getenv("HOME") .. "/.config/hypr"

dofile(HYPR_DIR .. "/conf.d/monitors.lua")
dofile(HYPR_DIR .. "/conf.d/env.lua")
dofile(HYPR_DIR .. "/conf.d/autostart.lua")
dofile(HYPR_DIR .. "/conf.d/look.lua")
dofile(HYPR_DIR .. "/conf.d/animations.lua")
dofile(HYPR_DIR .. "/conf.d/input.lua")
dofile(HYPR_DIR .. "/conf.d/binds.lua")
dofile(HYPR_DIR .. "/conf.d/rules.lua")
