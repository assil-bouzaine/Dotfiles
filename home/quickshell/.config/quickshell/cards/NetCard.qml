// Network card: the drop-down behind the bar's Wi-Fi icon and SUPER + N.
//
// Modelled on the Omarchy 4.5 network panel (MIT, github.com/basecamp/omarchy):
// connection hero with QR share / speed test / Wi-Fi switch, captive-portal
// sign-in, live ping / loss / throughput / totals / IP / gateway, Wi-Fi band
// pinning, DNS provider, and known + other networks with inline password and
// WPA-Enterprise login, forget, and a re-prompt after a wrong password.
//
// All NetworkManager work happens in netctl.py; this file only draws.
// Part of the "cards" Quickshell instance (shell.qml), toggled over IPC by
// ./card netcard  (qs ipc -c cards call netcard toggle)
// Nothing polls while the card is closed.
//
// Keys: j/k or arrows move between rows, h/l within a row, Enter / Space
// select, d forgets a saved network, r rescans, Esc goes back / closes.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root

    // CARDS_TEST=1: never take the keyboard (for screenshots on a hidden output).
    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"
    readonly property string netctl: decodeURIComponent(Qt.resolvedUrl("netctl.py").toString().replace("file://", ""))

    // ── state ────────────────────────────────────────────────────────────
    property bool opened: false
    property double closedAt: 0
    property string view: "main"          // main | qr | speed
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    property var status: ({})
    property var networks: []
    property int listVersion: 0
    property bool scanning: false

    // throughput and ping history, reset on every open
    property string prevIface: ""
    property double prevRx: 0
    property double prevTx: 0
    property double prevT: 0
    property double downRate: 0
    property double upRate: 0
    property var pingSamples: []
    readonly property int pingWindow: 24
    readonly property int pingAverage: 5

    // one network action at a time
    property string actionSsid: ""
    property string actionKind: ""        // connect | disconnect | forget
    property string failureSsid: ""
    property string failureText: ""
    property string passwordSsid: ""
    property string pendingBand: ""
    property string pendingDns: ""
    property bool dnsCustomOpen: false
    property int phraseIndex: 0
    readonly property var phrases: ["Wiring bits", "Handling packets", "Sorting frames", "Hauling bytes",
                                    "Routing crumbs", "Counting collisions", "Bending light"]

    // keyboard / hover cursor: one highlighted control across the card
    property string cursor: ""
    property bool cursorActive: false

    property string toastText: ""
    property color toastColor: Theme.muted

    property var qr: ({})
    property bool qrReveal: false

    property string speedPhase: ""        // "" | down | up | done
    property bool speedRunning: false
    property double speedDown: 0
    property double speedUp: 0
    property bool speedDownDone: false
    property bool speedUpDone: false
    property double speedProgress: 0
    property string speedError: ""

    // ── derived ──────────────────────────────────────────────────────────
    readonly property string kind: status.kind || "disconnected"
    readonly property bool hasWifiDevice: !!status.wifi_device
    readonly property bool wifiOn: status.wifi_enabled === true
    readonly property bool online: kind === "wifi" || kind === "ethernet"
    readonly property string connectivity: online ? (status.connectivity || "unknown") : "none"
    readonly property bool portal: connectivity === "portal"
    readonly property bool limited: connectivity === "limited"
    readonly property bool connecting: actionKind === "connect" || kind === "connecting"
    readonly property bool canShare: kind === "wifi"
    readonly property bool canSpeed: online
    readonly property var bands: status.bands || []
    readonly property string bandSelected: pendingBand !== "" ? pendingBand : (status.band_selected || "auto")
    readonly property bool bandPinned: bandSelected !== "auto"
    readonly property bool canSelectBand: (kind === "wifi" || pendingBand !== "") && (bands.length > 1 || bandPinned)
    readonly property string dnsSelected: pendingDns !== "" ? pendingDns : (status.dns || "")
    readonly property var dnsProviders: ["DHCP", "Cloudflare", "Google", "Custom"]

    readonly property bool hasPing: pingSamples.length > 0 && connectivity !== "portal" && connectivity !== "limited"
    readonly property double pingAvg: {
        let total = 0, n = 0
        for (let i = Math.max(0, pingSamples.length - pingAverage); i < pingSamples.length; i++)
            if (pingSamples[i] !== null) { total += pingSamples[i]; n++ }
        return n ? total / n : -1
    }
    readonly property int pingLoss: {
        if (!pingSamples.length) return 0
        return Math.round(pingSamples.filter(v => v === null).length * 100 / pingSamples.length)
    }

    // ── helpers ──────────────────────────────────────────────────────────
    function wifiIcon(strength) {
        const icons = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
        return icons[Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))]
    }

    function bytes(n) {
        n = Number(n) || 0
        if (n < 1024) return Math.round(n) + " B"
        if (n < 1048576) return (n / 1024).toFixed(1) + " KB"
        if (n < 1073741824) return (n / 1048576).toFixed(1) + " MB"
        return (n / 1073741824).toFixed(2) + " GB"
    }

    function mbps(bytesPerSec) {
        const v = bytesPerSec * 8 / 1e6
        return v < 10 ? v.toFixed(1) : v.toFixed(0)
    }

    function bandLabel(b) { return b === "auto" ? "Auto" : b + " GHz" }

    function toast(text, color) {
        toastText = text
        toastColor = color || Theme.muted
        toastTimer.restart()
    }

    // Run netctl.py (or anything) once; done(ok, json) gets its parsed output.
    function run(args, done, env) {
        const p = oneShot.createObject(root, { command: args, done: done || null, environment: env || ({}) })
        p.running = true
    }

    function ctl(args, done, env) {
        run([netctl].concat(args), (code, text) => {
            let d = {}
            try { d = JSON.parse(text.trim().split("\n").pop() || "{}") } catch (e) {}
            if (done) done(d)
        }, env)
    }

    function refresh() {
        if (!statusProc.running) statusProc.running = true
        if (!listProc.running) listProc.running = true
    }

    function rescan() {
        if (!wifiOn || scanning) return
        scanning = true
        ctl(["rescan"], () => { scanTail.restart(); listProc.running = true })
    }

    // ── open / close ─────────────────────────────────────────────────────
    function openOn(name) {
        for (const s of Quickshell.screens)
            if (s.name === name) targetScreen = s
        view = "main"
        status = ({})
        prevT = 0; downRate = 0; upRate = 0; pingSamples = []
        failureSsid = ""; failureText = ""; passwordSsid = ""; dnsCustomOpen = false
        toastText = ""
        cursorActive = false
        cursor = ""
        opened = true
        openAnim.restart()
        refresh()
        rescan()
        Qt.callLater(() => keys.forceActiveFocus())
    }

    function open() {
        openOn(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    }

    function close() {
        if (!opened) return
        opened = false
        closedAt = Date.now()
        speedProc.running = false
        passwordSsid = ""
        qrReveal = false
    }

    function toggle() {
        if (opened) close()
        // A click on the bar icon first clears the focus grab (closing the
        // card), then runs the toggle: that click meant "close", not "reopen".
        else if (Date.now() - closedAt > 400) open()
    }

    function back() {
        if (view === "speed") { speedProc.running = false; view = "main"; return }
        if (view !== "main") { view = "main"; qrReveal = false; return }
        if (passwordSsid !== "") { cancelPrompt(); return }
        if (dnsCustomOpen) { dnsCustomOpen = false; keys.forceActiveFocus(); return }
        close()
    }

    // ── actions ──────────────────────────────────────────────────────────
    function netBySsid(ssid) {
        for (const n of networks) if (n.ssid === ssid) return n
        return null
    }

    function cancelPrompt() {
        passwordSsid = ""
        keys.forceActiveFocus()
    }

    function clickNetwork(ssid) {
        const n = netBySsid(ssid)
        if (!n || actionKind !== "") return
        if (n.connected) return disconnect(ssid)
        if (n.known || n.open) return connect(ssid, "", "")
        failureSsid = ""
        passwordSsid = ssid
    }

    function reasonText(r) {
        return ({ wrong_password: "Wrong password", needs_password: "Passphrase required",
                  network_lost: "Network lost", timeout: "Timed out connecting" })[r] || "Connection failed"
    }

    function connect(ssid, secret, identity) {
        actionSsid = ssid
        actionKind = "connect"
        failureSsid = ""
        phraseIndex = Math.floor(Math.random() * phrases.length)
        const args = ["connect", ssid].concat(identity ? ["--identity", identity] : [])
        ctl(args, d => {
            actionKind = ""
            const n = netBySsid(ssid)
            if (d.ok) {
                passwordSsid = ""
                keys.forceActiveFocus()
                toast("Connected to " + ssid, Theme.green)
            } else {
                failureSsid = ssid
                failureText = reasonText(d.reason)
                // Wrong or missing password: open the field again to retype it.
                if ((d.reason === "wrong_password" || d.reason === "needs_password") && n && !n.open)
                    passwordSsid = ssid
            }
            refresh()
        }, secret ? { NETCARD_SECRET: secret } : {})
    }

    function disconnect(ssid) {
        actionSsid = ssid
        actionKind = "disconnect"
        ctl(["disconnect"], d => {
            actionKind = ""
            if (!d.ok) toast("Couldn't disconnect", Theme.red)
            refresh()
        })
    }

    function forget(ssid) {
        const n = netBySsid(ssid)
        if (!n || !n.known || n.connected || actionKind !== "") return
        actionSsid = ssid
        actionKind = "forget"
        ctl(["forget", ssid], d => {
            actionKind = ""
            toast(d.ok ? "Forgot " + ssid : "Couldn't forget " + ssid, d.ok ? Theme.muted : Theme.red)
            refresh()
        })
    }

    function toggleWifi() {
        const on = !wifiOn
        status = Object.assign({}, status, { wifi_enabled: on })
        ctl(["radio", on ? "on" : "off"], d => {
            if (!d.ok) toast("Couldn't switch Wi-Fi " + (on ? "on" : "off"), Theme.red)
            refresh()
            if (on) Qt.callLater(rescan)
        })
    }

    function setBand(b) {
        if (pendingBand !== "") return
        pendingBand = b
        ctl(["band", b], d => {
            pendingBand = ""
            if (!d.ok) toast(d.error || "Couldn't change the band", Theme.red)
            refresh()
        })
    }

    function toggleBandAuto() {
        if (bandPinned) setBand("auto")
        else if (status.band) setBand(status.band)   // pin the band it is on now
    }

    function setDns(provider, servers) {
        if (pendingDns !== "") return
        if (provider === "Custom" && servers === undefined) {
            dnsCustomOpen = true
            return
        }
        pendingDns = provider
        ctl(["dns", provider].concat(servers ? servers.split(/[\s,]+/).filter(s => s) : []), d => {
            pendingDns = ""
            if (d.ok) {
                dnsCustomOpen = false
                keys.forceActiveFocus()
                toast(provider === "DHCP" ? "Using DNS from DHCP" : "DNS set to " + provider, Theme.green)
            } else {
                toast(d.error || "Couldn't change DNS", Theme.red)
            }
            refresh()
        })
    }

    function copy(value, what) {
        if (!value) return
        run(["sh", "-c", "printf %s \"$NETCARD_COPY\" | wl-copy"], null, { NETCARD_COPY: value })
        toast("Copied " + what)
    }

    function openPortal() {
        Quickshell.execDetached(["xdg-open", "http://neverssl.com"])
        close()
    }

    function openQr() {
        ctl(["qr"], d => {
            if (!d.ok) return toast(d.error || "Couldn't make the QR code", Theme.red)
            qr = d
            qrReveal = false
            view = "qr"
        })
    }

    function startSpeed() {
        speedDown = 0; speedUp = 0; speedDownDone = false; speedUpDone = false
        speedProgress = 0; speedError = ""; speedPhase = "down"
        view = "speed"
        speedRunning = true
        speedProc.running = true
    }

    function takeSpeed(line) {
        let d
        try { d = JSON.parse(line) } catch (e) { return }
        if (d.error) speedError = d.error
        if (d.phase === "down") {
            speedDown = d.rate
            if (d.done) { speedDownDone = true; speedPhase = "up"; speedProgress = 0 }
            else speedProgress = d.progress
        } else if (d.phase === "up") {
            speedUp = d.rate
            if (d.done) { speedUpDone = true; speedPhase = "done" }
            else speedProgress = d.progress
        }
    }

    // ── cursor ───────────────────────────────────────────────────────────
    function isHot(id) { return cursorActive && cursor === id }
    function hover(id) { cursor = id; cursorActive = true }

    function focusRows() {
        const rows = []
        const head = []
        if (canShare) head.push("qr")
        if (canSpeed) head.push("speed")
        if (hasWifiDevice) head.push("wifi")
        if (head.length) rows.push(head)
        if (portal) rows.push(["portal"])
        if (online) rows.push(["copy:ip", "copy:gw"])
        if (canSelectBand) {
            rows.push(["band:auto"])
            if (bandPinned) rows.push(bands.map(b => "band:" + b))
        }
        rows.push(dnsProviders.map(p => "dns:" + p))
        if (wifiOn)
            for (const n of networks) {
                const r = ["net:" + n.ssid]
                if (n.known && !n.connected) r.push("forget:" + n.ssid)
                rows.push(r)
            }
        return rows
    }

    function move(dr, dc) {
        const rows = focusRows()
        if (!rows.length) return
        let ri = -1, ci = 0
        for (let i = 0; i < rows.length && ri < 0; i++) {
            const j = rows[i].indexOf(cursor)
            if (j >= 0) { ri = i; ci = j }
        }
        if (ri < 0 || !cursorActive) {
            // First key press: land on the connected / first network, else DNS.
            const first = rows.findIndex(r => r[0].startsWith("net:"))
            ri = first >= 0 ? first : rows.findIndex(r => r[0].startsWith("dns:"))
            ci = 0
            cursorActive = true
            cursor = rows[ri][0]
        } else {
            ri = Math.max(0, Math.min(rows.length - 1, ri + dr))
            ci = dr !== 0 ? Math.min(ci, rows[ri].length - 1) : Math.max(0, Math.min(rows[ri].length - 1, ci + dc))
            cursor = rows[ri][ci]
        }
        scrollToCursor()
    }

    function scrollToCursor() {
        const ssid = cursor.replace(/^(net|forget):/, "")
        if (ssid === cursor) return
        const i = networks.findIndex(n => n.ssid === ssid)
        const item = i >= 0 ? netRepeater.itemAt(i) : null
        if (!item) return
        if (item.y < listFlick.contentY) listFlick.contentY = item.y
        else if (item.y + item.height > listFlick.contentY + listFlick.height)
            listFlick.contentY = item.y + item.height - listFlick.height
    }

    function activate(id) {
        if (!id) return
        const [what, ...rest] = id.split(":")
        const arg = rest.join(":")
        if (what === "qr") openQr()
        else if (what === "speed") startSpeed()
        else if (what === "wifi") toggleWifi()
        else if (what === "portal") openPortal()
        else if (id === "copy:ip") copy(status.ip, "IP address")
        else if (id === "copy:gw") copy(status.gateway, "gateway")
        else if (id === "band:auto") toggleBandAuto()
        else if (what === "band") setBand(arg)
        else if (what === "dns") setDns(arg)
        else if (what === "net") clickNetwork(arg)
        else if (what === "forget") forget(arg)
    }

    function hint(id) {
        if (!cursorActive || !id) return "j k move   h l switch   Enter select   Esc close"
        const [what, ...rest] = id.split(":")
        const arg = rest.join(":")
        const n = what === "net" || what === "forget" ? netBySsid(arg) : null
        switch (what) {
        case "qr": return "Show a QR code to share this Wi-Fi"
        case "speed": return "Run a speed test"
        case "wifi": return wifiOn ? "Turn Wi-Fi off" : "Turn Wi-Fi on"
        case "portal": return "Open the network's sign-in page"
        case "copy": return arg === "ip" ? "Copy the IP address" : "Copy the gateway address"
        case "band": return arg === "auto" ? (bandPinned ? "Let Wi-Fi pick the band" : "Stay on the current band")
                                           : "Stay on " + bandLabel(arg)
        case "dns": return arg === "DHCP" ? "Use DNS from DHCP" : arg === "Custom" ? "Set custom DNS servers"
                                                                   : "Set DNS to " + arg
        case "forget": return "Forget this network"
        case "net": return !n ? "" : n.connected ? "Enter: disconnect" : (n.known ? "Enter: connect   d: forget" : "Enter: connect")
        }
        return ""
    }

    // ── data in ──────────────────────────────────────────────────────────
    function takeStatus(text) {
        let s
        try { s = JSON.parse(text) } catch (e) { return }
        const now = Date.now() / 1000
        const rx = Number(s.rx_bytes || 0), tx = Number(s.tx_bytes || 0)
        if (s.iface && s.iface === prevIface && prevT > 0 && now > prevT) {
            downRate = Math.max(0, (rx - prevRx) / (now - prevT))
            upRate = Math.max(0, (tx - prevTx) / (now - prevT))
        } else {
            downRate = 0; upRate = 0
        }
        if (s.iface !== prevIface) pingSamples = []
        prevIface = s.iface || ""; prevRx = rx; prevTx = tx; prevT = now
        if (s.iface) {
            const p = pingSamples.slice()
            p.push(typeof s.internet_ping === "number" ? s.internet_ping : null)
            while (p.length > pingWindow) p.shift()
            pingSamples = p
        }
        status = s
    }

    function takeList(text) {
        let d
        try { d = JSON.parse(text) } catch (e) { return }
        const nets = d.networks || []
        const same = nets.length === netModel.count && nets.every((n, i) => netModel.get(i).ssid === n.ssid)
        if (same) {
            nets.forEach((n, i) => netModel.set(i, n))
        } else if (passwordSsid === "") {
            netModel.clear()
            nets.forEach(n => netModel.append(n))
        } else {
            return   // keep the rows still while a password is being typed
        }
        networks = nets
        listVersion++
    }

    ListModel { id: netModel }

    // ── processes and timers (all idle while closed) ────────────────────
    Process {
        id: statusProc
        command: [root.netctl, "status"]
        stdout: StdioCollector { onStreamFinished: root.takeStatus(text) }
    }

    Process {
        id: listProc
        command: [root.netctl, "list"]
        stdout: StdioCollector { onStreamFinished: root.takeList(text) }
    }

    // NetworkManager tells us about every state change; refresh right after.
    Process {
        running: root.opened
        command: ["nmcli", "monitor"]
        stdout: SplitParser { onRead: data => nmSettle.restart() }
    }

    Process {
        id: speedProc
        command: [root.netctl, "speed"]
        stdout: SplitParser { onRead: data => root.takeSpeed(data) }
        onExited: (code, exitStatus) => {
            root.speedRunning = false
            if (root.speedPhase !== "done" && !root.speedError && code !== 0) root.speedError = "Speed test stopped"
            if (root.speedPhase !== "done") root.speedPhase = "done"
        }
    }

    Component {
        id: oneShot
        Process {
            id: p
            property var done: null
            property string out: ""
            property bool streamed: false
            property bool exited: false
            property int code: 0
            function finish() {
                if (!streamed || !exited) return
                if (done) done(code, out)
                p.destroy()
            }
            stdout: StdioCollector { onStreamFinished: { p.out = text; p.streamed = true; p.finish() } }
            onExited: (exitCode, exitStatus) => { p.code = exitCode; p.exited = true; p.finish() }
        }
    }

    Timer { id: nmSettle; interval: 350; onTriggered: root.refresh() }
    Timer { interval: 1500; repeat: true; running: root.opened; onTriggered: if (!statusProc.running) statusProc.running = true }
    Timer { interval: 4000; repeat: true; running: root.opened; onTriggered: if (!listProc.running) listProc.running = true }
    Timer { interval: 20000; repeat: true; running: root.opened && root.wifiOn; onTriggered: root.rescan() }
    Timer { id: scanTail; interval: 2500; onTriggered: { root.scanning = false; root.refresh() } }
    Timer { id: toastTimer; interval: 2600; onTriggered: root.toastText = "" }
    Timer { interval: 900; repeat: true; running: root.opened && root.connecting; onTriggered: root.phraseIndex++ }
    // Behind a portal nothing changes on this machine once you've signed in,
    // so ask NetworkManager to probe again until the internet is reachable.
    Timer {
        interval: 4000; repeat: true
        running: root.opened && (root.portal || root.limited)
        onTriggered: root.run(["nmcli", "networking", "connectivity", "check"], () => root.refresh())
    }

    IpcHandler {
        target: "netcard"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function openOn(screen: string): void { root.openOn(screen) }
        // for testing
        function activate(id: string): void { root.activate(id) }
        function nav(rows: int, cols: int): void { root.move(rows, cols) }
        function back(): void { root.back() }
        function prompt(ssid: string): void { root.passwordSsid = ssid }
    }

    // ── small parts ──────────────────────────────────────────────────────
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

    // A clickable spot. `hot` comes from the shared cursor.
    component Hit: MouseArea {
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        acceptedButtons: Qt.LeftButton
    }

    component IconButton: Rectangle {
        id: ib
        property string glyph
        property bool hot: false
        property color tint: Theme.fg
        signal hovered()
        signal activated()
        implicitWidth: 32
        implicitHeight: 32
        radius: 10
        color: hot ? Theme.lift : "transparent"
        Behavior on color { ColorAnimation { duration: 90 } }
        Icon { anchors.centerIn: parent; text: ib.glyph; color: ib.tint; font.pixelSize: 16 }
        Hit { anchors.fill: parent; onEntered: ib.hovered(); onClicked: ib.activated() }
    }

    component Switch: Rectangle {
        id: sw
        property bool on: false
        property bool hot: false
        signal hovered()
        signal activated()
        implicitWidth: 38
        implicitHeight: 22
        radius: 11
        color: on ? Theme.green : (hot ? Theme.alpha(Theme.fg, 0.2) : Theme.lift)
        border.width: hot ? 2 : 0
        border.color: on ? Theme.alpha(Theme.green, 0.53) : Theme.alpha(Theme.fg, 0.13)
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            width: 16; height: 16; radius: 8
            y: 3
            x: sw.on ? sw.width - width - 3 : 3
            color: sw.on ? Theme.onAccent : Theme.fg
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
        Hit { anchors.fill: parent; onEntered: sw.hovered(); onClicked: sw.activated() }
    }

    component Pill: Rectangle {
        id: pill
        property string label
        property bool selected: false
        property bool hot: false
        property bool busy: false
        signal hovered()
        signal activated()
        implicitHeight: 30
        radius: 9
        color: selected ? (hot ? Theme.alpha(Theme.accent, 0.25) : Theme.cyanSoft) : (hot ? Theme.lift : Theme.field)
        border.width: hot ? 2 : 1
        border.color: selected ? (hot ? Theme.cyan : Theme.alpha(Theme.accent, 0.4)) : (hot ? Theme.alpha(Theme.fg, 0.25) : "transparent")
        Behavior on color { ColorAnimation { duration: 90 } }
        Label {
            anchors.centerIn: parent
            text: pill.label
            color: pill.selected ? Theme.cyan : Theme.fg
            font.weight: pill.selected ? Font.Bold : Font.Medium
            font.pixelSize: 13
            opacity: pill.busy ? 0.55 : 1
        }
        Hit { anchors.fill: parent; onEntered: pill.hovered(); onClicked: pill.activated() }
    }

    component Field: Rectangle {
        id: fld
        property alias input: inp
        property alias text: inp.text
        property string placeholder
        property bool secret: false
        property bool reveal: false
        signal accepted()
        signal cancelled()
        signal tabbed()
        implicitHeight: 34
        radius: 9
        color: Theme.field
        border.width: 1
        border.color: inp.activeFocus ? Theme.alpha(Theme.accent, 0.5) : Theme.alpha(Theme.fg, 0.08)
        TextInput {
            id: inp
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.fg
            selectionColor: Theme.alpha(Theme.accent, 0.33)
            font.family: Theme.sans
            font.pixelSize: 13
            echoMode: fld.secret && !fld.reveal ? TextInput.Password : TextInput.Normal
            passwordCharacter: "•"
            clip: true
            selectByMouse: true
            Keys.onEscapePressed: e => { fld.cancelled(); e.accepted = true }
            Keys.onReturnPressed: e => { fld.accepted(); e.accepted = true }
            Keys.onEnterPressed: e => { fld.accepted(); e.accepted = true }
            Keys.onTabPressed: e => { fld.tabbed(); e.accepted = true }
        }
        Text {
            anchors.fill: inp
            verticalAlignment: Text.AlignVCenter
            text: fld.placeholder
            color: Theme.faint
            font.family: Theme.sans
            font.pixelSize: 13
            visible: inp.text === ""
        }
    }

    component Stat: Item {
        id: st
        property string label
        property string value
        property bool hot: false
        property bool copyable: false
        signal hovered()
        signal activated()
        implicitHeight: 28
        Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -8
            anchors.rightMargin: -8
            radius: 8
            color: st.hot && st.copyable ? Theme.lift : "transparent"
        }
        Label {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: st.label
            color: Theme.muted
            font.pixelSize: 12
        }
        Label {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.62)
            horizontalAlignment: Text.AlignRight
            text: st.hot && st.copyable ? "󰆏  " + st.value : st.value
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Hit {
            anchors.fill: parent
            enabled: st.copyable
            onEntered: st.hovered()
            onClicked: st.activated()
        }
    }

    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Theme.rule
    }

    // A speed dial: 270° arc on a log scale up to 1 Gbit/s.
    component Dial: Item {
        id: dial
        property string label
        property double rate: 0       // bytes/s
        property bool active: false
        property bool done: false
        readonly property double mbit: rate * 8 / 1e6
        implicitWidth: 160
        implicitHeight: 150
        onMbitChanged: arc.requestPaint()
        onActiveChanged: arc.requestPaint()
        Canvas {
            id: arc
            anchors.fill: parent
            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                const cx = width / 2, cy = height / 2 + 4, r = Math.min(width, height) / 2 - 10
                const a0 = Math.PI * 0.75, span = Math.PI * 1.5
                ctx.lineWidth = 9
                ctx.lineCap = "round"
                ctx.strokeStyle = "rgba(" + Math.round(Theme.fg.r * 255) + "," + Math.round(Theme.fg.g * 255) + "," + Math.round(Theme.fg.b * 255) + ",0.09)"
                ctx.beginPath(); ctx.arc(cx, cy, r, a0, a0 + span); ctx.stroke()
                const f = Math.min(1, Math.log10(1 + dial.mbit) / 3)
                if (f > 0.003) {
                    const g = ctx.createLinearGradient(cx - r, cy, cx + r, cy)
                    g.addColorStop(0, String(Theme.accent)); g.addColorStop(1, String(Theme.accent2))
                    ctx.strokeStyle = g
                    ctx.beginPath(); ctx.arc(cx, cy, r, a0, a0 + span * f); ctx.stroke()
                }
            }
        }
        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 6
            spacing: 0
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: dial.active || dial.done ? (dial.mbit < 10 ? dial.mbit.toFixed(1) : dial.mbit.toFixed(0)) : "--"
                font.pixelSize: 30
                font.weight: Font.Bold
                color: dial.done ? Theme.fg : (dial.active ? Theme.cyan : Theme.faint)
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Mbps"
                color: Theme.muted
                font.pixelSize: 11
            }
        }
        SectionTitle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: dial.label
            color: dial.active ? Theme.cyan : Theme.muted
        }
    }

    // ── the card ─────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.opened
        screen: root.targetScreen
        anchors { top: true; right: true }
        margins { top: 42; right: 6 }          // under the bar, like the rofi cards
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 404
        implicitHeight: card.height
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "netcard"
        WlrLayershell.keyboardFocus: root.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        readonly property int screenHeight: screen ? screen.height : 768

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
            transform: Translate { id: slide; y: 0 }

            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 130 }
                NumberAnimation { target: slide; property: "y"; from: -8; to: 0; duration: 170; easing.type: Easing.OutCubic }
            }

            // Click on empty card space: leave any text field.
            MouseArea { anchors.fill: parent; onClicked: keys.forceActiveFocus() }

            Item {
                id: keys
                focus: true
                Keys.onPressed: e => {
                    const k = e.key
                    const shift = e.modifiers & Qt.ShiftModifier
                    if (k === Qt.Key_Escape) root.back()
                    else if (root.view === "speed") {
                        if ((k === Qt.Key_Return || k === Qt.Key_Space || k === Qt.Key_R) && !root.speedRunning) root.startSpeed()
                        else if (k === Qt.Key_H || k === Qt.Key_Left || k === Qt.Key_Backspace) root.back()
                        else return
                    } else if (root.view === "qr") {
                        if (k === Qt.Key_C) root.copy(root.qr.password, "password")
                        else if (k === Qt.Key_Space || k === Qt.Key_V) root.qrReveal = !root.qrReveal
                        else if (k === Qt.Key_H || k === Qt.Key_Left || k === Qt.Key_Backspace) root.back()
                        else return
                    }
                    else if (k === Qt.Key_J || k === Qt.Key_Down || (k === Qt.Key_Tab && !shift)) root.move(1, 0)
                    else if (k === Qt.Key_K || k === Qt.Key_Up || k === Qt.Key_Backtab) root.move(-1, 0)
                    else if (k === Qt.Key_H || k === Qt.Key_Left) root.move(0, -1)
                    else if (k === Qt.Key_L || k === Qt.Key_Right) root.move(0, 1)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
                        if (!root.cursorActive) root.move(0, 0)
                        else root.activate(root.cursor)
                    }
                    else if (k === Qt.Key_D || k === Qt.Key_Delete) {
                        const ssid = root.cursor.replace(/^(net|forget):/, "")
                        if (ssid !== root.cursor) root.forget(ssid)
                    }
                    else if (k === Qt.Key_R) root.rescan()
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

                // ── main view ────────────────────────────────────────
                ColumnLayout {
                    id: upper
                    visible: root.view === "main"
                    Layout.fillWidth: true
                    spacing: 12

                    // hero
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Rectangle {
                            implicitWidth: 42
                            implicitHeight: 42
                            radius: 13
                            color: root.portal || root.limited ? Theme.yellowSoft
                                 : root.online ? Theme.greenSoft : Theme.field
                            Icon {
                                anchors.centerIn: parent
                                font.pixelSize: 20
                                color: root.portal || root.limited ? Theme.yellow
                                     : root.online ? Theme.green : Theme.muted
                                text: {
                                    const restricted = root.portal || root.limited
                                    if (root.kind === "wifi") return restricted ? "󰤩" : root.wifiIcon(root.status.signal || 0)
                                    if (root.kind === "ethernet") return restricted ? "󰈂" : "󰈀"
                                    if (root.hasWifiDevice && !root.wifiOn) return "󰖪"
                                    return "󰤮"
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label {
                                Layout.fillWidth: true
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                text: root.actionKind === "connect" ? root.actionSsid
                                    : root.kind === "wifi" ? (root.status.ssid || "Wi-Fi")
                                    : root.kind === "ethernet" ? "Ethernet"
                                    : root.status.kind === undefined ? " "
                                    : root.hasWifiDevice && !root.wifiOn ? "Wi-Fi is off" : "Not connected"
                            }
                            Label {
                                Layout.fillWidth: true
                                font.pixelSize: 12
                                color: root.connecting ? Theme.cyan
                                     : root.portal || root.limited ? Theme.yellow : Theme.muted
                                text: {
                                    if (root.connecting) return root.phrases[root.phraseIndex % root.phrases.length] + "…"
                                    if (root.portal) return "Sign-in required"
                                    if (root.limited) return "Limited internet access"
                                    if (root.kind === "wifi") {
                                        const parts = []   // the green icon already says connected
                                        if (root.status.band) parts.push(root.bandLabel(root.status.band))
                                        if (root.status.rate) parts.push(root.status.rate)
                                        return parts.length ? parts.join(" · ") : "Connected"
                                    }
                                    if (root.kind === "ethernet") {
                                        const sp = root.status.speed
                                        return "Connected" + (sp > 0 ? " · " + (sp >= 1000 ? sp / 1000 + " Gb/s" : sp + " Mb/s") : "")
                                    }
                                    if (root.status.kind === undefined) return " "
                                    if (root.hasWifiDevice && !root.wifiOn) return "Turn it on to see networks"
                                    return "Pick a network below"
                                }
                            }
                        }

                        IconButton {
                            visible: root.canShare
                            glyph: "󰐲"
                            hot: root.isHot("qr")
                            onHovered: root.hover("qr")
                            onActivated: root.activate("qr")
                        }
                        IconButton {
                            visible: root.canSpeed
                            glyph: "󰓅"
                            hot: root.isHot("speed")
                            onHovered: root.hover("speed")
                            onActivated: root.activate("speed")
                        }
                        Switch {
                            visible: root.hasWifiDevice
                            Layout.leftMargin: 4
                            on: root.wifiOn
                            hot: root.isHot("wifi")
                            onHovered: root.hover("wifi")
                            onActivated: root.activate("wifi")
                        }
                    }

                    // captive portal
                    Rectangle {
                        visible: root.portal || root.limited
                        Layout.fillWidth: true
                        implicitHeight: 38
                        radius: 10
                        color: root.isHot("portal") ? Theme.alpha(Theme.yellow, 0.24) : Theme.yellowSoft
                        border.width: 1
                        border.color: Theme.alpha(Theme.yellow, 0.33)
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10
                            Icon { text: "󰖟"; color: Theme.yellow }
                            Label {
                                Layout.fillWidth: true
                                color: Theme.yellow
                                font.weight: Font.DemiBold
                                text: root.portal ? "Sign in to this network" : "Limited internet access"
                            }
                            Icon { visible: root.portal; text: "󰁔"; color: Theme.yellow }
                        }
                        Hit {
                            anchors.fill: parent
                            enabled: root.portal
                            onEntered: root.hover("portal")
                            onClicked: root.activate("portal")
                        }
                    }

                    // live details
                    GridLayout {
                        visible: root.online
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 26
                        rowSpacing: 0
                        uniformCellWidths: true

                        Stat {
                            Layout.fillWidth: true
                            label: "Ping"
                            value: !root.hasPing ? "--" : root.pingAvg < 0 ? "Timeout"
                                 : root.pingAvg.toFixed(root.pingAvg < 10 ? 1 : 0) + " ms"
                        }
                        Stat {
                            Layout.fillWidth: true
                            label: "Packet loss"
                            value: root.hasPing ? root.pingLoss + "%" : "--"
                        }
                        Stat { Layout.fillWidth: true; label: "Receiving"; value: root.prevT ? root.bytes(root.downRate) + "/s" : "--" }
                        Stat { Layout.fillWidth: true; label: "Sending"; value: root.prevT ? root.bytes(root.upRate) + "/s" : "--" }
                        Stat { Layout.fillWidth: true; label: "Downloaded"; value: root.status.rx_bytes !== undefined ? root.bytes(root.status.rx_bytes) : "--" }
                        Stat { Layout.fillWidth: true; label: "Uploaded"; value: root.status.tx_bytes !== undefined ? root.bytes(root.status.tx_bytes) : "--" }
                        Stat {
                            Layout.fillWidth: true
                            label: "IP address"
                            value: root.status.ip || "--"
                            copyable: !!root.status.ip
                            hot: root.isHot("copy:ip")
                            onHovered: root.hover("copy:ip")
                            onActivated: root.activate("copy:ip")
                        }
                        Stat {
                            Layout.fillWidth: true
                            label: "Gateway"
                            value: root.status.gateway || "--"
                            copyable: !!root.status.gateway
                            hot: root.isHot("copy:gw")
                            onHovered: root.hover("copy:gw")
                            onActivated: root.activate("copy:gw")
                        }
                    }

                    Rule { visible: root.online }

                    // Wi-Fi band
                    ColumnLayout {
                        visible: root.canSelectBand
                        Layout.fillWidth: true
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            SectionTitle {
                                Layout.fillWidth: true
                                text: root.bandPinned || !root.status.band ? "WI-FI BAND"
                                    : "WI-FI BAND: " + root.bandLabel(root.status.band).toUpperCase()
                            }
                            SectionTitle { text: "AUTOMATIC"; color: Theme.faint }
                            Switch {
                                Layout.leftMargin: 6
                                implicitWidth: 34
                                implicitHeight: 20
                                on: !root.bandPinned
                                hot: root.isHot("band:auto")
                                onHovered: root.hover("band:auto")
                                onActivated: root.activate("band:auto")
                            }
                        }
                        RowLayout {
                            visible: root.bandPinned
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.bands
                                Pill {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    label: root.bandLabel(modelData)
                                    selected: root.bandSelected === modelData
                                    busy: root.pendingBand !== ""
                                    hot: root.isHot("band:" + modelData)
                                    onHovered: root.hover("band:" + modelData)
                                    onActivated: root.activate("band:" + modelData)
                                }
                            }
                        }
                    }

                    // DNS
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            SectionTitle { Layout.fillWidth: true; text: "DNS PROVIDER" }
                            SectionTitle {
                                visible: root.dnsSelected === "Custom" && !!root.status.dns_servers
                                text: (root.status.dns_servers || "").split(",").join("  ")
                                color: Theme.faint
                                font.weight: Font.Medium
                                font.letterSpacing: 0
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: root.dnsProviders
                                Pill {
                                    required property string modelData
                                    Layout.fillWidth: true
                                    label: modelData
                                    selected: root.dnsSelected === modelData
                                    busy: root.pendingDns !== ""
                                    hot: root.isHot("dns:" + modelData)
                                    onHovered: root.hover("dns:" + modelData)
                                    onActivated: root.activate("dns:" + modelData)
                                }
                            }
                        }
                        RowLayout {
                            visible: root.dnsCustomOpen
                            Layout.fillWidth: true
                            spacing: 6
                            Field {
                                id: dnsField
                                Layout.fillWidth: true
                                placeholder: "Servers, e.g. 9.9.9.9 149.112.112.112"
                                onAccepted: root.setDns("Custom", text)
                                onCancelled: { root.dnsCustomOpen = false; keys.forceActiveFocus() }
                            }
                            Pill {
                                implicitWidth: 64
                                label: "Set"
                                selected: true
                                onActivated: root.setDns("Custom", dnsField.text)
                            }
                            Connections {
                                target: root
                                function onDnsCustomOpenChanged() {
                                    if (root.dnsCustomOpen) {
                                        dnsField.text = (root.status.dns_servers || "").split(",").join(" ")
                                        dnsField.input.forceActiveFocus()
                                    }
                                }
                            }
                        }
                    }

                    Rule { visible: root.wifiOn }

                    SectionTitle {
                        visible: root.wifiOn && root.networks.length === 0
                        text: root.scanning || root.status.kind === undefined ? "SCANNING WI-FI…" : "NO NETWORKS IN RANGE"
                    }

                    Label {
                        visible: root.hasWifiDevice && !root.wifiOn && root.status.kind !== undefined
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        horizontalAlignment: Text.AlignHCenter
                        color: Theme.faint
                        text: "Wi-Fi is off. The switch above turns it back on."
                        font.pixelSize: 12
                    }
                }

                // networks
                Flickable {
                    id: listFlick
                    visible: root.view === "main" && root.wifiOn && netModel.count > 0
                    Layout.fillWidth: true
                    Layout.topMargin: -4
                    // Fit under the bar: what's left of the screen after the rest of the card.
                    Layout.preferredHeight: Math.min(listCol.implicitHeight,
                                                     Math.max(130, win.screenHeight - 42 - 16 - 28 - upper.implicitHeight - 12 - footer.implicitHeight - 24))
                    contentHeight: listCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: listCol
                        width: listFlick.width
                        spacing: 2

                        Repeater {
                            id: netRepeater
                            model: netModel

                            delegate: Column {
                                id: row
                                required property int index
                                required property string ssid
                                required property int strength
                                required property bool connected
                                required property bool known
                                required property bool open
                                required property bool enterprise
                                width: listCol.width
                                spacing: 0

                                readonly property bool hot: root.isHot("net:" + ssid)
                                readonly property bool forgetHot: root.isHot("forget:" + ssid)
                                readonly property bool canForget: known && !connected
                                readonly property bool busyHere: root.actionKind !== "" && root.actionSsid === ssid
                                readonly property bool failed: root.failureSsid === ssid && root.failureText !== "" && !busyHere
                                readonly property bool prompting: root.passwordSsid === ssid
                                readonly property string section: {
                                    root.listVersion
                                    if (index === 0) return known ? "KNOWN NETWORKS" : "OTHER NETWORKS"
                                    const prev = netModel.get(index - 1)
                                    return !known && prev && prev.known ? "OTHER NETWORKS" : ""
                                }

                                onPromptingChanged: {
                                    if (prompting) Qt.callLater(() => (enterprise ? idField : pwField).input.forceActiveFocus())
                                    else { pwField.text = ""; pwField.reveal = false }
                                }

                                SectionTitle {
                                    visible: row.section !== ""
                                    text: row.section
                                    topPadding: row.index === 0 ? 2 : 10
                                    bottomPadding: 6
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 40
                                    radius: 10
                                    color: row.hot || row.forgetHot || row.prompting ? Theme.lift : "transparent"
                                    Behavior on color { ColorAnimation { duration: 90 } }

                                    Hit {
                                        anchors.fill: parent
                                        enabled: root.actionKind === ""
                                        onEntered: root.hover("net:" + row.ssid)
                                        onClicked: root.activate("net:" + row.ssid)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 6
                                        spacing: 12

                                        Icon {
                                            text: root.wifiIcon(row.strength)
                                            color: row.connected ? Theme.green : Theme.fg
                                            font.pixelSize: 16
                                        }
                                        Label {
                                            Layout.fillWidth: true
                                            text: row.ssid
                                            font.weight: row.connected ? Font.Bold : Font.Medium
                                        }
                                        Label {
                                            visible: text !== ""
                                            font.pixelSize: 12
                                            color: row.busyHere ? Theme.cyan : row.failed ? Theme.red : row.connected ? Theme.green : Theme.muted
                                            text: row.busyHere ? ({ connect: "Connecting…", disconnect: "Disconnecting…", forget: "Forgetting…" })[root.actionKind]
                                                : row.failed ? root.failureText
                                                : row.connected ? "Connected" : ""
                                        }
                                        // forget (saved networks) or lock (needs a password)
                                        Item {
                                            implicitWidth: 28
                                            implicitHeight: 28
                                            visible: !row.busyHere && !row.connected && (row.canForget ? (row.hot || row.forgetHot) : !row.open && !row.known)
                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 8
                                                color: row.forgetHot ? Theme.alpha(Theme.red, 0.2) : "transparent"
                                            }
                                            Icon {
                                                anchors.centerIn: parent
                                                text: row.canForget ? "󰅙" : "󰌾"
                                                color: row.canForget ? (row.forgetHot ? Theme.red : Theme.muted) : Theme.faint
                                                font.pixelSize: row.canForget ? 15 : 13
                                            }
                                            Hit {
                                                anchors.fill: parent
                                                enabled: row.canForget
                                                onEntered: root.hover("forget:" + row.ssid)
                                                onClicked: root.activate("forget:" + row.ssid)
                                            }
                                        }
                                    }
                                }

                                // inline password (and identity for WPA Enterprise)
                                ColumnLayout {
                                    visible: row.prompting
                                    width: parent.width
                                    spacing: 6
                                    Item { implicitHeight: 2 }
                                    Field {
                                        id: idField
                                        visible: row.enterprise
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 6
                                        Layout.rightMargin: 6
                                        placeholder: "Identity (user@domain)"
                                        onAccepted: pwField.input.forceActiveFocus()
                                        onTabbed: pwField.input.forceActiveFocus()
                                        onCancelled: root.cancelPrompt()
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.leftMargin: 6
                                        Layout.rightMargin: 6
                                        spacing: 6
                                        Field {
                                            id: pwField
                                            Layout.fillWidth: true
                                            secret: true
                                            placeholder: "Passphrase"
                                            onAccepted: if (text) root.connect(row.ssid, text, row.enterprise ? idField.text : "")
                                            onTabbed: if (row.enterprise) idField.input.forceActiveFocus()
                                            onCancelled: root.cancelPrompt()
                                        }
                                        IconButton {
                                            implicitHeight: 34
                                            implicitWidth: 34
                                            glyph: pwField.reveal ? "󰈉" : "󰈈"
                                            tint: Theme.muted
                                            hot: revealHit.hovered
                                            onActivated: pwField.reveal = !pwField.reveal
                                            HoverHandler { id: revealHit }
                                        }
                                        Pill {
                                            implicitWidth: 84
                                            implicitHeight: 34
                                            label: row.busyHere ? "…" : "Connect"
                                            selected: true
                                            onActivated: if (pwField.text) root.connect(row.ssid, pwField.text, row.enterprise ? idField.text : "")
                                        }
                                    }
                                    Item { implicitHeight: 6 }
                                }
                            }
                        }
                    }
                }

                // ── share (QR) view ──────────────────────────────────
                ColumnLayout {
                    visible: root.view === "qr"
                    Layout.fillWidth: true
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        IconButton { glyph: "󰁍"; hot: backQr.hovered; onActivated: root.back(); HoverHandler { id: backQr } }
                        Label { Layout.fillWidth: true; text: "Share Wi-Fi"; font.pixelSize: 15; font.weight: Font.Bold }
                    }

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 232
                        implicitHeight: 232
                        radius: 16
                        color: "white"
                        Image {
                            anchors.fill: parent
                            anchors.margins: 12
                            source: root.qr.path ? "file://" + root.qr.path : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: false
                            cache: false
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.qr.ssid || ""
                        font.pixelSize: 15
                        font.weight: Font.Bold
                    }
                    Label {
                        Layout.fillWidth: true
                        Layout.topMargin: -8
                        horizontalAlignment: Text.AlignHCenter
                        text: "Point a phone camera at the code to join"
                        color: Theme.muted
                        font.pixelSize: 12
                    }

                    Rectangle {
                        visible: !!root.qr.password
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 10
                        color: Theme.field
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 4
                            spacing: 2
                            Label { text: "Password"; color: Theme.muted; font.pixelSize: 12 }
                            Label {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                rightPadding: 6
                                text: root.qrReveal ? (root.qr.password || "") : "•".repeat(Math.min(14, (root.qr.password || "").length))
                                font.weight: Font.DemiBold
                            }
                            IconButton {
                                glyph: root.qrReveal ? "󰈉" : "󰈈"
                                tint: Theme.muted
                                hot: eyeQr.hovered
                                onActivated: root.qrReveal = !root.qrReveal
                                HoverHandler { id: eyeQr }
                            }
                            IconButton {
                                glyph: "󰆏"
                                tint: Theme.muted
                                hot: copyQr.hovered
                                onActivated: root.copy(root.qr.password, "password")
                                HoverHandler { id: copyQr }
                            }
                        }
                    }
                }

                // ── speed test view ──────────────────────────────────
                ColumnLayout {
                    visible: root.view === "speed"
                    Layout.fillWidth: true
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        IconButton { glyph: "󰁍"; hot: backSp.hovered; onActivated: root.back(); HoverHandler { id: backSp } }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            Label { text: "Speed test"; font.pixelSize: 15; font.weight: Font.Bold }
                            Label {
                                Layout.fillWidth: true
                                font.pixelSize: 12
                                color: root.speedError ? Theme.red : Theme.muted
                                text: root.speedError ? root.speedError
                                    : root.speedPhase === "down" ? "Measuring download…"
                                    : root.speedPhase === "up" ? "Measuring upload…"
                                    : "Done  ·  " + (root.kind === "wifi" ? root.status.ssid : "Ethernet")
                            }
                        }
                        Pill {
                            visible: !root.speedRunning
                            implicitWidth: 96
                            label: "Run again"
                            hot: againHit.hovered
                            onActivated: root.startSpeed()
                            HoverHandler { id: againHit }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        spacing: 0
                        Dial {
                            Layout.fillWidth: true
                            label: "DOWNLOAD"
                            rate: root.speedDown
                            active: root.speedPhase === "down"
                            done: root.speedDownDone
                        }
                        Dial {
                            Layout.fillWidth: true
                            label: "UPLOAD"
                            rate: root.speedUp
                            active: root.speedPhase === "up"
                            done: root.speedUpDone
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 3
                        radius: 2
                        color: Theme.lift
                        opacity: root.speedRunning ? 1 : 0
                        Rectangle {
                            height: parent.height
                            radius: 2
                            width: parent.width * root.speedProgress
                            color: Theme.cyan
                            Behavior on width { NumberAnimation { duration: 240 } }
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Measured against speed.cloudflare.com  ·  Ping " + (root.hasPing && root.pingAvg >= 0 ? root.pingAvg.toFixed(0) + " ms" : "--")
                        color: Theme.faint
                        font.pixelSize: 11
                    }
                }

                // footer: hint for the highlighted control, or a short message
                Label {
                    id: footer
                    Layout.fillWidth: true
                    Layout.topMargin: -2
                    font.pixelSize: 11
                    color: root.toastText ? root.toastColor : Theme.faint
                    text: root.toastText ? root.toastText
                        : root.view === "qr" ? "Space show password   c copy   Esc back"
                        : root.view === "speed" ? (root.speedRunning ? "Esc stop" : "r run again   Esc back")
                        : root.hint(root.cursor)
                }
            }
        }
    }
}
