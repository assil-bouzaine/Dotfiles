-- Workspace layouts: tiling or floating, per workspace (SUPER + ALT + L).
-- Ported from Omarchy 4.5 (default/hypr/workspace-modes.lua, MIT) and cut down
-- to the two layouts this desktop uses.
--
-- Hyprland has no floating *layout* (an unknown layout name quietly falls back
-- to dwindle), so floating is applied to the windows themselves. Every tiled
-- window on a floating workspace is floated and tagged, so ending the mode tiles
-- exactly those again. Windows that float on their own (dialogs, and the apps
-- in OWN_FLOAT below, which have float rules in rules.lua) are left alone.
--
-- On a floating workspace:
--   * new windows open floating at a comfortable size, centred and cascaded
--   * windows get titlebars (close / maximize / minimize) from Omarchy's
--     titlebars plugin in the theme's colours, when it is installed
--     (~/.dotfiles/home/titlebars, `titlebars-rebuild` after Hyprland upgrades)
--   * focus follows clicks instead of the mouse
--   * the dock shows at the bottom (quickshell/cards/Dock.qml); SUPER + ALT + M
--     or the titlebar's − minimizes a window into it
--
-- Every boot starts the same way: workspace 1 floating, the rest tiling
-- (DEFAULT_FLOATING). SUPER + ALT + L changes a workspace until the next
-- reboot. The current modes live in $XDG_RUNTIME_DIR/workspace-modes, one
-- "<id> floating" line per floating workspace: a reboot empties that folder,
-- so the first config load writes the defaults again, while config reloads
-- (theme switches) keep whatever was changed. scripts/layout-toggle edits the
-- file and calls workspace_mode() through `hyprctl eval`; the dock reads it too.

local HOME = os.getenv("HOME")
local STATE_FILE = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/workspace-modes"
local DEFAULT_FLOATING = { "1" }   -- floating after every boot; keep scripts/layout-toggle in step
local TITLEBARS = "/usr/lib/omarchy-hyprland-titlebars/titlebars.so"
local MINIMIZE = HOME .. "/.config/hypr/scripts/window-minimize"

local FLOATED_TAG = "mode-floated"          -- floated by the mode: tiled again when it ends
local WORKSPACE_TAG = "floating-workspace"  -- on a floating workspace: titlebar, opaque
local OPENED_TAG = "mode-opened"            -- floated by the open rule as it opened
local OPEN_RULE = "floating-open-"

-- Apps with float rules of their own (rules.lua): they open at their own size
-- and stay floating when the mode ends.
local OWN_FLOAT_CLASS = "hyprland-run|feh|blueman-manager|nm-connection-editor|bar-htop|bar-tasks|bar\\.tasks|org\\.pulseaudio\\.pavucontrol|pavucontrol"
local OWN_FLOAT_TITLE = "^(.* wants to open.*|.* wants to save.*|Discord Popout)$"
-- Apps rules.lua sends to a workspace of their own. The open rule is checked
-- before that move, so it would float them on their way to a tiled workspace;
-- they skip it, and `arrange` floats them after they open if their workspace
-- floats too. Keep in step with the workspace rules in rules.lua.
local OWN_WORKSPACE_CLASS = "kitty|libreoffice-.*|com\\.microsoft\\.VSCode|[Cc]ode|code-oss|com\\.t3tools\\.T3Code|org\\.kde\\.dolphin|brave-browser|org\\.kde\\.gwenview|[Ss]potify|discord|org\\.mozilla\\.Thunderbird|thunderbird"

local modes = {}            -- workspace id (string) -> "floating"
local watching = false
local floating_ready = false -- set up once per config load, on the first floating workspace
local set_up_floating
local cascade = 0
local open_rules = 0

local function set_floating(window, floating)
    hl.dispatch(hl.dsp.window.float({ action = floating and "on" or "off", window = window }))
end

local function set_tag(window, tag, on)
    hl.dispatch(hl.dsp.window.tag({ tag = (on and "+" or "-") .. tag, window = window }))
end

local function claimed()
    local addresses = {}
    for _, window in ipairs(hl.get_windows({ tag = FLOATED_TAG })) do
        addresses[window.address] = true
    end
    return addresses
end

-- Special workspaces (scratchpad, minimized) and named ones (negative ids)
-- keep whatever state a window arrived with.
local function floating_workspace(id)
    id = tonumber(id)
    return id ~= nil and id >= 1 and modes[tostring(id)] == "floating"
end

local function anything_floats()
    return next(modes) ~= nil
end

local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

-- A window the mode floats gets a comfortable size in the middle of its
-- monitor, each one stepped from the last so a workspace floated all at once
-- doesn't stack every window exactly on the one beneath it.
local function place(window)
    local monitor = window.monitor
    if not monitor or not monitor.width then
        return
    end

    local width = math.floor(monitor.width / monitor.scale)
    local height = math.floor(monitor.height / monitor.scale)
    if (monitor.transform or 0) % 2 == 1 then
        width, height = height, width
    end
    local reserved = monitor.reserved or {}
    width = width - (reserved.left or 0) - (reserved.right or 0)
    height = height - (reserved.top or 0) - (reserved.bottom or 0)

    hl.dispatch(hl.dsp.window.resize({
        x = math.min(1100, math.floor(width * 0.64)),
        y = math.min(760, math.floor(height * 0.68)),
        relative = false,
        window = window,
    }))
    hl.dispatch(hl.dsp.window.center({ window = window }))

    cascade = (cascade + 1) % 5
    hl.dispatch(hl.dsp.window.move({ x = cascade * 24 - 48, y = cascade * 24 - 48, relative = true, window = window }))
end

-- A window already floating on its own account is left unclaimed, so it still
-- floats when the mode ends. A fullscreen window is left as it is.
-- Every tiled window is claimed before any is floated: floating one member of
-- a group floats the rest, and a single pass would then find those already
-- floating and strand them when the mode ends.
local function float_for_mode(windows)
    local claiming = {}
    for _, window in ipairs(windows) do
        set_tag(window, WORKSPACE_TAG, true)
        if not window.floating and (window.fullscreen or 0) == 0 then
            set_tag(window, FLOATED_TAG, true)
            table.insert(claiming, window)
        end
    end
    for _, window in ipairs(claiming) do
        set_floating(window, true)
        place(window)
    end
end

-- A pinned window was pinned on purpose, and tiling it would unpin it too.
local function tile_for_mode(window, mine)
    set_tag(window, WORKSPACE_TAG, false)
    if not mine[window.address] or window.pinned then
        return
    end
    set_tag(window, FLOATED_TAG, false)
    set_floating(window, false)
end

local function floating_ids()
    local ids = {}
    for id in pairs(modes) do
        table.insert(ids, id)
    end
    table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
    return ids
end

-- A window opening on a floating workspace floats from its first frame, at the
-- size the mode gives it, instead of opening tiled and shrinking into place.
-- Modal dialogs and OWN_FLOAT apps float on their own account, at their own size.
local OPEN_WIDTH = "min(1100,monitor_w*0.64)"
local OPEN_HEIGHT = "min(760,monitor_h*0.68)"

local function open_position()
    local step = cascade * 24 - 48
    return string.format("(monitor_w-%s)/2+(%d) (monitor_h-%s)/2+(%d)", OPEN_WIDTH, step, OPEN_HEIGHT, step)
end

local function sync_open_rules()
    local ids = floating_ids()
    for i, id in ipairs(ids) do
        hl.window_rule({
            name = OPEN_RULE .. i,
            enabled = true,
            match = {
                workspace = id,
                modal = false,
                class = "negative:^(" .. OWN_FLOAT_CLASS .. "|" .. OWN_WORKSPACE_CLASS .. ")$",
                title = "negative:" .. OWN_FLOAT_TITLE,
            },
            float = true,
            size = OPEN_WIDTH .. " " .. OPEN_HEIGHT,
            move = open_position(),
            tag = "+" .. OPENED_TAG,
        })
    end
    for i = #ids + 1, open_rules do
        hl.window_rule({ name = OPEN_RULE .. i, enabled = false })
    end
    open_rules = math.max(open_rules, #ids)
end

-- A rule's tag leaves with the rule, so a window the open rule floated is
-- claimed for good as it opens. Rule tags are listed with a trailing "*".
local function claim_opened(window)
    for _, tag in ipairs(window.tags or {}) do
        if tag == OPENED_TAG or tag == OPENED_TAG .. "*" then
            set_tag(window, FLOATED_TAG, true)
            cascade = (cascade + 1) % 5 -- the next window steps on from this one
            sync_open_rules()
            return
        end
    end
end

-- A maximized window has a floating workspace to itself until another one
-- opens there, which brings it back to its own size so the two can share it.
local function unmaximize_others(window)
    local id = window.workspace and window.workspace.id
    if not floating_workspace(id) then
        return
    end
    for _, other in ipairs(hl.get_workspace_windows(tostring(id))) do
        if other.address ~= window.address and (other.fullscreen or 0) == 1 then
            hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = other }))
        end
    end
end

-- The workspace is passed in when a window is still on its way to it.
local function arrange(windows, workspace)
    local floating = {}
    local mine = claimed()
    for _, window in ipairs(windows) do
        local id = tonumber(workspace and workspace.id or (window.workspace and window.workspace.id))
        if id and id >= 1 then
            if floating_workspace(id) then
                table.insert(floating, window)
            else
                tile_for_mode(window, mine)
            end
        end
    end
    float_for_mode(floating)
end

-- Overlapping windows are picked with the pointer, so a floating workspace
-- focuses on click; every other workspace keeps input.lua's follow_mouse.
local input = {}

local function update_input()
    local workspace = hl.get_active_workspace()
    local active = workspace ~= nil and floating_workspace(workspace.id)
    if active == input.floating then
        return
    end
    input.floating = active
    hl.config({ input = { follow_mouse = active and 0 or input.follow_mouse } })
end

-- Windows arrive by opening and by being carried in, and a window rule only
-- fires for the first. One carried out to a tiled workspace gives up the
-- floating the mode gave it.
local function watch()
    if watching then
        return
    end
    watching = true
    input.follow_mouse = hl.get_config("input.follow_mouse")

    hl.on("window.open", function(window)
        claim_opened(window)
        unmaximize_others(window)
        arrange({ window })
        update_input()
    end)

    -- At the first config load no workspace is active yet, so a workspace
    -- that floats from boot (workspace 1) gets its click-to-focus here.
    hl.on("hyprland.start", function()
        hl.timer(function()
            input.floating = nil
            update_input()
        end, { type = "oneshot", timeout = 300 })
    end)

    -- A move is still being committed when this fires; changing the window's
    -- floating state underneath it loses the move, so let it land first.
    hl.on("window.move_to_workspace", function(window, workspace)
        hl.timer(function()
            arrange({ window }, workspace)
        end, { type = "oneshot", timeout = 1 })
    end)

    -- A tiled window leaving fullscreen on a floating workspace floats then.
    hl.on("window.fullscreen", function(window)
        hl.timer(function()
            arrange({ window })
        end, { type = "oneshot", timeout = 1 })
    end)

    hl.on("workspace.active", update_input)
    hl.on("monitor.focused", update_input)
end

-- scripts/layout-toggle: hyprctl eval 'workspace_mode({ workspace = "3", mode = "floating" })'
function workspace_mode(spec)
    watch()
    local id = tostring(spec.workspace)
    modes[id] = spec.mode == "floating" and "floating" or nil
    if anything_floats() then
        set_up_floating()
    end
    arrange(hl.get_workspace_windows(id))
    sync_open_rules()
    update_input()
end

-- ── Titlebars ───────────────────────────────────────────────────────────

-- Colours and font come from the theme (THEME, set by the generated
-- ~/.local/state/theme/hyprland.lua that look.lua runs).
local function titlebars()
    if not file_exists(TITLEBARS) then
        return
    end
    hl.plugin.load(TITLEBARS)
    -- The plugin reloads the config once it is in; that pass finds hyprbars.
    if not hl.plugin.hyprbars then
        return
    end

    local theme = THEME or {}
    local bar = theme.titlebar or "rgb(24283b)"
    local text = theme.foreground or "rgb(c0caf5)"
    local window = [[window = "address:%WINDOW%"]]
    local maximize = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\", " .. window .. " })'"

    hl.config({
        plugin = {
            hyprbars = {
                enabled = true,
                workspace_tag = WORKSPACE_TAG,
                bar_height = 30,
                bar_color = bar,
                col = { text = text },
                bar_text_font = theme.font or "monospace",
                bar_text_size = 12,
                bar_text_weight = "normal",
                bar_text_align = "left",
                bar_buttons_alignment = "right",
                bar_part_of_window = true,
                bar_precedence_over_border = true,
                bar_padding = 10,
                bar_button_padding = 8,
                button_rounding = 0,
                icon_on_hover = false,
                inactive_button_color = bar,
                on_double_click = maximize,
            },
        },
    })

    for _, button in ipairs({
        { icon = "×", action = "hyprctl dispatch 'hl.dsp.window.close({ " .. window .. " })'" },
        { icon = "□", action = maximize },
        { icon = "−", action = MINIMIZE .. " %WINDOW%" }, -- the dock brings it back
    }) do
        hl.plugin.hyprbars.add_button({ bg_color = bar, fg_color = text, size = 20, icon = button.icon, action = button.action })
    end
end

-- Hyprland unloads a plugin the config stops asking for, and bringing it back
-- costs a cascade of reloads, so once in it stays asked for all session.
local function titlebars_loaded()
    for _, plugin in ipairs(hl.get_loaded_plugins and hl.get_loaded_plugins() or {}) do
        if plugin.name == "hyprbars" then
            return true
        end
    end
    return false
end

-- What floating workspaces need on top of the rest of the config. Runs while
-- the config loads when something floats already, otherwise the moment a
-- workspace starts floating, so SUPER + ALT + L brings titlebars without a reload.
set_up_floating = function()
    if floating_ready then
        return
    end
    floating_ready = true

    -- Overlapping windows need depth to tell apart (look.lua has shadows on).
    if not hl.get_config("decoration.shadow.enabled") then
        hl.config({ decoration = { shadow = { enabled = true, range = 16, render_power = 3, color = "rgba(00000035)" } } })
        hl.window_rule({ name = "floating-ws-no-shadow", match = { class = ".*" }, no_shadow = true })
        hl.window_rule({ name = "floating-ws-shadow", match = { tag = WORKSPACE_TAG }, no_shadow = false })
    end
    -- A translucent window over another is hard to read.
    hl.window_rule({ name = "floating-ws-opaque", match = { tag = WORKSPACE_TAG }, opacity = "1.0 override 1.0 override" })

    titlebars()
end

-- ── Load ────────────────────────────────────────────────────────────────

local function load_saved()
    local f = io.open(STATE_FILE, "r")
    if not f then
        -- First load since boot: start from the defaults and write them down
        -- for layout-toggle, window-minimize and the dock.
        local out = io.open(STATE_FILE, "w")
        for _, id in ipairs(DEFAULT_FLOATING) do
            modes[id] = "floating"
            if out then
                out:write(id .. " floating\n")
            end
        end
        if out then
            out:close()
        end
        return
    end
    for line in f:lines() do
        local id, mode = line:match("^%s*(%d+)%s+(%a+)")
        if id and mode == "floating" then
            modes[id] = "floating"
        end
    end
    f:close()
end

load_saved()

-- A reload is a fresh start here but not for the windows: bring each one in
-- line with the saved modes, including windows a mode that has since ended
-- floated (they still carry its tags).
local leftovers = #hl.get_windows({ tag = FLOATED_TAG }) > 0 or #hl.get_windows({ tag = WORKSPACE_TAG }) > 0
if anything_floats() or leftovers then
    watch()
end
if watching then
    arrange(hl.get_windows())
    update_input()
end
if anything_floats() then
    set_up_floating()
elseif titlebars_loaded() and file_exists(TITLEBARS) then
    hl.plugin.load(TITLEBARS)
end
sync_open_rules()
