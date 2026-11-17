pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colours and font of the current theme, shared by the cards, the dock, the
// pickers and the wallpaper picker (wallpicker/Theme.qml links here).
// ~/.local/state/theme/theme.json is written by ~/.local/bin/theme and watched,
// so switching theme (SUPER + CTRL + T) or font (SUPER + CTRL + F) restyles
// everything live. QML colours are #AARRGGBB.
Singleton {
    id: root

    property var c: ({})
    property string font: "JetBrainsMono Nerd Font"
    property string name: "tokyo-night"
    property string title: "Tokyo Night"

    function pick(key, fallback) { return root.c[key] !== undefined ? root.c[key] : fallback }
    function alpha(color, a) { return Qt.rgba(color.r, color.g, color.b, a) }

    // Palette (Tokyo Night until the file has been read)
    readonly property color bg:        pick("background", "#1a1b26")
    readonly property color bgDark:    pick("dark_background", "#13141c")
    readonly property color surface:   pick("lighter_background", "#24283b")
    readonly property color fg:        pick("foreground", "#a9b1d6")
    readonly property color fgBright:  pick("bright_foreground", "#c0caf5")
    readonly property color muted:     pick("text_muted", "#737893")
    readonly property color faint:     pick("text_faint", "#4d5165")
    readonly property color accent:    pick("accent", "#7aa2f7")
    readonly property color accent2:   pick("accent2", "#bb9af7")
    readonly property color onAccent:  pick("on_accent", "#0e0e14")
    readonly property color yellow:    pick("yellow", "#e0af68")
    readonly property color red:       pick("red", "#f7768e")
    readonly property color green:     pick("green", "#9ece6a")   // "on" / connected / success

    // Panels: ink fill, hairline edge, raised rows
    readonly property color ink:   alpha(bg, 0.97)
    readonly property color edge:  alpha(fg, 0.11)
    readonly property color rule:  alpha(fg, 0.08)
    readonly property color field: alpha(fg, 0.06)
    readonly property color lift:  alpha(fg, 0.09)

    // The cards were written with cyan as the accent.
    readonly property color cyan:       accent
    readonly property color cyanSoft:   alpha(accent, 0.15)
    readonly property color greenSoft:  alpha(green, 0.15)
    readonly property color yellowSoft: alpha(yellow, 0.14)

    readonly property string sans: font
    readonly property string icons: font

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/theme/theme.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.c = d.colors || {}
                if (d.font) root.font = d.font
                if (d.name) root.name = d.name
                if (d.title) root.title = d.title
            } catch (e) {
                console.warn("Theme: can't read theme.json:", e)
            }
        }
    }
}
