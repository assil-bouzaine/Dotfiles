// Agents card: the drop-down behind the bar's robot icon (SUPER + CTRL + A).
//
// Laid out like Omarchy 4.5's agents panel (MIT, github.com/basecamp/omarchy,
// shell/plugins/agents): a hero with the robot and a line that rotates through
// this week's token counts, one section per subscription (mark, name, plan, a
// meter per limit window with the time until it resets, exact % on hover),
// and "make something cool" starters that open an agent on a task. Agents
// start in a new window of the tmux session "main", in ~ (agentsctl.py launch).
// Data from agentsctl.py; marks in assets/ are Omarchy's.
//
// Keys: j/k h/l move, Enter select, r refresh, Esc close.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    readonly property string ctl: decodeURIComponent(Qt.resolvedUrl("agentsctl.py").toString().replace("file://", ""))
    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"

    property bool opened: false
    property double closedAt: 0
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    property var agents: []
    property double fetchedAt: 0
    property var stats: null
    property bool loading: false
    property int heroIndex: 0
    property double now: Date.now() / 1000

    property string cursor: ""
    property bool cursorActive: false
    property string toastText: ""

    readonly property var starters: [
        { glyph: "󰕮", label: "Bar widget", prompt: "Add a new widget to my Waybar bar (~/.dotfiles/home/waybar). Ask me what it should show, then build it in the same ink-island style as the rest of the bar and reload it." },
        { glyph: "󰐱", label: "Card", prompt: "Make me a new Quickshell drop-down card like the network and agents cards in ~/.dotfiles/home/quickshell/.config/quickshell/cards. Ask me what it should do, then build it, add a bar icon or keybind, and test it on a headless output." },
        { glyph: "󰣆", label: "App", prompt: "Make me a small desktop app for my Hyprland setup. Ask me what it should do, then build it and add a .desktop entry so it shows up in the rofi launcher." }
    ]

    // ── helpers ──────────────────────────────────────────────────────────
    function tokens(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e4) return Math.round(n / 1e3) + "k"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "k"
        return String(n)
    }

    function duration(secs) {
        if (secs <= 0) return "now"
        const d = Math.floor(secs / 86400), h = Math.floor(secs % 86400 / 3600), m = Math.floor(secs % 3600 / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return Math.max(1, m) + "m"
    }

    readonly property var heroLines: {
        const s = stats
        if (!s) return ["Counting tokens…"]
        const l = []
        l.push(tokens(s.week_tokens) + " tokens this week")
        l.push(tokens(s.today_tokens) + " tokens today")
        if (s.top_model) l.push("Mostly " + s.top_model)
        if (s.busiest_day) l.push("Busiest day: " + s.busiest_day)
        l.push(s.prompts_today + (s.prompts_today === 1 ? " prompt today" : " prompts today"))
        l.push(s.sessions_today + (s.sessions_today === 1 ? " session today" : " sessions today"))
        return l
    }

    function meterColor(p) {
        return p >= 100 ? Theme.red : p >= 80 ? Theme.yellow : Theme.cyan
    }

    function run(args, done) {
        const p = oneShot.createObject(root, { command: [ctl].concat(args), done: done || null })
        p.running = true
    }

    function refresh(force) {
        loading = true
        run(force ? ["limits", "--refresh"] : ["limits"], text => {
            loading = false
            try {
                const d = JSON.parse(text)
                agents = d.agents || []
                fetchedAt = d.fetched_at || 0
            } catch (e) {}
            Quickshell.execDetached(["pkill", "-RTMIN+12", "-x", "waybar"])   // robot icon colour
        })
        run(["stats"], text => { try { stats = JSON.parse(text) } catch (e) {} })
    }

    function toast(t) { toastText = t; toastTimer.restart() }

    // ── open / close ─────────────────────────────────────────────────────
    function openOn(name) {
        for (const s of Quickshell.screens) if (s.name === name) targetScreen = s
        cursorActive = false
        cursor = ""
        heroIndex = 0
        now = Date.now() / 1000
        opened = true
        openAnim.restart()
        refresh(false)
        Qt.callLater(() => keys.forceActiveFocus())
    }
    function open() { openOn(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") }
    function close() {
        if (!opened) return
        opened = false
        closedAt = Date.now()
    }
    function toggle() {
        if (opened) close()
        else if (Date.now() - closedAt > 400) open()   // the bar click that cleared the grab meant "close"
    }

    // ── actions + cursor ─────────────────────────────────────────────────
    function activate(id) {
        if (!id) return
        const [what, arg] = id.split(":")
        if (what === "refresh") { refresh(true); toast("Checking limits…") }
        else if (what === "start") { run(["launch", "claude"]); close() }
        else if (what === "login") { run(["login", arg]); close() }
        else if (what === "starter") { run(["launch", "claude", starters[Number(arg)].prompt]); close() }
    }

    function isHot(id) { return cursorActive && cursor === id }
    function hover(id) { cursor = id; cursorActive = true }

    function focusRows() {
        const rows = [["refresh", "start"]]
        for (const a of agents) if (a.error && a.auth_error) rows.push(["login:" + a.id])
        rows.push(starters.map((s, i) => "starter:" + i))
        return rows
    }

    function move(dr, dc) {
        const rows = focusRows()
        let ri = -1, ci = 0
        for (let i = 0; i < rows.length && ri < 0; i++) {
            const j = rows[i].indexOf(cursor)
            if (j >= 0) { ri = i; ci = j }
        }
        if (ri < 0 || !cursorActive) { cursorActive = true; cursor = rows[rows.length - 1][0]; return }
        ri = Math.max(0, Math.min(rows.length - 1, ri + dr))
        ci = dr !== 0 ? Math.min(ci, rows[ri].length - 1) : Math.max(0, Math.min(rows[ri].length - 1, ci + dc))
        cursor = rows[ri][ci]
    }

    function hint(id) {
        if (!cursorActive || !id) return "j k move   h l switch   Enter select   r refresh   Esc close"
        const [what, arg] = id.split(":")
        if (what === "refresh") return "Check the limits again"
        if (what === "start") return "Start Claude Code in a new tmux window"
        if (what === "login") return "Sign in again"
        if (what === "starter") return "Start Claude Code on: " + starters[Number(arg)].label.toLowerCase()
        return ""
    }

    // ── processes / timers ───────────────────────────────────────────────
    Component {
        id: oneShot
        Process {
            id: p
            property var done: null
            stdout: StdioCollector { onStreamFinished: { if (p.done) p.done(text); p.destroy() } }
        }
    }

    Timer { interval: 3500; repeat: true; running: root.opened; onTriggered: { heroFade.restart() } }
    Timer { interval: 60000; repeat: true; running: root.opened; onTriggered: root.refresh(false) }
    Timer { interval: 15000; repeat: true; running: root.opened; triggeredOnStart: true; onTriggered: root.now = Date.now() / 1000 }
    Timer { id: toastTimer; interval: 2200; onTriggered: root.toastText = "" }

    IpcHandler {
        target: "agents"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function openOn(screen: string): void { root.openOn(screen) }
        function nav(rows: int, cols: int): void { root.move(rows, cols) }
    }

    // ── parts ────────────────────────────────────────────────────────────
    component Label: Text {
        color: Theme.fg
        font.family: Theme.sans
        font.pixelSize: 13
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
        elide: Text.ElideRight
    }

    component Icon: Text {
        color: Theme.fg
        font.family: Theme.icons
        font.pixelSize: 16
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    component SectionTitle: Text {
        color: Theme.muted
        font.family: Theme.sans
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.9
    }

    component Hit: MouseArea {
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
    }

    component IconButton: Rectangle {
        id: ib
        property string glyph
        property bool hot: false
        property bool spinning: false
        signal hovered()
        signal activated()
        implicitWidth: 32
        implicitHeight: 32
        radius: 10
        color: hot ? Theme.lift : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
        Icon {
            id: glyphText
            anchors.centerIn: parent
            text: ib.glyph
            RotationAnimation on rotation { running: ib.spinning; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
            rotation: 0
        }
        Hit { anchors.fill: parent; onEntered: ib.hovered(); onClicked: ib.activated() }
    }

    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.rule
    }

    // One limit window: label, meter, time to reset (exact % while hovered).
    component WindowRow: Item {
        id: wr
        property var win
        property double now
        readonly property double pct: win ? Math.min(100, win.percent) : 0
        implicitHeight: 26
        HoverHandler { id: wrHover }
        RowLayout {
            anchors.fill: parent
            spacing: 12
            Label {
                Layout.preferredWidth: 58
                text: wr.win ? wr.win.label : ""
                color: Theme.muted
                font.pixelSize: 12
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 6
                radius: 3
                color: Theme.lift
                Rectangle {
                    height: parent.height
                    radius: 3
                    width: Math.max(wr.pct > 0 ? 6 : 0, parent.width * wr.pct / 100)
                    color: root.meterColor(wr.pct)
                    gradient: wr.pct < 80 ? meterGradient : null
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    Gradient {
                        id: meterGradient
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Theme.cyan }
                        GradientStop { position: 1; color: Theme.accent2 }
                    }
                }
            }
            Label {
                Layout.preferredWidth: 104
                horizontalAlignment: Text.AlignRight
                font.pixelSize: 12
                color: wrHover.hovered ? Theme.fg : (wr.pct >= 100 ? Theme.red : Theme.faint)
                text: !wr.win ? "" : wrHover.hovered ? Math.round(wr.win.percent) + "% used"
                    : wr.win.resets_at ? (wr.pct >= 100 ? "back in " : "resets in ") + root.duration(wr.win.resets_at - wr.now)
                    : Math.round(wr.win.percent) + "% used"
            }
        }
    }

    // ── the card ─────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.opened
        screen: root.targetScreen
        anchors { top: true; right: true }
        margins { top: 42; right: 6 }
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 404
        implicitHeight: card.height
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "agentscard"
        WlrLayershell.keyboardFocus: root.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        HyprlandFocusGrab {
            active: win.visible && !root.testMode
            windows: [win]
            onCleared: root.close()
        }

        Rectangle {
            id: card
            width: parent.width
            height: body.implicitHeight + 28
            radius: 16
            color: Theme.ink
            border.width: 1
            border.color: Theme.edge
            transform: Translate { id: slide }

            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 130 }
                NumberAnimation { target: slide; property: "y"; from: -8; to: 0; duration: 170; easing.type: Easing.OutCubic }
            }

            Item {
                id: keys
                focus: true
                Keys.onPressed: e => {
                    const k = e.key
                    if (k === Qt.Key_Escape) root.close()
                    else if (k === Qt.Key_J || k === Qt.Key_Down || k === Qt.Key_Tab) root.move(1, 0)
                    else if (k === Qt.Key_K || k === Qt.Key_Up || k === Qt.Key_Backtab) root.move(-1, 0)
                    else if (k === Qt.Key_H || k === Qt.Key_Left) root.move(0, -1)
                    else if (k === Qt.Key_L || k === Qt.Key_Right) root.move(0, 1)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                        if (!root.cursorActive) root.move(0, 0)
                        else root.activate(root.cursor)
                    }
                    else if (k === Qt.Key_R) root.activate("refresh")
                    else return
                    e.accepted = true
                }
            }

            ColumnLayout {
                id: body
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 12

                // hero
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 13
                        color: Theme.cyanSoft
                        Icon { anchors.centerIn: parent; text: "󰚩"; font.pixelSize: 22; color: Theme.cyan }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Label { text: "Agents"; font.pixelSize: 15; font.weight: Font.Bold }
                        Label {
                            id: heroLine
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: Theme.muted
                            text: root.heroLines[root.heroIndex % root.heroLines.length]
                            SequentialAnimation {
                                id: heroFade
                                NumberAnimation { target: heroLine; property: "opacity"; to: 0; duration: 180 }
                                ScriptAction { script: root.heroIndex++ }
                                NumberAnimation { target: heroLine; property: "opacity"; to: 1; duration: 220 }
                            }
                        }
                    }
                    IconButton {
                        glyph: "󰑐"
                        spinning: root.loading
                        hot: root.isHot("refresh")
                        onHovered: root.hover("refresh")
                        onActivated: root.activate("refresh")
                    }
                    IconButton {
                        glyph: "󰞷"
                        hot: root.isHot("start")
                        onHovered: root.hover("start")
                        onActivated: root.activate("start")
                    }
                }

                Rule {}

                SectionTitle { text: "SUBSCRIPTIONS" }

                Label {
                    visible: root.agents.length === 0
                    color: Theme.faint
                    font.pixelSize: 12
                    text: root.loading ? "Checking limits…" : "No Claude Code or Codex sign-in found"
                }

                Repeater {
                    model: root.agents
                    delegate: ColumnLayout {
                        id: agentBox
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.topMargin: index > 0 ? 4 : 0
                        spacing: 4
                        readonly property bool stale: !!modelData.error && modelData.windows.length > 0

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            Image {
                                Layout.preferredWidth: 20
                                Layout.preferredHeight: 20
                                source: Qt.resolvedUrl("assets/" + agentBox.modelData.id + ".svg")
                                sourceSize: Qt.size(40, 40)
                                fillMode: Image.PreserveAspectFit
                            }
                            Label { text: agentBox.modelData.name; font.weight: Font.Bold }
                            Label {
                                visible: !!agentBox.modelData.plan
                                text: agentBox.modelData.plan
                                color: Theme.muted
                                font.pixelSize: 12
                            }
                            Item { Layout.fillWidth: true }
                            // trouble: sign-in link, or a note that the numbers are old
                            Label {
                                visible: !!agentBox.modelData.error
                                font.pixelSize: 12
                                color: agentBox.modelData.auth_error ? (root.isHot("login:" + agentBox.modelData.id) ? Theme.fg : Theme.yellow) : Theme.faint
                                font.underline: !!agentBox.modelData.auth_error
                                text: agentBox.modelData.auth_error ? "Sign-in required"
                                    : agentBox.stale ? "󰋼 Last known" : "Limits unavailable"
                                Hit {
                                    anchors.fill: parent
                                    enabled: !!agentBox.modelData.auth_error
                                    onEntered: root.hover("login:" + agentBox.modelData.id)
                                    onClicked: root.activate("login:" + agentBox.modelData.id)
                                }
                            }
                        }

                        Repeater {
                            model: agentBox.modelData.windows
                            WindowRow {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.leftMargin: 30
                                win: modelData
                                now: root.now
                                opacity: agentBox.stale ? 0.55 : 1
                            }
                        }
                    }
                }

                Rule {}

                SectionTitle { text: "MAKE SOMETHING COOL" }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: root.starters
                        Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool hot: root.isHot("starter:" + index)
                            Layout.fillWidth: true
                            implicitHeight: 66
                            radius: 12
                            color: hot ? Theme.cyanSoft : Theme.field
                            border.width: 1
                            border.color: hot ? Theme.alpha(Theme.accent, 0.4) : "transparent"
                            Behavior on color { ColorAnimation { duration: 110 } }
                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Icon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.glyph
                                    font.pixelSize: 20
                                    color: tile.hot ? Theme.cyan : Theme.fg
                                }
                                Label {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: tile.modelData.label
                                    font.pixelSize: 12
                                    color: tile.hot ? Theme.fg : Theme.muted
                                }
                            }
                            Hit {
                                anchors.fill: parent
                                onEntered: root.hover("starter:" + tile.index)
                                onClicked: root.activate("starter:" + tile.index)
                            }
                        }
                    }
                }

                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: -2
                    font.pixelSize: 11
                    color: root.toastText ? Theme.cyan : Theme.faint
                    text: root.toastText ? root.toastText
                        : root.cursorActive ? root.hint(root.cursor)
                        : root.fetchedAt ? "Updated " + root.duration(root.now - root.fetchedAt).replace("now", "just now") + (root.now - root.fetchedAt >= 60 ? " ago" : "") + "   ·   r refresh   Esc close"
                        : root.hint("")
                }
            }
        }
    }
}
