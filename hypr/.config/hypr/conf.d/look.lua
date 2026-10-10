-- Look and feel
-- Refer to https://wiki.hypr.land/configuring/core/config-options/

hl.config({
    -- https://wiki.hypr.land/configuring/core/config-options/#general
    general = {
        gaps_in  = 5,
        gaps_out = 15,

        border_size = 2,

        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/configuring/extra/tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },

    -- https://wiki.hypr.land/configuring/core/config-options/#decoration
    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a, -- rgba(1a1a1aee)
        },

        blur = {
            enabled  = true,
            size     = 5,
            passes   = 3,
            vibrancy = 0.1696,
        },
    },

    -- See https://wiki.hypr.land/configuring/layouts/dwindle-layout/ for more
    dwindle = {
        preserve_split = true, -- You probably want this
    },

    -- See https://wiki.hypr.land/configuring/layouts/master-layout/ for more
    master = {
        new_status = "master",
    },

    -- The tab bar at the top of grouped windows (SUPER + G / SUPER + TAB).
    group = {
        groupbar = {
            enabled       = false, -- u can change this to true to see a blue line
            font_size     = 0,     -- hides the title text
            height        = 1,     -- thin line height
            gradients     = false, -- no gradient, flat color
            render_titles = false, -- explicitly disable title rendering
            scrolling     = false, -- disable scroll-to-switch (optional, cleaner UX)

            col = {
                active          = "rgba(33ccffee)",
                inactive        = "rgba(444444aa)",
                locked_active   = "rgba(33ccffee)",
                locked_inactive = "rgba(444444aa)",
            },
        },
    },

    -- https://wiki.hypr.land/configuring/core/config-options/#misc
    misc = {
        force_default_wallpaper = 0,     -- 0 = no anime mascot wallpaper (wallpaper-cycle.sh sets ours)
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})
