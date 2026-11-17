import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// Every keybind (SUPER + K), in config order. Read the config afresh on open;
// release the keyboard and let the card fade before dispatching a chosen bind.
Scope {
    id: root

    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"
    readonly property int rowHeight: 44
    readonly property int sectionHeight: 30

    property bool opened: false
    property real closedAt: 0
    property string filterText: ""
    property int selectedIndex: 0
    property var binds: []
    property var filtered: []
    property bool loading: false
    property bool reloadPending: false
    property string error: ""
    property string pendingRun: ""
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    function rebuild() {
        const words = root.filterText.trim().toLowerCase().split(/\s+/).filter(w => w.length > 0)
        root.filtered = root.binds.filter(bind => {
            const haystack = [bind.description, bind.combo, bind.group].concat(bind.keys).join(" ").toLowerCase()
            return words.every(word => haystack.includes(word))
        })
        root.selectedIndex = 0
        list.positionViewAtBeginning()
    }
    function setFilter(text) {
        root.filterText = text
        root.rebuild()
    }
    function openOn(name) {
        for (const s of Quickshell.screens) if (s.name === name) root.targetScreen = s
        root.pendingRun = ""
        runTimer.stop()
        root.binds = []
        root.setFilter("")
        root.error = ""
        root.loading = true
        root.opened = true
        if (listProc.running) root.reloadPending = true
        else listProc.running = true
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
    function select(delta) {
        if (!root.filtered.length) return
        root.selectedIndex = Math.max(0, Math.min(root.filtered.length - 1, root.selectedIndex + delta))
        list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
    function launch(index) {
        const bind = root.filtered[index]
        if (!root.opened || !bind || !bind.run) return
        root.pendingRun = bind.run
        root.close()
        runTimer.restart()
    }

    Process {
        id: listProc
        command: ["lua", Quickshell.env("HOME") + "/.config/hypr/scripts/keybinds.lua", "--json"]
        stdout: StdioCollector { id: bindOutput }
        stderr: StdioCollector { id: bindError }
        onExited: code => {
            if (root.reloadPending) {
                root.reloadPending = false
                if (root.opened) {
                    Qt.callLater(() => listProc.running = true)
                    return
                }
            }
            root.loading = false
            if (code !== 0) {
                root.error = bindError.text.trim() || "Couldn't read the keybinds"
                return
            }
            try {
                const data = JSON.parse(bindOutput.text)
                if (!Array.isArray(data.binds)) throw new Error("Missing binds list")
                root.binds = data.binds
                root.rebuild()
            } catch (e) {
                root.error = "Couldn't read keybinds.lua --json"
            }
        }
    }

    Timer {
        id: runTimer
        interval: 200
        onTriggered: {
            const run = root.pendingRun
            root.pendingRun = ""
            if (run) Quickshell.execDetached(["hyprctl", "dispatch", run])
        }
    }

    IpcHandler {
        target: "keys"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function openOn(screen: string): void { root.openOn(screen) }   // tests
        function filter(text: string): void { root.setFilter(text) }   // tests
        function nav(d: int): void { root.select(d) }                  // tests
    }

    PanelWindow {
        id: panel
        visible: root.opened || card.opacity > 0
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.alpha(Theme.bgDark, 0.55)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "keyscard"
        WlrLayershell.keyboardFocus: root.testMode || !root.opened ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, 760)
            height: Math.min(parent.height - 96, 620)
            radius: 18
            color: Theme.ink
            border.width: 1
            border.color: Theme.edge
            opacity: root.opened ? 1 : 0
            scale: root.opened ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
            }

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    const k = event.key
                    const page = Math.max(1, Math.floor(list.height / root.rowHeight) - 1)
                    if (k === Qt.Key_Escape) {
                        if (root.filterText) root.setFilter("")
                        else root.close()
                    } else if (k === Qt.Key_Backspace) {
                        root.setFilter(Array.from(root.filterText).slice(0, -1).join(""))
                    } else if (k === Qt.Key_Up) {
                        root.select(-1)
                    } else if (k === Qt.Key_Down) {
                        root.select(1)
                    } else if (k === Qt.Key_PageUp) {
                        root.select(-page)
                    } else if (k === Qt.Key_PageDown) {
                        root.select(page)
                    } else if (k === Qt.Key_Home) {
                        root.select(-root.filtered.length)
                    } else if (k === Qt.Key_End) {
                        root.select(root.filtered.length)
                    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                        root.launch(root.selectedIndex)
                    } else if (event.text && !/[\x00-\x1f\x7f]/.test(event.text)
                               && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                        root.setFilter(root.filterText + event.text)
                    } else {
                        return
                    }
                    event.accepted = true
                }
            }

            Row {
                id: header
                x: 18
                y: 18
                spacing: 10
                Text {
                    text: "󰌌"
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 18
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "Keybinds"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.loading ? "Loading…" : root.filtered.length + (root.filterText ? " / " + root.binds.length : "") + " binds"
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                id: search
                x: 18
                y: header.y + 22 + 14
                width: card.width - 36
                height: 44
                radius: 12
                color: Theme.field
                border.width: 1
                border.color: root.filterText ? Theme.alpha(Theme.accent, 0.5) : "transparent"
                Text {
                    id: glass
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    color: root.filterText ? Theme.accent : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 18
                }
                Text {
                    anchors.left: glass.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.filterText || "Search descriptions, keys or groups"
                    textFormat: Text.PlainText
                    color: root.filterText ? Theme.fg : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }
            }

            ListView {
                id: list
                x: 12
                y: search.y + search.height + 10
                width: card.width - 24
                height: card.height - y - 44
                clip: true
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds

                // Headers belong to the following bind, so filtering keeps
                // sections in config order without separate selectable rows.
                delegate: Item {
                    id: entry
                    required property var modelData
                    required property int index
                    readonly property bool startsGroup: index === 0 || !root.filtered[index - 1] || root.filtered[index - 1].group !== modelData.group
                    width: list.width
                    height: root.rowHeight + (startsGroup ? root.sectionHeight : 0)

                    Text {
                        x: 12
                        y: 10
                        visible: entry.startsGroup
                        text: entry.modelData.group
                        textFormat: Text.PlainText
                        color: Theme.muted
                        font.family: Theme.font
                        font.pixelSize: 11
                    }

                    Rectangle {
                        id: row
                        readonly property bool selected: entry.index === root.selectedIndex
                        y: entry.startsGroup ? root.sectionHeight : 0
                        width: list.width
                        height: root.rowHeight
                        radius: 12
                        color: selected ? Theme.lift : "transparent"
                        border.width: selected ? 1 : 0
                        border.color: Theme.alpha(Theme.accent, 0.45)

                        Row {
                            id: chips
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Repeater {
                                model: entry.modelData.keys
                                delegate: Row {
                                    id: chip
                                    required property string modelData
                                    required property int index
                                    spacing: 5
                                    Text {
                                        visible: chip.index > 0
                                        text: "+"
                                        color: Theme.faint
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Rectangle {
                                        width: cap.implicitWidth + 14
                                        height: 26
                                        radius: 6
                                        color: Theme.field
                                        border.width: 1
                                        border.color: Theme.edge
                                        Text {
                                            id: cap
                                            anchors.centerIn: parent
                                            text: chip.modelData
                                            textFormat: Text.PlainText
                                            color: Theme.accent
                                            font.family: Theme.font
                                            font.pixelSize: 12
                                            font.weight: Font.Bold
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            x: chips.x + chips.width + 16
                            width: Math.max(0, runHint.x - x - 12)
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.description
                            textFormat: Text.PlainText
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Text {
                            id: runHint
                            anchors.right: parent.right
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            visible: row.selected && !!entry.modelData.run
                            width: visible ? implicitWidth : 0
                            text: "↵ run"
                            color: Theme.faint
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: entry.modelData.run ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onEntered: root.selectedIndex = entry.index
                            onClicked: root.launch(entry.index)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: list
                width: list.width - 24
                visible: !root.filtered.length
                text: root.error || (root.loading ? "Loading keybinds…" : "No keybinds match “" + root.filterText + "”")
                textFormat: Text.PlainText
                color: root.error ? Theme.red : Theme.muted
                font.family: Theme.font
                font.pixelSize: 14
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Text {
                x: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                width: card.width - 36
                text: "type to search   ↑ ↓ move   Enter run   Esc close"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
    }
}
