-- Windows and workspaces
-- See https://wiki.hypr.land/configuring/core/rules/
-- Ref https://wiki.hypr.land/configuring/core/rules/workspace-rules/
-- ("Smart gaps" commented example from the old conf was left commented out.)

hl.window_rule({
    name  = "center-floating",
    match = { float = true },

    center = true,
})

hl.window_rule({
    -- Ignore maximize requests from all apps. You'll probably like this.
    name  = "suppress-maximize-events",
    match = { class = ".*" },

    suppress_event = "maximize",
})

-- Terminal always opens on workspace 1 (old comment said 2, value was 1 — kept)
hl.window_rule({
    name  = "terminal-workspace",
    match = { class = "^(kitty)$" },

    workspace = "1",
})

hl.window_rule({
    name  = "libreoffice-workspace",
    match = { class = "^(libreoffice-.*)$" },

    workspace = "9",
})

-- VSCode always opens on workspace 3, stacked as tabs in one group
-- (a second window joins the group if it is focused; switch with SUPER + TAB)
hl.window_rule({
    name  = "vscode-workspace",
    match = { class = "^(com\\.microsoft\\.VSCode|[Cc]ode|code-oss)$" },

    workspace = "3",
    group     = "set",
})

-- Dolphin always opens on workspace 3
hl.window_rule({
    name  = "dolphin",
    match = { class = "^(org\\.kde\\.dolphin)$" },

    workspace = "3",
})

hl.window_rule({
    -- Fix some dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },

    no_focus = true,
})

-- Hyprland-run windowrule
hl.window_rule({
    name  = "move-hyprland-run",
    match = { class = "hyprland-run" },

    move  = "20 monitor_h-120",
    float = true,
})

-- Brave's group is locked so other apps opened on workspace 2 don't get
-- pulled in as tabs (group.auto_group adds new windows to the focused group);
-- "invade" still lets new Brave windows join it.
hl.window_rule({
    name  = "brave-workspace",
    match = { class = "^(brave-browser)$" },

    workspace = "2",
    group     = "set lock invade",
})

-- NOTE: the `initial_class` match below is kept 1:1 from the old conf.
-- If Hyprland complains on reload, switch them to `class`.
hl.window_rule({
    name  = "gwenview-workspace",
    match = { initial_class = "org.kde.gwenview" },

    workspace = "8",
})

-- Spotify reports its class as "Spotify" (capital S); match both spellings.
-- "barred" keeps it out of whatever group is focused when it opens.
hl.window_rule({
    name  = "spotify-workspace",
    match = { class = "^([Ss]potify)$" },

    workspace = "4",
    group     = "barred",
})

-- Workspace 2: floating layout (single rule — separate workspace_rule()
-- calls for the same workspace overwrite each other). Normal gaps, so Brave
-- doesn't fill the screen edge to edge.
hl.workspace_rule({ workspace = "2", layout = "floating" })

hl.window_rule({
    name  = "xwayland-video-bridge-fixes",
    match = { class = "xwaylandvideobridge" },

    no_initial_focus = true,
    no_focus         = true,
    no_anim          = true,
    no_blur          = true,
    max_size         = "1 1",
    opacity          = 0.0,
})

hl.window_rule({
    name  = "hide-google-meet-sharing",
    match = { title = "^(meet.google.com is sharing your screen.)$" },

    workspace = "6",
    opacity   = 0.0,
    no_focus  = true,
    no_shadow = true,
})

hl.window_rule({
    name  = "file-picker-floating",
    match = {
        class = "^(brave-browser)$",
        title = "^(.* wants to open.*|.* wants to save.*)$",
    },

    float  = true,
    center = true,
    size   = "900 600",
})

hl.window_rule({
    name  = "feh-floating-centered",
    match = { class = "^(feh)$" },

    float  = true,
    center = true,
})

-- Waybar: blur the desktop behind the translucent bar
hl.layer_rule({
    name  = "waybar-blur",
    match = { namespace = "^(waybar)$" },

    blur         = true,
    ignore_alpha = 0.3,
})

-- Bluetooth/network settings and htop opened from the bar float in the middle
hl.window_rule({
    name  = "bar-popups-floating",
    match = { class = "^(blueman-manager|nm-connection-editor|bar-htop)$" },

    float  = true,
    center = true,
    size   = "800 520",
})
