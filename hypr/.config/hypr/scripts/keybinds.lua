#!/usr/bin/env lua
-- Prints every Hyprland keybind as one pango-markup row for rofi (keybinds.sh).
--
-- `hyprctl binds` is useless with the Lua config (it only reports
-- "HL.Dispatcher(exec_cmd)"), so this runs the config files that call
-- hl.bind() against a fake `hl` that records each bind instead of applying it.
-- Loops, variables and string concatenation are therefore resolved for real.
-- Each row is the keys plus the bind's `description` (plain English, set in
-- binds.lua); that text is what rofi searches.

local dir = (os.getenv("HOME") or "") .. "/.config/hypr/conf.d"
local LABEL_MAX = 60

local binds, sources = {}, {}

-- hl.dsp.window.move({ workspace = 3 }) -> { path = "window.move", args = { {workspace = 3} } }
local function dsp(path)
    return setmetatable({}, {
        __index = function(_, k) return dsp(path == "" and k or (path .. "." .. k)) end,
        __call  = function(_, ...) return { path = path, args = { ... } } end,
    })
end

local noop
noop = setmetatable({}, {
    __index = function() return noop end,
    __call  = function() return noop end,
})

hl = setmetatable({
    dsp = dsp(""),
    bind = function(keys, action, opts)
        local info = debug.getinfo(2, "Sl")
        binds[#binds + 1] = {
            keys = keys, action = action, opts = opts or {},
            file = info.source:gsub("^@", ""), line = info.currentline,
        }
    end,
}, { __index = function() return noop end })

local function read_lines(path)
    local t = {}
    for l in io.lines(path) do t[#t + 1] = l end
    return t
end

local ls = io.popen('ls "' .. dir .. '"/*.lua 2>/dev/null')
for path in ls:lines() do
    local lines = read_lines(path)
    if table.concat(lines, "\n"):find("hl%.bind") then
        sources[path] = lines
        pcall(dofile, path)
    end
end
ls:close()

-- ── keys ────────────────────────────────────────────────────────────────────
local KEYS = {
    SUPER = "Super", SHIFT = "Shift", ALT = "Alt", CTRL = "Ctrl", CONTROL = "Ctrl",
    RETURN = "Enter", SPACE = "Space", TAB = "Tab", ESCAPE = "Esc", PRINT = "Print",
    LEFT = "←", RIGHT = "→", UP = "↑", DOWN = "↓",
    SEMICOLON = ";", COMMA = ",", PERIOD = ".", SLASH = "/", MINUS = "-", EQUAL = "=",
    ["MOUSE:272"] = "Left Click", ["MOUSE:273"] = "Right Click", ["MOUSE:274"] = "Middle Click",
    ["CODE:61"] = "/",
    MOUSE_DOWN = "Scroll Down", MOUSE_UP = "Scroll Up",
    XF86AUDIORAISEVOLUME = "Vol +", XF86AUDIOLOWERVOLUME = "Vol -",
    XF86AUDIOMUTE = "Mute", XF86AUDIOMICMUTE = "Mic Mute",
    XF86MONBRIGHTNESSUP = "Bright +", XF86MONBRIGHTNESSDOWN = "Bright -",
    XF86AUDIONEXT = "Next", XF86AUDIOPREV = "Prev",
    XF86AUDIOPLAY = "Play", XF86AUDIOPAUSE = "Pause",
}

local function keycaps(combo)
    local caps = {}
    for raw in combo:gmatch("[^+]+") do
        local part = raw:match("^%s*(.-)%s*$")
        local nice = KEYS[part:upper()]
        if not nice then
            nice = part:gsub("^XF86", "")
            if #nice == 1 then nice = nice:upper() end
        end
        caps[#caps + 1] = nice
    end
    return caps
end

-- ── labels ──────────────────────────────────────────────────────────────────
local function value(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = k .. " " .. value(v[k] ~= nil and v[k] or v[tonumber(k)]) end
    return table.concat(out, ", ")
end

local function label(action)
    if type(action) == "function" then return "custom function", true end
    if type(action) ~= "table" or not action.path then return "?", true end
    if action.path == "exec_cmd" then
        local cmd = tostring(action.args[1] or "")
        cmd = cmd:gsub("^pkill %-x rofi || ", ""):gsub((os.getenv("HOME") or "\0"):gsub("%p", "%%%0"), "~")
        return cmd, false
    end
    local name = action.path:gsub("[._]", " ")
    local args = {}
    for _, a in ipairs(action.args) do args[#args + 1] = value(a) end
    if #args > 0 then name = name .. " → " .. table.concat(args, ", ") end
    return name, false
end

-- First comment line of the paragraph (blank-line separated block) holding `line`.
local function section(file, line)
    local lines = sources[file]
    if not lines then return "" end
    local start = line
    while start > 1 and lines[start - 1]:match("%S") do start = start - 1 end
    local text = lines[start]:match("^%s*%-%-+%s*(.+)$")
    if not text then return "" end
    return text
end

local function tidy(text, is_label)
    if is_label then text = text:gsub("^[%u%d%s+]+:%s*", "") else text = text:gsub(": .*$", "") end
    return (text:gsub("%. .*$", ""):gsub("[.:]$", ""))
end

-- ── output ──────────────────────────────────────────────────────────────────
local function esc(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
local function ulen(s) return select(2, s:gsub("[^\128-\191]", "")) end
local function cut(s, n)
    if ulen(s) <= n then return s end
    local i, count = 1, 0
    while count < n - 1 do
        i = i + 1
        while (s:byte(i) or 0) >= 128 and s:byte(i) < 192 do i = i + 1 end
        count = count + 1
    end
    return s:sub(1, i - 1) .. "…"
end

local rows, keyw = {}, 0
for _, b in ipairs(binds) do
    local caps = keycaps(b.keys)
    local w = #caps - 1
    for _, c in ipairs(caps) do w = w + ulen(c) + 2 end
    if w > keyw then keyw = w end
    -- Shown (and searched) text: the bind's `description`. Binds without one
    -- fall back to their comment, then to the dispatcher / command.
    local text = b.opts.description
    if not text or text == "" then
        local auto = label(b.action)
        local sec = section(b.file, b.line)
        text = sec ~= "" and tidy(sec, true) or auto
        if b.opts.release then text = text .. "  (on release)" end
    end
    rows[#rows + 1] = { caps = caps, w = w, text = cut(text, LABEL_MAX) }
end

for _, r in ipairs(rows) do
    local caps = {}
    for _, c in ipairs(r.caps) do
        caps[#caps + 1] = '<span background="#2b3440" foreground="#33ccff" weight="bold"> ' .. esc(c) .. ' </span>'
    end
    io.write(table.concat(caps, " "), string.rep(" ", keyw - r.w + 3), esc(r.text), "\n")
end
