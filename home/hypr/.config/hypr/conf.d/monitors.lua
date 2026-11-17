-- Monitors
-- See https://wiki.hypr.land/configuring/core/monitors/

hl.monitor({
    output   = "",
    mode     = "preferred", -- unknown screens (TV, projector) use their native mode
    position = "auto",
    scale    = "auto",
})

-- Laptop panel on the left
hl.monitor({
    output   = "eDP-1",
    mode     = "1366x768@60",
    position = "0x0",
    scale    = "1",
})

-- MSI MAG 255F E20 on the right (120Hz is the max it exposes over HDMI)
hl.monitor({
    output   = "HDMI-A-1",
    mode     = "1920x1080@120",
    position = "1366x0",
    scale    = "1",
})
