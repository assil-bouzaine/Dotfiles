-- Input
-- https://wiki.hypr.land/configuring/core/config-options/#input

hl.config({
    input = {
        kb_layout  = "us,ara,fr",
        kb_variant = "",
        kb_model   = "",
        kb_options = "ctrl:nocaps,ctrl:ralt_rctrl,grp:alt_shift_toggle",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification

        touchpad = {
            natural_scroll = false,
        },
    },
})

-- See https://wiki.hypr.land/configuring/core/gestures/
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})
