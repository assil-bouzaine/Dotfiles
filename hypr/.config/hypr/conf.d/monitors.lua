-- Monitors
-- See https://wiki.hypr.land/configuring/core/monitors/

hl.monitor({
    output   = "",
    mode     = "1366x768@60",
    position = "auto",
    scale    = "auto",
})

-- Check monitors using `hyprctl monitors`, then u can configure the 2nd monitor
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "1366x768@60",
    position = "1366x0",
    scale    = "1",
})
