// Agents card: the drop-down behind the bar's robot icon (SUPER + CTRL + A).
//
// Modelled on Omarchy 4.5's agents panel (MIT, github.com/omacom/omarchy,
// shell/plugins/agents), extended for Claude Code, Codex, Antigravity (agy),
// OpenCode, and Pi:
//   - Hero with rotating token / activity summary across all detected CLIs
//   - One row per auto-detected agent: brand mark, name, plan/provider, live
//     tmux session badge (click to jump straight to its window), quota meters
//     (with reset countdown, scoped 3P ticks, and exact % on hover) or 7-day
//     activity sparkline, and a per-agent terminal launcher (󰞷).
//
// Keys: j/k move, h/l switch row action, 1-5 jump/launch agent, Enter select,
//       r refresh, Esc close.

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

    readonly property int liveTotal: {
        let n = 0
        for (const a of agents) {
            const lv = liveFor(a)
            if (lv) n += lv.count || 1
        }
        return n
    }

    // ── helpers ──────────────────────────────────────────────────────────
    function tokens(n) {
        if (n >= 1e9) return (n / 1e9).toFixed(1) + "B"
        if (n >= 1e6) return (n / 1e6).toFixed(1) + "M"
        if (n >= 1e4) return Math.round(n / 1e3) + "k"
        if (n >= 1e3) return (n / 1e3).toFixed(1) + "k"
        return String(n || 0)
    }

    function duration(secs) {
        if (secs <= 0) return "now"
        const d = Math.floor(secs / 86400), h = Math.floor(secs % 86400 / 3600), m = Math.floor(secs % 3600 / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return Math.max(1, m) + "m"
    }

    function usageFor(agentId) {
        return (stats && stats.per_agent && stats.per_agent[agentId]) ? stats.per_agent[agentId] : null
    }

    function liveFor(agent) {
        if (!agent) return null
        if (stats && stats.live && stats.live[agent.id]) return stats.live[agent.id]
        return agent.live || null
    }

    readonly property var heroLines: {
        const s = stats
        if (!s) return ["Scanning agents…"]
        const l = []
        if (liveTotal > 0) l.push(liveTotal + (liveTotal === 1 ? " agent active right now" : " agents active right now"))
        if (s.week_tokens > 0) l.push(tokens(s.week_tokens) + " tokens this week")
        if (s.today_tokens > 0) l.push(tokens(s.today_tokens) + " tokens today")
        if (s.top_model) l.push("Mostly " + s.top_model)
        if (s.busiest_day) l.push("Busiest day: " + s.busiest_day)
        if (s.prompts_today > 0) l.push(s.prompts_today + (s.prompts_today === 1 ? " prompt today" : " prompts today"))
        if (s.sessions_today > 0) l.push(s.sessions_today + (s.sessions_today === 1 ? " session today" : " sessions today"))
        return l.length > 0 ? l : ["Ready to code"]
    }

    function meterColor(p) {
        return p >= 100 ? Theme.red : p >= 80 ? Theme.yellow : Theme.cyan
    }

    function liveLabel(lv) {
        if (!lv) return ""
        const st = lv.state || "running"
        const base = st === "question" ? "Input" : st === "waiting" ? "Waiting" : st === "working" ? "Working" : st === "done" ? "Done" : "Live"
        return lv.count > 1 ? base + " · " + lv.count : base
    }

    function liveColor(lv) {
        if (!lv) return Theme.green
        const st = lv.state || "running"
        if (st === "question" || st === "waiting") return Theme.yellow
        if (st === "working") return Theme.cyan
        return Theme.green
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
            Quickshell.execDetached(["pkill", "-RTMIN+12", "-x", "waybar"])
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
        else if (Date.now() - closedAt > 400) open()
    }

    // ── actions + cursor ─────────────────────────────────────────────────
    function agentById(id) {
        for (const a of agents) if (a.id === id) return a
        return null
    }

    function activate(id) {
        if (!id) return
        const idx = id.indexOf(":")
        const what = idx >= 0 ? id.slice(0, idx) : id
        const arg = idx >= 0 ? id.slice(idx + 1) : ""
        if (what === "refresh") { refresh(true); toast("Refreshing limits & stats…") }
        else if (what === "launch") { run(["launch", arg]); close() }
        else if (what === "focus") { run(["focus", arg]); close() }
        else if (what === "login") { run(["login", arg]); close() }
    }

    function quickJumpOrLaunch(index) {
        if (index < 0 || index >= agents.length) return
        const a = agents[index]
        const lv = liveFor(a)
        if (lv && lv.target) activate("focus:" + lv.target)
        else activate("launch:" + a.id)
    }

    function isHot(id) { return cursorActive && cursor === id }
    function hover(id) { cursor = id; cursorActive = true }

    function focusRows() {
        const rows = [["refresh"]]
        for (const a of agents) {
            const row = []
            const lv = liveFor(a)
            if (lv && lv.target) row.push("focus:" + lv.target)
            if (a.error && a.auth_error) row.push("login:" + a.id)
            row.push("launch:" + a.id)
            rows.push(row)
        }
        return rows
    }

    function move(dr, dc) {
        const rows = focusRows()
        let ri = -1, ci = 0
        for (let i = 0; i < rows.length && ri < 0; i++) {
            const j = rows[i].indexOf(cursor)
            if (j >= 0) { ri = i; ci = j }
        }
        if (ri < 0 || !cursorActive) {
            cursorActive = true
            cursor = rows.length > 1 ? rows[1][0] : rows[0][0]
            return
        }
        ri = Math.max(0, Math.min(rows.length - 1, ri + dr))
        ci = dr !== 0 ? Math.min(ci, rows[ri].length - 1) : Math.max(0, Math.min(rows[ri].length - 1, ci + dc))
        cursor = rows[ri][ci]
    }

    function hint(id) {
        if (!cursorActive || !id) return "1-5 launch   j k move   r refresh   Esc close"
        const idx = id.indexOf(":")
        const what = idx >= 0 ? id.slice(0, idx) : id
        const arg = idx >= 0 ? id.slice(idx + 1) : ""
        if (what === "refresh") return "Refresh limits and usage across all agents"
        if (what === "launch") {
            const a = agentById(arg)
            return "Start " + (a ? a.name : arg) + " in a new tmux window"
        }
        if (what === "focus") return "Jump to live tmux pane (" + arg + ")"
        if (what === "login") {
            const a = agentById(arg)
            return "Sign in again to " + (a ? a.name : arg)
        }
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
        property int size: 30
        property int glyphSize: 15
        signal hovered()
        signal activated()
        implicitWidth: size
        implicitHeight: size
        radius: 9
        color: hot ? Theme.lift : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
        Icon {
            anchors.centerIn: parent
            text: ib.glyph
            font.pixelSize: ib.glyphSize
            color: ib.hot ? Theme.fgBright : Theme.muted
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

    // One limit window: label, meter (with optional 3P scoped ticks), time to reset (exact % on hover).
    component WindowRow: Item {
        id: wr
        property var win
        property double now
        readonly property double pct: win ? Math.min(100, win.percent) : 0
        readonly property var scoped: win && win.scoped ? win.scoped : []
        implicitHeight: 24
        HoverHandler { id: wrHover }
        RowLayout {
            anchors.fill: parent
            spacing: 10
            Label {
                Layout.preferredWidth: 56
                text: wr.win ? wr.win.label : ""
                color: Theme.muted
                font.pixelSize: 12
            }
            Rectangle {
                id: track
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
                // Scoped allowance ticks (e.g. Antigravity's Claude/GPT bucket on the same clock)
                Repeater {
                    model: wr.scoped
                    Rectangle {
                        required property var modelData
                        width: 2
                        height: 12
                        radius: 1
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.max(0, Math.min(track.width - width, track.width * Math.min(100, modelData.percent) / 100 - width / 2))
                        color: root.meterColor(modelData.percent)
                    }
                }
            }
            Label {
                Layout.preferredWidth: 102
                horizontalAlignment: Text.AlignRight
                font.pixelSize: 12
                color: wrHover.hovered ? Theme.fg : (wr.pct >= 100 ? Theme.red : Theme.faint)
                text: !wr.win ? ""
                    : wrHover.hovered
                        ? Math.round(wr.win.percent) + "% used" + (wr.scoped.length > 0 ? " · " + wr.scoped[0].title + " " + Math.round(wr.scoped[0].percent) + "%" : "")
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
        implicitWidth: 416
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
                    else if (k >= Qt.Key_1 && k <= Qt.Key_9) root.quickJumpOrLaunch(k - Qt.Key_1)
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
                        Rectangle {
                            visible: root.liveTotal > 0
                            width: 9
                            height: 9
                            radius: 5
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 3
                            color: Theme.green
                            border.width: 2
                            border.color: Theme.ink
                        }
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
                        size: 32
                        glyphSize: 16
                        spinning: root.loading
                        hot: root.isHot("refresh")
                        onHovered: root.hover("refresh")
                        onActivated: root.activate("refresh")
                    }
                }

                Rule {}

                RowLayout {
                    Layout.fillWidth: true
                    SectionTitle { text: "AGENTS" }
                    Item { Layout.fillWidth: true }
                    Label {
                        visible: root.agents.length > 0
                        font.pixelSize: 11
                        color: Theme.faint
                        text: root.agents.length + " detected" + (root.liveTotal > 0 ? " · " + root.liveTotal + " live" : "")
                    }
                }

                Label {
                    visible: root.agents.length === 0
                    color: Theme.faint
                    font.pixelSize: 12
                    text: root.loading ? "Detecting agents…" : "No supported agent CLI detected"
                }

                Flickable {
                    id: listFlick
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(520, agentsCol.implicitHeight)
                    contentWidth: width
                    contentHeight: agentsCol.implicitHeight
                    clip: true
                    interactive: contentHeight > height
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: agentsCol
                        width: listFlick.width
                        spacing: 10

                        Repeater {
                            model: root.agents
                            delegate: ColumnLayout {
                                id: agentBox
                                required property var modelData
                                required property int index
                                readonly property var lv: root.liveFor(modelData)
                                readonly property var usg: root.usageFor(modelData.id)
                                readonly property bool hasWindows: modelData.windows && modelData.windows.length > 0
                                readonly property bool hasActivity: !!usg && usg.week_tokens > 0
                                readonly property bool stale: !!modelData.error && hasWindows

                                Layout.fillWidth: true
                                spacing: 4

                                // Divider between agent blocks
                                Rectangle {
                                    visible: agentBox.index > 0
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 4
                                    implicitHeight: 1
                                    color: Theme.rule
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Image {
                                        Layout.preferredWidth: 19
                                        Layout.preferredHeight: 19
                                        source: Qt.resolvedUrl("assets/" + agentBox.modelData.id + ".svg")
                                        sourceSize: Qt.size(38, 38)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: false
                                        smooth: true
                                    }

                                    Label {
                                        text: agentBox.modelData.name
                                        font.weight: Font.Bold
                                    }

                                    Label {
                                        visible: !!agentBox.modelData.plan
                                        text: agentBox.modelData.plan
                                        color: Theme.muted
                                        font.pixelSize: 12
                                    }

                                    // Live tmux session pill (click to jump straight to that pane)
                                    Rectangle {
                                        id: livePill
                                        visible: !!agentBox.lv
                                        readonly property string focusId: agentBox.lv && agentBox.lv.target ? "focus:" + agentBox.lv.target : ""
                                        readonly property bool hot: focusId !== "" && root.isHot(focusId)
                                        readonly property color pillColor: root.liveColor(agentBox.lv)
                                        implicitWidth: liveRow.implicitWidth + 12
                                        implicitHeight: 20
                                        radius: 10
                                        color: hot ? Theme.alpha(pillColor, 0.28) : Theme.alpha(pillColor, 0.14)
                                        border.width: 1
                                        border.color: hot ? pillColor : Theme.alpha(pillColor, 0.35)
                                        Row {
                                            id: liveRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Rectangle {
                                                width: 6
                                                height: 6
                                                radius: 3
                                                anchors.verticalCenter: parent.verticalCenter
                                                color: livePill.pillColor
                                            }
                                            Text {
                                                text: root.liveLabel(agentBox.lv)
                                                color: livePill.pillColor
                                                font.family: Theme.sans
                                                font.pixelSize: 11
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                        Hit {
                                            anchors.fill: parent
                                            enabled: livePill.focusId !== ""
                                            onEntered: root.hover(livePill.focusId)
                                            onClicked: root.activate(livePill.focusId)
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    // Status note / auth prompt
                                    Label {
                                        visible: !!agentBox.modelData.error || !!agentBox.modelData.status_note
                                        font.pixelSize: 11
                                        color: agentBox.modelData.auth_error
                                            ? (root.isHot("login:" + agentBox.modelData.id) ? Theme.fgBright : Theme.yellow)
                                            : Theme.faint
                                        font.underline: !!agentBox.modelData.auth_error
                                        text: agentBox.modelData.auth_error ? "Sign-in required"
                                            : agentBox.modelData.status_note ? "󰋼 " + agentBox.modelData.status_note
                                            : agentBox.stale ? "󰋼 Last known"
                                            : "Limits unavailable"
                                        Hit {
                                            anchors.fill: parent
                                            enabled: !!agentBox.modelData.auth_error
                                            onEntered: root.hover("login:" + agentBox.modelData.id)
                                            onClicked: root.activate("login:" + agentBox.modelData.id)
                                        }
                                    }

                                    // Per-agent terminal launcher
                                    IconButton {
                                        glyph: "󰞷"
                                        size: 26
                                        glyphSize: 14
                                        hot: root.isHot("launch:" + agentBox.modelData.id)
                                        onHovered: root.hover("launch:" + agentBox.modelData.id)
                                        onActivated: root.activate("launch:" + agentBox.modelData.id)
                                    }
                                }

                                // Rate-limit meters (Claude, Codex, Antigravity, OpenCode Go)
                                Repeater {
                                    model: agentBox.hasWindows ? agentBox.modelData.windows : []
                                    WindowRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 27
                                        win: modelData
                                        now: root.now
                                        opacity: agentBox.stale ? 0.55 : 1
                                    }
                                }

                                // 7-day sparkline when there are no quota windows (OpenCode Zen, Pi, etc.)
                                Item {
                                    id: sparkRow
                                    visible: !agentBox.hasWindows && agentBox.hasActivity
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 27
                                    implicitHeight: 22
                                    readonly property var days: (agentBox.usg && agentBox.usg.daily_tokens) ? agentBox.usg.daily_tokens : []
                                    readonly property double peak: {
                                        let m = 0
                                        for (const v of days) if (v > m) m = v
                                        return m
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 10
                                        Label {
                                            Layout.preferredWidth: 56
                                            text: "7-day"
                                            color: Theme.muted
                                            font.pixelSize: 12
                                        }
                                        Item {
                                            id: sparkBars
                                            Layout.fillWidth: true
                                            implicitHeight: 16
                                            Row {
                                                anchors.fill: parent
                                                spacing: 4
                                                Repeater {
                                                    model: sparkRow.days.length
                                                    Rectangle {
                                                        required property int index
                                                        readonly property double val: sparkRow.days[index] || 0
                                                        readonly property bool isToday: index === sparkRow.days.length - 1
                                                        width: Math.max(4, (sparkBars.width - 4 * Math.max(0, sparkRow.days.length - 1)) / Math.max(1, sparkRow.days.length))
                                                        height: val > 0 && sparkRow.peak > 0 ? Math.max(4, sparkBars.height * val / sparkRow.peak) : 3
                                                        y: sparkBars.height - height
                                                        radius: Math.min(width, height) / 2
                                                        color: val <= 0 ? Theme.lift : (isToday ? Theme.cyan : Theme.alpha(Theme.accent, 0.55))
                                                    }
                                                }
                                            }
                                        }
                                        Label {
                                            Layout.preferredWidth: 102
                                            horizontalAlignment: Text.AlignRight
                                            font.pixelSize: 12
                                            color: Theme.faint
                                            text: agentBox.usg ? (agentBox.usg.today_tokens > 0 ? root.tokens(agentBox.usg.today_tokens) + " today" : root.tokens(agentBox.usg.week_tokens) + " / 7d") : ""
                                        }
                                    }
                                }

                                // Subtle per-agent model & token caption
                                Label {
                                    visible: agentBox.hasActivity && (agentBox.hasWindows || (agentBox.usg && agentBox.usg.top_model !== ""))
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 27
                                    font.pixelSize: 11
                                    color: Theme.faint
                                    text: {
                                        const u = agentBox.usg
                                        if (!u) return ""
                                        const parts = []
                                        if (agentBox.hasWindows) {
                                            if (u.today_tokens > 0) parts.push(root.tokens(u.today_tokens) + " today")
                                            else if (u.week_tokens > 0) parts.push(root.tokens(u.week_tokens) + " this week")
                                        }
                                        if (u.top_model) parts.push(u.top_model)
                                        if (u.today_prompts > 0) parts.push(u.today_prompts + (u.today_prompts === 1 ? " prompt" : " prompts"))
                                        return parts.join(" · ")
                                    }
                                }
                            }
                        }
                    }
                }

                Rule {}

                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: -4
                    font.pixelSize: 11
                    color: root.toastText ? Theme.cyan : Theme.faint
                    text: root.toastText ? root.toastText
                        : root.cursorActive ? root.hint(root.cursor)
                        : root.fetchedAt ? "Updated " + root.duration(root.now - root.fetchedAt).replace("now", "just now") + (root.now - root.fetchedAt >= 60 ? " ago" : "") + "   ·   1-" + Math.max(1, root.agents.length) + " launch   r refresh"
                        : root.hint("")
                }
            }
        }
    }
}
