import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Font picker (SUPER + CTRL + F), like Omarchy 4.5's font menu. Every
// monospace Nerd Font, each shown in itself; Enter / click switches the font
// of the terminal, bar, cards, dock, titlebars and lock screen with
// ~/.local/bin/theme and closes. Keys: j k or arrows, Enter, Esc.
Scope {
    id: root

    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"
    readonly property string themeCmd: Quickshell.env("HOME") + "/.local/bin/theme"
    readonly property string sample: "0O 1lI {} => != -> <= ++ 󰣇  "

    property bool opened: false
    property real closedAt: 0
    property var fonts: []
    property string current: ""
    property int index: 0
    property bool applying: false
    property string error: ""
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    readonly property int rowHeight: 58

    function openOn(name) {
        for (const s of Quickshell.screens) if (s.name === name) root.targetScreen = s
        root.error = ""
        root.applying = false
        listProc.running = true
        root.opened = true
        Qt.callLater(() => keys.forceActiveFocus())
    }
    function open() { openOn(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") }
    function close() {
        if (!root.opened) return
        root.opened = false
        root.closedAt = Date.now()
    }
    function toggle() {
        if (root.opened) close()
        else if (Date.now() - root.closedAt > 300) open()
    }
    function move(d) {
        if (!root.fonts.length) return
        root.index = Math.max(0, Math.min(root.fonts.length - 1, root.index + d))
        list.positionViewAtIndex(root.index, ListView.Contain)
    }
    function apply(i) {
        if (root.applying || i < 0 || i >= root.fonts.length) return
        root.index = i
        if (root.fonts[i] === root.current) { root.close(); return }
        root.applying = true
        root.error = ""
        setProc.command = [root.themeCmd, "font", "set", root.fonts[i]]
        setProc.running = true
    }

    Process {
        id: listProc
        command: [root.themeCmd, "font", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.fonts = d.fonts || []
                    root.current = d.current || ""
                    const i = root.fonts.indexOf(root.current)
                    root.index = i >= 0 ? i : 0
                    Qt.callLater(() => list.positionViewAtIndex(root.index, ListView.Center))
                } catch (e) {
                    root.error = "Couldn't read the fonts (theme font list --json)"
                }
            }
        }
    }

    Process {
        id: setProc
        stderr: StdioCollector { id: setErr }
        onExited: code => {
            root.applying = false
            if (code === 0) {
                root.current = root.fonts[root.index]
                root.close()
            } else {
                root.error = setErr.text.trim() || "Couldn't switch the font"
            }
        }
    }

    IpcHandler {
        target: "fonts"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function openOn(screen: string): void { root.openOn(screen) }   // tests
        function nav(d: int): void { root.move(d) }                     // tests
    }

    PanelWindow {
        id: win
        visible: root.opened
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.alpha(Theme.bgDark, 0.55)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "fontpicker"
        WlrLayershell.keyboardFocus: root.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, 560)
            height: Math.min(parent.height - 96, 18 + 22 + 14 + Math.min(root.fonts.length || 8, 8) * root.rowHeight + 14 + 14 + 18)
            radius: 18
            color: Theme.ink
            border.width: 1
            border.color: Theme.edge
            opacity: root.opened ? 1 : 0
            scale: root.opened ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }   // clicks on the card don't close it

            Item {
                id: keys
                focus: true
                Keys.onPressed: e => {
                    const k = e.key
                    if (k === Qt.Key_Escape || k === Qt.Key_Q) root.close()
                    else if (k === Qt.Key_K || k === Qt.Key_Up) root.move(-1)
                    else if (k === Qt.Key_J || k === Qt.Key_Down || k === Qt.Key_Tab) root.move(1)
                    else if (k === Qt.Key_PageUp) root.move(-6)
                    else if (k === Qt.Key_PageDown) root.move(6)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.apply(root.index)
                    else return
                    e.accepted = true
                }
            }

            Row {
                id: header
                x: 18
                y: 18
                spacing: 10
                Text {
                    text: "󰛖"
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 18
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Font"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.fonts.length ? root.fonts.length + " fonts  ·  terminal, bar, dock, cards, lock screen" : "Loading…"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

            ListView {
                id: list
                x: 12
                y: header.y + 22 + 14
                width: card.width - 24
                height: card.height - y - 14 - 14 - 18
                clip: true
                model: root.fonts
                boundsBehavior: Flickable.StopAtBounds
                spacing: 0

                delegate: Rectangle {
                    id: row
                    required property string modelData
                    required property int index
                    readonly property bool selected: index === root.index
                    readonly property bool isCurrent: modelData === root.current
                    width: list.width
                    height: root.rowHeight
                    radius: 12
                    color: row.selected ? Theme.lift : "transparent"
                    border.width: row.selected ? 1 : 0
                    border.color: Theme.alpha(Theme.accent, 0.45)

                    Column {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 60
                        spacing: 3
                        Text {
                            width: parent.width
                            text: row.modelData.replace(/ Nerd Font$/, "")
                            color: row.selected ? Theme.fgBright : Theme.fg
                            font.family: row.modelData
                            font.pixelSize: 16
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: root.sample
                            color: Theme.muted
                            font.family: row.modelData
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        visible: row.isCurrent || (root.applying && row.selected)
                        text: root.applying && row.selected ? "…" : "󰄬"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 16
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.index = row.index
                        onClicked: root.apply(row.index)
                    }
                }
            }

            Text {
                x: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                width: card.width - 36
                text: root.error ? root.error : "j k move   Enter apply   Esc close   ·   themes: Super Ctrl T"
                color: root.error ? Theme.red : Theme.faint
                font.family: Theme.font
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }
}
