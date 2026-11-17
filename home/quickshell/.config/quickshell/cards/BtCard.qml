// Bluetooth card: the drop-down behind the bar's Bluetooth icon (SUPER + B).
//
// Modelled on Omarchy 4.5's Bluetooth panel (MIT, github.com/basecamp/omarchy,
// shell/plugins/panels/bluetooth): a hero with the on/off switch and a status
// line, then CONNECTED, PAIRED and (while scanning) AVAILABLE devices. Click
// connects / disconnects / pairs; the x on a paired device forgets it. The
// adapter scans only while the card is open. Devices come live from
// Quickshell.Bluetooth (BlueZ); actions run through btctl.sh.
//
// Keys: j/k move, l / h to the forget button and back, Enter select,
// d forget, Esc close.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth

Scope {
    id: root

    readonly property string ctl: decodeURIComponent(Qt.resolvedUrl("btctl.sh").toString().replace("file://", ""))
    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"

    property bool opened: false
    property double closedAt: 0
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: !!adapter && adapter.enabled
    readonly property var allDevices: Bluetooth.devices ? Bluetooth.devices.values : []

    // address -> "connecting" | "disconnecting" | "forgetting"
    property var pending: ({})
    property bool powerBusy: false
    property int phraseIndex: 0
    readonly property var phrases: ["Untangling wires", "Streaming vikings", "Pairing mysteries", "Herding headsets",
                                    "Taming radios", "Summoning speakers", "Wrangling codecs", "Polishing packets"]

    property string cursor: ""
    property bool cursorActive: false

    // ── devices ──────────────────────────────────────────────────────────
    function label(d) { return String(d.deviceName || d.name || "").trim() }
    function humanName(d) {
        const n = label(d)
        return n !== "" && !/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(n) && !/^[0-9a-f-]{32,36}$/i.test(n)
    }
    function row(d, section) {
        // plain values only: BlueZ can drop a device object while a row still uses it
        return { address: d.address, name: label(d), section: section, connected: !!d.connected,
                 state: d.state !== undefined ? d.state : -1, pairing: !!d.pairing, icon: d.icon || "",
                 battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1 }
    }
    readonly property var rows: {
        const c = [], k = [], a = []
        for (const d of allDevices) {
            if (!d || !humanName(d)) continue
            if (d.connected) c.push(d)
            else if (d.paired || d.bonded || d.trusted) k.push(d)
            else a.push(d)
        }
        const byName = (x, y) => label(x).localeCompare(label(y))
        const out = []
        c.sort(byName).forEach(d => out.push(row(d, "CONNECTED")))
        k.sort(byName).forEach(d => out.push(row(d, "PAIRED")))
        if (adapter && adapter.discovering) a.sort(byName).forEach(d => out.push(row(d, "AVAILABLE")))
        return out
    }
    readonly property var connectedRows: rows.filter(r => r.connected)

    function device(address) {
        for (const d of allDevices) if (d && d.address === address) return d
        return null
    }

    function typeIcon(icon, connected) {
        if (/headset|headphone|audio/.test(icon)) return "󰋋"
        if (/mouse/.test(icon)) return "󰍽"
        if (/keyboard/.test(icon)) return "󰌌"
        if (/phone/.test(icon)) return "󰏲"
        if (/gaming|joystick/.test(icon)) return "󰊴"
        if (/computer/.test(icon)) return "󰟀"
        return connected ? "󰂱" : "󰂯"
    }

    function setPending(address, action) {
        const next = Object.assign({}, pending)
        if (action) next[address] = action
        else delete next[address]
        pending = next
        if (action) pendingTimeout.restart()
    }

    function act(r) {
        if (!r || pending[r.address]) return
        if (r.connected) {
            setPending(r.address, "disconnecting")
            Quickshell.execDetached([ctl, "disconnect", r.address])
        } else {
            setPending(r.address, "connecting")
            Quickshell.execDetached([ctl, r.section === "AVAILABLE" ? "pair" : "connect", r.address])
        }
    }

    function forget(r) {
        if (!r || r.section === "AVAILABLE" || pending[r.address]) return
        setPending(r.address, "forgetting")
        Quickshell.execDetached([ctl, "forget", r.address])
    }

    function togglePower() {
        if (!adapter || powerBusy) return
        powerBusy = true
        powerProc.command = [ctl, "power", enabled ? "off" : "on"]
        powerProc.running = true
    }

    // Drop a pending label once BlueZ shows the result.
    onAllDevicesChanged: syncPending()
    function syncPending() {
        const next = Object.assign({}, pending)
        let changed = false
        for (const addr in next) {
            const d = device(addr)
            const a = next[addr]
            if ((a === "connecting" && d && d.connected) || (a === "disconnecting" && d && !d.connected)
                || (a === "forgetting" && (!d || !(d.paired || d.bonded || d.trusted)))) {
                delete next[addr]
                changed = true
            }
        }
        if (changed) pending = next
    }

    // ── open / close ─────────────────────────────────────────────────────
    function openOn(name) {
        for (const s of Quickshell.screens) if (s.name === name) targetScreen = s
        cursorActive = false
        cursor = ""
        opened = true
        openAnim.restart()
        Qt.callLater(() => keys.forceActiveFocus())
    }
    function open() { openOn(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") }
    function close() {
        if (!opened) return
        opened = false
        closedAt = Date.now()
        if (adapter && adapter.discovering) adapter.discovering = false
    }
    function toggle() {
        if (opened) close()
        else if (Date.now() - closedAt > 400) open()
    }

    // scan while open
    Timer {
        interval: 1500; repeat: true; triggeredOnStart: true
        running: root.opened && root.enabled
        onTriggered: if (root.adapter && !root.adapter.discovering) root.adapter.discovering = true
    }
    Timer { interval: 2600; repeat: true; running: root.opened && root.enabled; onTriggered: phraseFade.restart() }
    Timer { id: pendingTimeout; interval: 25000; onTriggered: root.pending = ({}) }

    Process {
        id: powerProc
        onExited: root.powerBusy = false
    }

    // ── cursor ───────────────────────────────────────────────────────────
    function isHot(id) { return cursorActive && cursor === id }
    function hover(id) { cursor = id; cursorActive = true }

    function focusRows() {
        const r = [["power"]]
        for (const x of rows) r.push(x.section === "AVAILABLE" ? ["dev:" + x.address] : ["dev:" + x.address, "forget:" + x.address])
        return r
    }
    function move(dr, dc) {
        const rs = focusRows()
        let ri = -1, ci = 0
        for (let i = 0; i < rs.length && ri < 0; i++) { const j = rs[i].indexOf(cursor); if (j >= 0) { ri = i; ci = j } }
        if (ri < 0 || !cursorActive) { cursorActive = true; cursor = (rs[1] || rs[0])[0]; return }
        ri = Math.max(0, Math.min(rs.length - 1, ri + dr))
        ci = dr !== 0 ? 0 : Math.max(0, Math.min(rs[ri].length - 1, ci + dc))
        cursor = rs[ri][ci]
    }
    function rowFor(address) { return rows.find(r => r.address === address) }
    function activate(id) {
        if (id === "power") return togglePower()
        const [what, ...rest] = id.split(":")
        const r = rowFor(rest.join(":"))
        if (what === "dev") act(r)
        else if (what === "forget") forget(r)
    }
    function hint(id) {
        if (!cursorActive || !id) return "j k move   Enter select   d forget   Esc close"
        if (id === "power") return enabled ? "Turn Bluetooth off" : "Turn Bluetooth on"
        const [what, ...rest] = id.split(":")
        const r = rowFor(rest.join(":"))
        if (!r) return ""
        if (what === "forget") return "Forget " + r.name
        return r.connected ? "Enter: disconnect   d: forget" : r.section === "AVAILABLE" ? "Enter: pair" : "Enter: connect   d: forget"
    }

    IpcHandler {
        target: "bluetooth"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function openOn(screen: string): void { root.openOn(screen) }
        function togglePower(): void { root.togglePower() }
        function nav(rows: int, cols: int): void { root.move(rows, cols) }
    }

    // ── parts ────────────────────────────────────────────────────────────
    component Label: Text {
        color: Theme.fg
        font.family: Theme.sans
        font.pixelSize: 13
        font.weight: Font.Medium
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

    // ── the card ─────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.opened
        screen: root.targetScreen
        anchors { top: true; right: true }
        margins { top: 42; right: 6 }
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 380
        implicitHeight: card.height
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "btcard"
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
                    else if (k === Qt.Key_D || k === Qt.Key_Delete) {
                        const a = root.cursor.replace(/^(dev|forget):/, "")
                        if (a !== root.cursor) root.forget(root.rowFor(a))
                    }
                    else return
                    e.accepted = true
                }
            }

            ColumnLayout {
                id: body
                x: 14
                y: 14
                width: parent.width - 28
                spacing: 10

                // hero
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        implicitWidth: 42
                        implicitHeight: 42
                        radius: 13
                        color: root.connectedRows.length ? Theme.cyanSoft : Theme.field
                        Icon {
                            anchors.centerIn: parent
                            font.pixelSize: 20
                            color: root.connectedRows.length ? Theme.cyan : root.enabled ? Theme.fg : Theme.muted
                            text: !root.adapter ? "󰂲" : !root.enabled ? "󰂲" : root.connectedRows.length ? "󰂱" : "󰂯"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Label { text: "Bluetooth"; font.pixelSize: 15; font.weight: Font.Bold }
                        Label {
                            id: status
                            Layout.fillWidth: true
                            font.pixelSize: 12
                            color: root.enabled && root.connectedRows.length ? Theme.cyan : Theme.muted
                            text: !root.adapter ? "No adapter"
                                : root.powerBusy ? (root.enabled ? "Turning off…" : "Turning on…")
                                : !root.enabled ? "Turned off"
                                : root.connectedRows.length === 1 ? "Connected to " + root.connectedRows[0].name
                                : root.connectedRows.length > 1 ? root.connectedRows.length + " devices connected"
                                : root.phrases[root.phraseIndex % root.phrases.length] + "…"
                            SequentialAnimation {
                                id: phraseFade
                                NumberAnimation { target: status; property: "opacity"; to: 0.15; duration: 160 }
                                ScriptAction { script: root.phraseIndex++ }
                                NumberAnimation { target: status; property: "opacity"; to: 1; duration: 200 }
                            }
                        }
                    }
                    // on / off
                    Rectangle {
                        id: sw
                        visible: !!root.adapter
                        readonly property bool hot: root.isHot("power")
                        implicitWidth: 38
                        implicitHeight: 22
                        radius: 11
                        color: root.enabled ? Theme.green : (hot ? Theme.alpha(Theme.fg, 0.2) : Theme.lift)
                        border.width: hot ? 2 : 0
                        border.color: root.enabled ? Theme.alpha(Theme.green, 0.53) : Theme.alpha(Theme.fg, 0.13)
                        opacity: root.powerBusy ? 0.6 : 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Rectangle {
                            width: 16; height: 16; radius: 8; y: 3
                            x: root.enabled ? sw.width - width - 3 : 3
                            color: root.enabled ? Theme.onAccent : Theme.fg
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        Hit { anchors.fill: parent; onEntered: root.hover("power"); onClicked: root.activate("power") }
                    }
                }

                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.rule }

                // device list
                Flickable {
                    id: flick
                    visible: root.enabled && root.rows.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(list.implicitHeight, Math.max(160, (win.screen ? win.screen.height : 768) - 260))
                    contentHeight: list.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: list
                        width: flick.width
                        spacing: 2
                        Repeater {
                            model: root.rows
                            delegate: Column {
                                id: devRow
                                required property var modelData
                                required property int index
                                width: list.width
                                readonly property var r: modelData
                                readonly property bool hot: root.isHot("dev:" + r.address)
                                readonly property bool forgetHot: root.isHot("forget:" + r.address)
                                readonly property string action: root.pending[r.address] || ""
                                readonly property bool firstOfSection: index === 0 || root.rows[index - 1].section !== r.section

                                SectionTitle {
                                    visible: devRow.firstOfSection
                                    text: devRow.r.section
                                    topPadding: devRow.index === 0 ? 2 : 10
                                    bottomPadding: 6
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 40
                                    radius: 10
                                    color: devRow.hot || devRow.forgetHot ? Theme.lift : "transparent"
                                    Behavior on color { ColorAnimation { duration: 90 } }
                                    Hit {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                                        onEntered: root.hover("dev:" + devRow.r.address)
                                        onClicked: m => m.button === Qt.RightButton
                                            ? (devRow.r.connected ? root.act(devRow.r) : root.forget(devRow.r))
                                            : root.act(devRow.r)
                                    }
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 6
                                        spacing: 12
                                        Icon {
                                            text: root.typeIcon(devRow.r.icon, devRow.r.connected)
                                            color: devRow.r.connected ? Theme.cyan : Theme.fg
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: devRow.r.name
                                            font.weight: devRow.r.connected ? Font.Bold : Font.Medium
                                        }
                                        Label {
                                            visible: text !== ""
                                            font.pixelSize: 12
                                            color: devRow.action !== "" || devRow.r.state === 3 ? Theme.cyan
                                                 : devRow.r.connected ? Theme.green : Theme.muted
                                            text: devRow.action === "forgetting" ? "Forgetting…"
                                                : devRow.action === "disconnecting" || devRow.r.state === 2 ? "Disconnecting…"
                                                : devRow.r.connected ? (devRow.r.battery >= 0 ? "󰁹 " + devRow.r.battery + "%" : "Connected")
                                                : devRow.action === "connecting" || devRow.r.state === 3 || devRow.r.pairing ? "Connecting…"
                                                : devRow.r.section === "AVAILABLE" && devRow.hot ? "Pair" : ""
                                        }
                                        // forget (paired devices), shown on hover
                                        Item {
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            visible: devRow.r.section !== "AVAILABLE" && devRow.action === "" && (devRow.hot || devRow.forgetHot)
                                            Rectangle { anchors.fill: parent; radius: 8; color: devRow.forgetHot ? Theme.alpha(Theme.red, 0.2) : "transparent" }
                                            Icon {
                                                anchors.centerIn: parent
                                                text: "󰅙"
                                                font.pixelSize: 15
                                                color: devRow.forgetHot ? Theme.red : Theme.muted
                                            }
                                            Hit {
                                                anchors.fill: parent
                                                onEntered: root.hover("forget:" + devRow.r.address)
                                                onClicked: root.forget(devRow.r)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    visible: !root.enabled || root.rows.length === 0
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.faint
                    font.pixelSize: 12
                    text: !root.adapter ? "No Bluetooth adapter"
                        : !root.enabled ? "Turn Bluetooth on to scan"
                        : "Scanning for devices…"
                }

                Label {
                    Layout.fillWidth: true
                    font.pixelSize: 11
                    color: Theme.faint
                    text: root.hint(root.cursor)
                }
            }
        }
    }
}
