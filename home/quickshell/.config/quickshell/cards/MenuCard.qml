import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// The Arch menu: the drop-down behind the bar's Arch logo (and SUPER + D).
//
// Modelled on Omarchy 4.5's menu (MIT, github.com/basecamp/omarchy,
// shell/plugins/menu): one short list you drill into, with Omarchy's icons.
// Typing searches every page and every app at once, so it is still the app
// launcher: type a few letters, Enter. Toggle rows flip in place and keep the
// menu open; Log out, Reboot and Shut down want a second press. Rows show
// their keybind on the right, so the menu also teaches them.
//
// Keys: type to search, ↑ ↓ or Tab move, Enter or → open, ← or Backspace
// back, Esc clears the search, then goes back, then closes.
// The switches and the header line come from menuctl.sh, read on open.
//
// Look: "Layered" (picked 2026-11-18 from ~/prototypes/bar-dropdowns): a glass
// card (Hyprland blurs the wallpaper behind the "archmenu" layer, rules.lua),
// quick-toggle tiles on the first page, rows with an icon tile and a second
// line, and a row of power buttons at the bottom. Toggle and System are no
// longer rows on the first page (the tiles and the power row replace them),
// but their entries still turn up when you type.
Scope {
    id: root

    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"
    readonly property string ctl: decodeURIComponent(Qt.resolvedUrl("menuctl.sh").toString().replace("file://", ""))

    readonly property int cardWidth: 360
    readonly property int rowHeight: 40
    readonly property int homeRowHeight: 46     // first-page rows carry their "about" line
    readonly property int resultHeight: 46      // search results carry a second line
    readonly property int sepGap: 9             // hairline between groups
    readonly property int maxResults: 8

    property bool opened: false
    property double closedAt: 0
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    property string page: ""                    // "" is the first page
    property string filterText: ""
    property int selectedIndex: 0
    property bool cursorActive: false           // no row is lit until the keys or the mouse pick one
    property string armed: ""                   // a confirm row waiting for its second press
    property var switches: ({})
    property int uptime: 0
    property string kernel: ""
    property var pending: null                  // what runs once the menu is off the screen

    // Commands run through bash -c, so ~, $(...) and && work.
    readonly property string bar: "~/.config/waybar/scripts/"
    readonly property string cardCmd: "~/.config/quickshell/cards/card "
    readonly property string shot: "mkdir -p ~/Pictures && f=~/Pictures/$(date +%F_%H-%M-%S).png && "

    // The first page's quick-toggle tiles: a switch each, and the theme picker.
    readonly property var tiles: [
        { key: "awake",       icon: 0xEF59,  label: "Stay awake" },
        { key: "nightlight",  icon: 0xF0594, label: "Night light" },
        { key: "dnd",         icon: 0xF009B, label: "Silence" },
        { key: "performance", icon: 0xF04C5, label: "Performance" },
        { key: "floating",    icon: 0xF10AC, label: "Floating" },
        { icon: 0xF0E0C, label: "Theme" }
    ]
    readonly property bool home: root.page === "" && root.filterText === ""
    readonly property var homeHidden: ["toggle", "system"]   // the tiles and the power row stand in for these

    readonly property var pages: ({
        appearance: "Appearance", toggle: "Toggle", capture: "Capture",
        setup: "Setup", learn: "Learn", system: "System"
    })

    // kind: page (opens one) | run | toggle (flips in place) | confirm (run, after a second press)
    // icon: a Nerd Font code point (Omarchy's where it has one). keys: the keybind
    // shown on the right, hint: a word shown there instead. sep: a hairline above.
    // about: the second line in search results (else the page it's on).
    readonly property var entries: [
        { id: "apps",       page: "", kind: "run",  icon: 0xF003B, label: "Apps", about: "Every app on a grid", cmd: cardCmd + "apps", keys: "Super Alt Space", words: "applications programs launcher grid all" },
        { id: "appearance", page: "", kind: "page", icon: 0xF03D8, label: "Appearance", about: "Theme, font, wallpaper, bar", sep: true, words: "style look" },
        { id: "toggle",     page: "", kind: "page", icon: 0xF0521, label: "Toggle", about: "Stay awake, night light, notifications", words: "switches quick settings" },
        { id: "capture",    page: "", kind: "page", icon: 0xF030,  label: "Capture", about: "Screenshots, send to phone", words: "screenshot" },
        { id: "setup",      page: "", kind: "page", icon: 0xE615,  label: "Setup", about: "Wi-Fi, Bluetooth, sound, agents", sep: true, words: "settings" },
        { id: "learn",      page: "", kind: "page", icon: 0xF09D1, label: "Learn", about: "Keybindings and wikis", words: "help docs" },
        { id: "update",     page: "", kind: "run",  icon: 0xF021,  label: "Update", about: "Update every package in a terminal", hint: "yay -Syu", words: "upgrade packages pacman system",
          cmd: "kitty --class=bar-update --title='System update' -e bash -c 'yay -Syu; echo; read -rsn1 -p \"Done. Press any key to close.\"'" },
        { id: "system",     page: "", kind: "page", icon: 0xF011,  label: "System", about: "Lock, suspend, log out, reboot, shut down", sep: true, words: "power" },

        { id: "theme",     page: "appearance", kind: "run", icon: 0xF0E0C, label: "Theme", cmd: cardCmd + "themes", keys: "Super Ctrl T", words: "colors colours" },
        { id: "font",      page: "appearance", kind: "run", icon: 0xE659,  label: "Font", cmd: cardCmd + "fonts", keys: "Super Ctrl F", words: "typeface" },
        { id: "wallpaper", page: "appearance", kind: "run", icon: 0xF03E,  label: "Wallpaper", cmd: "~/.config/quickshell/wallpicker/wallpicker", keys: "Super Ctrl Space", words: "background picture" },
        { id: "topbar",    page: "appearance", kind: "run", icon: 0xF035C, label: "Hide or show the bar", cmd: bar + "bar-toggle.sh", keys: "Super Shift Space", words: "top bar waybar" },

        { id: "awake",       page: "toggle", kind: "toggle", icon: 0xEF59,  label: "Stay awake", key: "awake", cmd: bar + "awake.sh toggle", keys: "Super Ctrl I", words: "idle lock sleep caffeine inhibit" },
        { id: "nightlight",  page: "toggle", kind: "toggle", icon: 0xF0594, label: "Night light", key: "nightlight", cmd: bar + "nightlight.sh toggle", words: "hyprsunset warm blue light" },
        { id: "dnd",         page: "toggle", kind: "toggle", icon: 0xF009B, label: "Silence notifications", key: "dnd", cmd: "swaync-client -d -sw", words: "do not disturb dnd" },
        { id: "performance", page: "toggle", kind: "toggle", icon: 0xF04C5, label: "Performance mode", key: "performance", cmd: bar + "power.sh toggle", words: "power profile fan balanced" },
        { id: "floating",    page: "toggle", kind: "toggle", icon: 0xF10AC, label: "Floating windows", key: "floating", cmd: "~/.config/hypr/scripts/layout-toggle", keys: "Super Alt L", words: "tiling layout workspace dock titlebars" },

        { id: "shot-area",   page: "capture", kind: "run", icon: 0xF0489, label: "Screenshot an area", cmd: shot + "grim -g \"$(slurp)\" \"$f\" && wl-copy < \"$f\"", keys: "Shift Print", words: "region selection" },
        { id: "shot-screen", page: "capture", kind: "run", icon: 0xF0E51, label: "Screenshot the screen", cmd: shot + "grim \"$f\" && wl-copy < \"$f\"", keys: "Print", words: "full" },
        { id: "phone",       page: "capture", kind: "run", icon: 0xF011C, label: "Send clipboard to phone", cmd: "~/.local/bin/tg-drop send --clip --notify", keys: "Super Shift P", words: "telegram share tg-drop" },

        { id: "wifi",      page: "setup", kind: "run", icon: 0xF05A9, label: "Wi-Fi", cmd: cardCmd + "netcard", keys: "Super N", words: "wifi network internet wireless" },
        { id: "bluetooth", page: "setup", kind: "run", icon: 0xF00AF, label: "Bluetooth", cmd: cardCmd + "bluetooth", keys: "Super B", words: "headphones headset devices" },
        { id: "sound",     page: "setup", kind: "run", icon: 0xF057E, label: "Sound", cmd: "pavucontrol", words: "audio volume speakers microphone" },
        { id: "agents",    page: "setup", kind: "run", icon: 0xF06A9, label: "AI agents", cmd: cardCmd + "agents", keys: "Super Ctrl A", words: "claude codex limits usage" },
        { id: "dotfiles",  page: "setup", kind: "run", icon: 0xF107F, label: "Dotfiles", cmd: "code ~/.dotfiles", hint: "VS Code", words: "config configuration editor" },

        { id: "keys",     page: "learn", kind: "run", icon: 0xF11C,  label: "Keybindings", cmd: cardCmd + "keys", keys: "Super K", words: "shortcuts cheat sheet" },
        { id: "hyprwiki", page: "learn", kind: "run", icon: 0xF359,  label: "Hyprland wiki", cmd: "xdg-open https://wiki.hypr.land/", words: "docs" },
        { id: "archwiki", page: "learn", kind: "run", icon: 0xF303,  label: "Arch wiki", cmd: "xdg-open https://wiki.archlinux.org/", words: "docs" },
        { id: "bash",     page: "learn", kind: "run", icon: 0xF1183, label: "Bash cheat sheet", cmd: "xdg-open https://devhints.io/bash", words: "shell scripting" },

        { id: "lock",     page: "system", kind: "run",     icon: 0xF023,  label: "Lock", cmd: "hyprlock", keys: "Super L", words: "screen" },
        { id: "suspend",  page: "system", kind: "run",     icon: 0xF04B2, label: "Suspend", cmd: "systemctl suspend", words: "sleep" },
        { id: "logout",   page: "system", kind: "confirm", icon: 0xF0343, label: "Log out", keys: "Super M", words: "exit quit sign out hyprland",
          cmd: "command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'" },
        { id: "reboot",   page: "system", kind: "confirm", icon: 0xF0709, label: "Reboot", cmd: "systemctl reboot", words: "restart" },
        { id: "shutdown", page: "system", kind: "confirm", icon: 0xF0425, label: "Shut down", cmd: "systemctl poweroff", words: "power off turn off" }
    ]

    // ── rows ─────────────────────────────────────────────────────────────
    // A match at the start of the name beats one at the start of a word,
    // which beats one inside it, which beats one in the extra words.
    function score(name, extra, q) {
        const n = String(name || "").toLowerCase()
        if (n.startsWith(q)) return 100
        if (n.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 80
        if (n.includes(q)) return 60
        return String(extra || "").toLowerCase().includes(q) ? 30 : 0
    }

    function entryRow(e, searching) {
        return { entry: e, app: null, kind: e.kind, icon: e.icon, label: e.label,
                 keys: e.keys || "", hint: e.hint || "", sep: false,
                 detail: e.about || root.pages[e.page] || "" }
    }
    function appRow(a) {
        return { entry: null, app: a, kind: "app", icon: 0, label: a.name, keys: "", hint: "", sep: false,
                 detail: a.genericName || a.comment || "App" }
    }

    // The page's rows, or while searching: every page's rows and every app,
    // best match first (a setting wins a tie with an app).
    readonly property var rows: {
        const q = root.filterText.trim().toLowerCase()
        if (!q) return root.entries.filter(e => e.page === root.page && !(root.page === "" && root.homeHidden.includes(e.id)))
                                   .map(e => root.entryRow(e, false))
        const found = []
        for (const e of root.entries) {
            const s = root.score(e.label, e.words + " " + (root.pages[e.page] || ""), q)
            if (s > 0) found.push({ s: s + 1, row: root.entryRow(e, true) })
        }
        const seen = {}
        for (const a of DesktopEntries.applications.values) {
            if (!a || a.noDisplay || seen[a.id]) continue
            seen[a.id] = true
            const s = root.score(a.name, [a.genericName, a.comment, a.id].concat(a.keywords || []).join(" "), q)
            if (s > 0) found.push({ s: s, row: root.appRow(a) })
        }
        found.sort((x, y) => y.s - x.s || x.row.label.toLowerCase().localeCompare(y.row.label.toLowerCase()))
        return found.slice(0, 40).map(x => x.row)
    }

    readonly property int listHeight: {
        const r = root.rows
        if (!r.length) return 64                  // room for "No matches"
        if (root.filterText) {
            // more than fit: end mid-row, so the cut-off row says there's more
            return r.length > root.maxResults ? Math.round((root.maxResults + 0.5) * root.resultHeight)
                                              : r.length * root.resultHeight
        }
        return r.length * (root.page === "" ? root.homeRowHeight : root.rowHeight)
    }

    function uptimeText() {
        const s = root.uptime
        if (!(s > 0)) return ""
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
        if (d > 0) return "up " + d + (d === 1 ? " day " : " days ") + h + " h"
        if (h > 0) return "up " + h + " h " + m + " min"
        return "up " + m + " min"
    }

    function iconSource(icon) {
        if (!icon) return Quickshell.iconPath("application-x-executable", true)
        if (String(icon).startsWith("/")) return "file://" + icon
        return Quickshell.iconPath(icon, "application-x-executable")
    }

    // ── open / close ─────────────────────────────────────────────────────
    function openOn(name) {
        for (const s of Quickshell.screens) if (s.name === name) root.targetScreen = s
        root.page = ""
        root.filterText = ""
        root.armed = ""
        root.selectedIndex = 0
        root.cursorActive = false
        root.pending = null
        runTimer.stop()
        root.readState()
        root.opened = true
        openAnim.restart()
        Qt.callLater(() => keys.forceActiveFocus())
    }
    function open() { openOn(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") }
    function close() {
        if (!root.opened) return
        root.opened = false
        root.armed = ""
        root.closedAt = Date.now()
    }
    function toggle() {
        if (root.opened) close()
        else if (Date.now() - root.closedAt > 400) open()   // the click that closed it was on the logo
    }

    // ── moving around ────────────────────────────────────────────────────
    function setFilter(text) {
        root.filterText = text
        root.armed = ""
        root.selectedIndex = 0
        root.cursorActive = text.length > 0     // Enter takes the best match
        list.positionViewAtBeginning()
    }
    function move(d) {
        const n = root.rows.length
        if (!n) return
        if (!root.cursorActive) root.selectedIndex = d > 0 ? 0 : n - 1
        else if (Math.abs(d) === 1) root.selectedIndex = ((root.selectedIndex + d) % n + n) % n
        else root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + d))
        root.cursorActive = true
        root.armed = ""
        list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
    function openPage(id, byKeys) {
        root.page = id
        root.filterText = ""
        root.armed = ""
        root.selectedIndex = 0
        root.cursorActive = byKeys
        root.slide(1)
    }
    // One step back: the confirm, the search, then the page. False at the start.
    function back() {
        if (root.armed) { root.armed = ""; return true }
        if (root.filterText) { root.setFilter(""); return true }
        if (!root.page) return false
        const from = root.page
        root.page = ""
        root.selectedIndex = Math.max(0, root.rows.findIndex(r => r.entry && r.entry.id === from))
        root.cursorActive = true
        root.slide(-1)
        return true
    }
    function slide(direction) {
        pageAnim.from = 12 * direction
        pageAnim.restart()
    }

    // ── doing things ─────────────────────────────────────────────────────
    function activate(index, byKeys) {
        const r = root.rows[index]
        if (!r) return
        if (r.app) return root.closeThen({ app: r.app })
        const e = r.entry
        if (e.kind === "page") return root.openPage(e.id, byKeys)
        if (e.kind === "toggle") return root.flip(e)
        root.press(e)
    }
    // Run an entry; Log out, Reboot and Shut down want a second press.
    function press(e) {
        if (e.kind === "confirm" && root.armed !== e.id) {
            root.armed = e.id
            disarm.restart()
            return
        }
        root.closeThen({ cmd: e.cmd })
    }
    function closeThen(what) {
        root.pending = what
        root.close()
        runTimer.restart()
    }
    function flip(e) {
        const next = Object.assign({}, root.switches)
        next[e.key] = !next[e.key]
        root.switches = next                     // the switch moves now, the state is read again after
        Quickshell.execDetached(["bash", "-c", e.cmd])
        stateTimer.restart()
    }
    // Terminal apps get a kitty; DesktopEntry.execute() ignores runInTerminal.
    function launchApp(a) {
        if (a.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(a.command))
        else a.execute()
    }
    function readState() {
        const m = Hyprland.focusedMonitor
        const ws = m && m.activeWorkspace ? String(m.activeWorkspace.id) : ""
        stateProc.command = ["bash", root.ctl, "state", ws]
        if (!stateProc.running) stateProc.running = true
    }

    Timer {
        id: runTimer
        interval: 220     // the menu leaves the screen and the keyboard first (screenshots, other cards)
        onTriggered: {
            const p = root.pending
            root.pending = null
            if (!p) return
            if (p.app) root.launchApp(p.app)
            else Quickshell.execDetached(["bash", "-c", p.cmd])
        }
    }
    Timer { id: disarm; interval: 4000; onTriggered: root.armed = "" }
    Timer { id: stateTimer; interval: 1800; onTriggered: root.readState() }   // the night light fades for ~1.5 s

    Process {
        id: stateProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.switches = d
                    root.uptime = d.uptime || 0
                    root.kernel = d.kernel || ""
                } catch (e) {
                    console.warn("MenuCard: can't read menuctl.sh state:", e)
                }
            }
        }
    }

    IpcHandler {
        target: "menu"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function openOn(screen: string): void { root.openOn(screen) }   // tests
        function filter(text: string): void { root.setFilter(text) }   // tests
        function nav(d: int): void { root.move(d) }                    // tests
        function enter(): void { root.activate(root.selectedIndex, true) }   // tests
        function back(): void { if (!root.back()) root.close() }       // tests
    }

    // ── parts ────────────────────────────────────────────────────────────
    component Label: Text {
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: 13
        elide: Text.ElideRight
        textFormat: Text.PlainText
    }

    // ── the card ─────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.opened
        screen: root.targetScreen
        anchors { top: true; left: true }
        margins { top: 42; left: 6 }            // under the bar's left island
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: root.cardWidth
        implicitHeight: card.height
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "archmenu"
        WlrLayershell.keyboardFocus: root.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        HyprlandFocusGrab {
            active: win.visible && !root.testMode
            windows: [win]
            onCleared: root.close()
        }

        Rectangle {
            id: card
            width: parent.width
            height: body.height + 28
            radius: 18
            color: Theme.alpha(Theme.bg, 0.80)     // glass: rules.lua blurs the wallpaper behind "archmenu"
            border.width: 1
            border.color: Theme.alpha(Theme.fg, 0.09)
            transform: Scale { id: grow; origin.x: 0; origin.y: 0 }   // grows out of the logo's corner

            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
                NumberAnimation { target: grow; properties: "xScale,yScale"; from: 0.95; to: 1; duration: 220
                                  easing.type: Easing.Bezier; easing.bezierCurve: [0.23, 1, 0.32, 1, 1, 1] }
            }

            Item {
                id: keys
                focus: true
                Keys.onPressed: event => {
                    const k = event.key
                    const typed = event.text && !/[\x00-\x1f\x7f]/.test(event.text)
                        && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                    if (k === Qt.Key_Escape) {
                        if (!root.back()) root.close()
                    } else if (k === Qt.Key_Backspace) {
                        if (root.filterText) root.setFilter(Array.from(root.filterText).slice(0, -1).join(""))
                        else root.back()
                    } else if (k === Qt.Key_Left) {
                        if (!root.filterText) root.back()
                    } else if (k === Qt.Key_Up || k === Qt.Key_Backtab) {
                        root.move(-1)
                    } else if (k === Qt.Key_Down || k === Qt.Key_Tab) {
                        root.move(1)
                    } else if (k === Qt.Key_PageUp) {
                        root.move(-5)
                    } else if (k === Qt.Key_PageDown) {
                        root.move(5)
                    } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right
                               || (k === Qt.Key_Space && !root.filterText)) {
                        if (!root.cursorActive) root.move(1)   // first Enter only lights a row
                        else root.activate(root.selectedIndex, true)
                    } else if (typed) {
                        root.setFilter(root.filterText + event.text)
                    } else {
                        return
                    }
                    event.accepted = true
                }
            }

            Column {
                id: body
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 12

                // header: the logo you clicked, uptime and kernel
                Item {
                    width: parent.width
                    height: 36
                    Rectangle {
                        id: logo
                        x: 2
                        width: 36
                        height: 36
                        radius: 11
                        color: Theme.alpha(Theme.accent, 0.12)
                        Text {
                            anchors.centerIn: parent
                            text: String.fromCodePoint(0xF303)
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: 19
                        }
                    }
                    Column {
                        anchors.left: logo.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Label {
                            width: parent.width
                            text: "Arch Linux"
                            color: Theme.fgBright
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                        Label {
                            width: parent.width
                            text: [root.uptimeText(), root.kernel ? "linux " + root.kernel.split("-")[0] : ""].filter(s => s).join("  ·  ")
                            color: Theme.muted
                            font.pixelSize: 11
                        }
                    }
                }

                // quick toggles: flip in place; the last tile opens the theme picker
                Grid {
                    id: tileGrid
                    visible: root.home
                    width: parent.width
                    columns: 3
                    spacing: 8
                    readonly property real cell: (width - 2 * spacing) / 3

                    Repeater {
                        model: root.tiles
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            readonly property bool isToggle: !!modelData.key
                            readonly property bool on: isToggle && !!root.switches[modelData.key]
                            width: tileGrid.cell
                            height: 66
                            radius: 13
                            color: on ? Theme.alpha(Theme.accent, tileHit.containsMouse ? 0.23 : 0.18)
                                      : Theme.alpha(Theme.fg, tileHit.containsMouse ? 0.09 : 0.06)
                            scale: tileHit.pressed ? 0.97 : 1
                            Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                            Text {
                                x: 11
                                y: 10
                                text: String.fromCodePoint(tile.modelData.icon)
                                color: tile.on ? Theme.accent : Theme.muted
                                font.family: Theme.font
                                font.pixelSize: 16
                                Behavior on color { ColorAnimation { duration: 160 } }
                            }
                            Column {
                                x: 11
                                width: parent.width - 22
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 9
                                spacing: 1
                                Label {
                                    width: parent.width
                                    text: tile.modelData.label
                                    color: tile.on ? Theme.fgBright : Theme.fg
                                    font.pixelSize: 11
                                }
                                Label {
                                    width: parent.width
                                    text: tile.isToggle ? (tile.on ? "On" : "Off") : Theme.title
                                    color: tile.on ? Theme.accent : Theme.faint
                                    font.pixelSize: 10
                                }
                            }
                            MouseArea {
                                id: tileHit
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (tile.isToggle) root.flip(root.entries.find(e => e.key === tile.modelData.key))
                                    else root.closeThen({ cmd: root.cardCmd + "themes" })
                                }
                            }
                        }
                    }
                }

                // search line (the keys go to `keys`; this only shows them)
                Rectangle {
                    width: parent.width
                    height: 38
                    radius: 11
                    color: Theme.field
                    border.width: 1
                    border.color: root.filterText ? Theme.alpha(Theme.accent, 0.5) : "transparent"
                    Text {
                        id: glass
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: String.fromCodePoint(0xF0349)
                        color: root.filterText ? Theme.accent : Theme.faint
                        font.family: Theme.font
                        font.pixelSize: 16
                    }
                    Label {
                        id: typed
                        anchors.left: glass.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - x - 20)
                        text: root.filterText
                        elide: Text.ElideLeft
                    }
                    Rectangle {
                        id: caret
                        anchors.left: typed.right
                        anchors.leftMargin: root.filterText ? 1 : 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 16
                        radius: 1
                        color: Theme.accent
                        SequentialAnimation on opacity {
                            running: root.opened
                            loops: Animation.Infinite
                            NumberAnimation { to: 1; duration: 0 }
                            PauseAnimation { duration: 530 }
                            NumberAnimation { to: 0; duration: 0 }
                            PauseAnimation { duration: 530 }
                        }
                    }
                    Label {
                        anchors.left: caret.right
                        anchors.leftMargin: 4
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.filterText
                        text: "Search apps and settings"
                        color: Theme.faint
                    }
                }

                // where you are: ‹ PAGE (click to go back), or the results
                Item {
                    visible: root.page !== "" || root.filterText !== ""
                    width: parent.width
                    height: 14
                    Text {
                        x: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.filterText ? (root.rows.length ? "RESULTS" : "")
                                              : "‹  " + (root.pages[root.page] || "").toUpperCase()
                        color: crumbHit.containsMouse && !root.filterText ? Theme.fg : Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 0.9
                        MouseArea {
                            id: crumbHit
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            enabled: !root.filterText
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.back()
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: root.listHeight

                    ListView {
                        id: list
                        anchors.fill: parent
                        model: root.rows
                        clip: true
                        interactive: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        transform: Translate { id: shift }

                        ParallelAnimation {
                            id: pageAnim
                            property real from: 12
                            NumberAnimation { target: list; property: "opacity"; from: 0.25; to: 1; duration: 150 }
                            NumberAnimation { target: shift; property: "x"; from: pageAnim.from; to: 0; duration: 180; easing.type: Easing.OutCubic }
                        }

                        delegate: Item {
                            id: slot
                            required property var modelData
                            required property int index
                            readonly property bool searching: root.filterText !== ""
                            readonly property bool withDetail: searching || root.page === ""
                            readonly property bool gap: !searching && modelData.sep && index > 0
                            readonly property bool lit: root.cursorActive && index === root.selectedIndex
                            readonly property bool isArmed: !!modelData.entry && root.armed === modelData.entry.id
                            readonly property bool isToggle: modelData.kind === "toggle"
                            readonly property bool on: isToggle && !!root.switches[modelData.entry.key]
                            width: list.width
                            height: (searching ? root.resultHeight : root.page === "" ? root.homeRowHeight : root.rowHeight)
                                    + (gap ? root.sepGap : 0)

                            Rectangle {
                                visible: slot.gap
                                x: 10
                                y: Math.floor(root.sepGap / 2)
                                width: parent.width - 20
                                height: 1
                                color: Theme.rule
                            }

                            Rectangle {
                                id: row
                                y: slot.gap ? root.sepGap : 0
                                width: parent.width
                                height: slot.height - y
                                radius: 11
                                color: slot.isArmed ? Theme.alpha(Theme.red, 0.10) : slot.lit ? Theme.alpha(Theme.fg, 0.07) : "transparent"

                                // the icon sits on its own small tile
                                Rectangle {
                                    id: iconTile
                                    x: 8
                                    width: 30
                                    height: 30
                                    radius: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: slot.isArmed ? Theme.red
                                         : slot.lit ? Theme.alpha(Theme.accent, 0.16)
                                         : Theme.alpha(Theme.fg, 0.07)
                                }
                                Text {
                                    visible: !slot.modelData.app
                                    anchors.centerIn: iconTile
                                    text: slot.modelData.icon ? String.fromCodePoint(slot.modelData.icon) : ""
                                    color: slot.isArmed ? Theme.onAccent : slot.lit ? Theme.accent : slot.on ? Theme.fgBright : Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                }
                                Image {
                                    visible: !!slot.modelData.app
                                    width: 18
                                    height: 18
                                    anchors.centerIn: iconTile
                                    source: slot.modelData.app ? root.iconSource(slot.modelData.app.icon) : ""
                                    sourceSize: Qt.size(40, 40)
                                    fillMode: Image.PreserveAspectFit
                                    // Not asynchronous: after a Quickshell hot reload async loads
                                    // through the icon provider come back blank (see AppGrid.qml).
                                    asynchronous: false
                                    smooth: true
                                    mipmap: true
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 50
                                    anchors.right: trail.left
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Label {
                                        width: parent.width
                                        text: slot.isArmed ? slot.modelData.label + "?" : slot.modelData.label
                                        color: slot.isArmed ? Theme.red : slot.lit ? Theme.fgBright : Theme.fg
                                        font.weight: Font.Medium
                                    }
                                    Label {
                                        visible: slot.withDetail && slot.modelData.detail !== ""
                                        width: parent.width
                                        text: slot.modelData.detail
                                        color: Theme.muted
                                        font.pixelSize: 11
                                    }
                                }

                                // right side: the keybind (or a hint), a switch, a chevron
                                Row {
                                    id: trail
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10
                                    Label {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: slot.isArmed || slot.modelData.keys !== "" || slot.modelData.hint !== ""
                                        text: slot.isArmed ? "press again" : (slot.modelData.keys || slot.modelData.hint)
                                        color: slot.isArmed ? Theme.red : Theme.faint
                                        font.pixelSize: 11
                                    }
                                    Rectangle {
                                        id: sw
                                        visible: slot.isToggle
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 34
                                        height: 20
                                        radius: 10
                                        color: slot.on ? Theme.accent : Theme.lift
                                        border.width: slot.on ? 0 : 1
                                        border.color: Theme.alpha(Theme.fg, 0.13)
                                        Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        Rectangle {
                                            width: 14
                                            height: 14
                                            radius: 7
                                            y: 3
                                            x: slot.on ? sw.width - width - 3 : 3
                                            color: slot.on ? Theme.onAccent : Theme.fg
                                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                    Text {
                                        visible: slot.modelData.kind === "page"
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String.fromCodePoint(0xF0142)
                                        color: slot.lit ? Theme.fg : Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 14
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: {
                                        root.selectedIndex = slot.index
                                        root.cursorActive = true
                                        if (!slot.isArmed) root.armed = ""
                                    }
                                    onClicked: root.activate(slot.index, false)
                                }
                            }
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        width: parent.width - 24
                        visible: root.rows.length === 0
                        text: "No apps or settings match “" + root.filterText + "”"
                        color: Theme.muted
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // power: Lock and Suspend run at once; Log out, Reboot and Shut down
                // turn red and ask "Again?" first (the same armed state as the rows)
                Item {
                    id: powerRow
                    visible: root.home
                    width: parent.width
                    height: 76
                    readonly property var items: root.entries.filter(e => e.page === "system")

                    Rectangle { width: parent.width; height: 1; color: Theme.rule }
                    Row {
                        y: 13
                        x: 2
                        width: parent.width - 4
                        spacing: (width - powerRow.items.length * 60) / Math.max(1, powerRow.items.length - 1)
                        Repeater {
                            model: powerRow.items
                            delegate: Item {
                                id: pw
                                required property var modelData
                                readonly property bool isArmed: root.armed === modelData.id
                                width: 60
                                height: 62
                                Rectangle {
                                    id: circle
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 40
                                    height: 40
                                    radius: 20
                                    color: pw.isArmed ? Theme.red : Theme.alpha(Theme.fg, pwHit.containsMouse ? 0.12 : 0.07)
                                    scale: pwHit.pressed ? 0.95 : 1
                                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: String.fromCodePoint(pw.modelData.icon)
                                        color: pw.isArmed ? Theme.onAccent : pwHit.containsMouse ? Theme.fgBright : Theme.fg
                                        font.family: Theme.font
                                        font.pixelSize: 16
                                    }
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.bottom: parent.bottom
                                    text: pw.isArmed ? "Again?" : pw.modelData.label
                                    color: pw.isArmed ? Theme.red : Theme.muted
                                    font.pixelSize: 10
                                    elide: Text.ElideNone
                                }
                                MouseArea {
                                    id: pwHit
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.press(pw.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
