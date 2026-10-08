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

-- Thunar always opens on workspace 3
hl.window_rule({
    name  = "thunar",
    match = { class = "^(thunar)$" },

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

hl.window_rule({
    name  = "brave-workspace",
    match = { class = "^(brave-browser)$" },

    workspace   = "2",
    border_size = 0,
    rounding    = 0,
    group       = "set",
})

-- NOTE: `initial_class` matches below are kept 1:1 from the old conf.
-- If Hyprland complains on reload, switch them to `class`.
hl.window_rule({
    name  = "ristretto-workspace",
    match = { initial_class = "org.xfce.ristretto" },

    workspace = "8",
})

hl.window_rule({
    name  = "spotify-workspace",
    match = { initial_class = "spotify" },

    workspace = "4",
})

-- Workspace 2: floating layout, always no gaps (single rule — separate
-- workspace_rule() calls for the same workspace overwrite each other)
hl.workspace_rule({ workspace = "2", layout = "floating", gaps_in = 0, gaps_out = 0 })

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
    opacity   = "0.0 0.0",
    no_focus  = true,
    no_shadow = true,
})

hl.window_rule({
    name  = "file-picker-floating",
    match = {
        class = "^(brave)$",
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
