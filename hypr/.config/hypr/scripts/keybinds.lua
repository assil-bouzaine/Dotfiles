#!/usr/bin/env lua
-- Prints every Hyprland keybind as aligned terminal text, or --json for KeysCard.
--
-- `hyprctl binds` is useless with the Lua config (it only reports
-- "HL.Dispatcher(exec_cmd)"), so this runs the config files that call
-- hl.bind() against a fake `hl` that records each bind instead of applying it.
-- Loops, variables and string concatenation are therefore resolved for real.
-- JSON includes comment-derived groups and replayable dispatcher expressions.

local dir = (os.getenv("HOME") or "") .. "/.config/hypr/conf.d"
local json_mode = arg[1] == "--json"

local binds, sources = {}, {}

-- hl.dsp.window.move({ workspace = 3 }) -> { path = "window.move", args = { {workspace = 3} } }
local function dsp(path)
    return setmetatable({}, {
        __index = function(_, k) return dsp(path == "" and k or (path .. "." .. k)) end,
        __call  = function(_, ...) return { path = path, args = table.pack(...) } end,
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

-- Preserve the description fallback: first comment of the bind's paragraph.
local function section(file, line)
    local lines = sources[file]
    if not lines then return "" end
    local start = line
    while start > 1 and lines[start - 1]:match("%S") do start = start - 1 end
    return lines[start]:match("^%s*%-%-+%s*(.+)$") or ""
end

-- Groups use the nearest full-line comment block, including across local
-- variables, loops and helper functions. Inline comments aren't section titles.
local function nearest_section(file, line)
    local lines = sources[file]
    if not lines then return "" end
    for i = line - 1, 1, -1 do
        if lines[i]:match("^%s*%-%-") then
            local start = i
            while start > 1 and lines[start - 1]:match("^%s*%-%-") do start = start - 1 end
            return lines[start]:match("^%s*%-%-+%s*(.-)%s*$") or ""
        end
    end
    return ""
end

local function tidy(text, is_label)
    if is_label then text = text:gsub("^[%u%d%s+]+:%s*", "") else text = text:gsub(": .*$", "") end
    return (text:gsub("%. .*$", ""):gsub("[.:]$", ""))
end

-- Long explanatory comments share a concise title with their neighbouring
-- binds. New comment blocks still get a title without maintaining a second list
-- of keybinds here.
local GROUPS = {
    { "drop-down cards", "Apps and cards" },
    { "keybindings", "Apps and cards" },
    { "layouts, dock and pickers", "Layouts, dock and pickers" },
    { "keybind cheat sheet", "Keybinds" },
    { "keybinds card", "Keybinds" },
    { "dictation", "Dictation" },
    { "window groups", "Window groups" },
    { "next tab", "Window groups" },
    { "move focus", "Focus" },
    { "scratchpad", "Scratchpad" },
    { "workspaces", "Workspaces" },
    { "keyboard layout", "Keyboard layout" },
    { "screenshots", "Screenshots" },
    { "send to phone", "Send to phone" },
    { "move/resize windows", "Move and resize" },
    { "multimedia keys", "Media keys" },
    { "switch sound", "Media keys" },
    { "requires playerctl", "Media keys" },
    { "universal copy / paste", "Clipboard" },
}

local function group_title(text, previous)
    if text == "" then return previous end
    local lower = text:lower()
    if lower:match("^fallback ") then return previous end
    for _, entry in ipairs(GROUPS) do
        if lower:find(entry[1], 1, true) then return entry[2] end
    end
    local title = tidy(text, false):gsub("%s*%b()", "")
    local words = {}
    for word in title:gmatch("%S+") do
        if #words == 6 then break end
        words[#words + 1] = word
    end
    return #words > 0 and table.concat(words, " ") or previous
end

-- Serialize values as Lua, not shell text: hyprctl receives the whole expression
-- as one argument. Explicit table keys preserve arrays, maps and boolean keys.
local function lua_literal(v)
    local kind = type(v)
    if kind == "string" then return string.format("%q", v) end
    if kind == "nil" or kind == "number" or kind == "boolean" then return tostring(v) end
    assert(kind == "table", "unsupported dispatcher argument: " .. kind)
    local keys, fields = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        if type(a) == "boolean" then return not a and b end
        return a < b
    end)
    for _, k in ipairs(keys) do
        fields[#fields + 1] = "[" .. lua_literal(k) .. "] = " .. lua_literal(v[k])
    end
    return "{ " .. table.concat(fields, ", ") .. " }"
end

local function runnable(b)
    if b.opts.mouse or b.opts.release or type(b.action) ~= "table" or not b.action.path then return "" end
    local args = {}
    for i = 1, b.action.args.n do args[i] = lua_literal(b.action.args[i]) end
    return "hl.dsp." .. b.action.path .. "(" .. table.concat(args, ", ") .. ")"
end

local JSON_ESC = {
    ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
    ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}
local function json_string(s)
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
        return JSON_ESC[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

-- ── output ──────────────────────────────────────────────────────────────────
local function ulen(s) return select(2, s:gsub("[^\128-\191]", "")) end
local rows, keyw, group = {}, 0, "Apps and cards"
local previous_section
for _, b in ipairs(binds) do
    local caps = keycaps(b.keys)
    local comment = nearest_section(b.file, b.line)
    if previous_section ~= nil and comment ~= previous_section then group = group_title(comment, group) end
    previous_section = comment
    local keys = table.concat(caps, " + ")
    keyw = math.max(keyw, ulen(keys))
    -- Binds without descriptions fall back to their comment, then the action.
    local text = b.opts.description
    if not text or text == "" then
        local auto = label(b.action)
        local sec = section(b.file, b.line)
        text = sec ~= "" and tidy(sec, true) or auto
        if b.opts.release then text = text .. "  (on release)" end
    end
    rows[#rows + 1] = {
        caps = caps, keys = keys, description = text, group = group,
        combo = b.keys:match("^%s*(.-)%s*$"):gsub("%s*%+%s*", " + "):upper(),
        run = runnable(b),
    }
end

if json_mode then
    io.write('{"binds":[\n')
    for i, r in ipairs(rows) do
        local caps = {}
        for _, c in ipairs(r.caps) do caps[#caps + 1] = json_string(c) end
        io.write('  {"keys":[', table.concat(caps, ","), '],"combo":', json_string(r.combo),
            ',"description":', json_string(r.description), ',"group":', json_string(r.group),
            ',"run":', json_string(r.run), "}", i < #rows and ",\n" or "\n")
    end
    io.write("]}\n")
else
    for _, r in ipairs(rows) do
        io.write(r.keys, string.rep(" ", keyw - ulen(r.keys) + 3), r.description, "\n")
    end
end
