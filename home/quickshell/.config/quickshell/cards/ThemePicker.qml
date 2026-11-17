import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

// Theme picker (SUPER + CTRL + T), like Omarchy 4.5's theme menu. Each theme
// shows its preview, name and palette; Enter / click switches the whole
// desktop with ~/.local/bin/theme (colours, wallpaper, kitty, bar, lock screen,
// GTK and KDE apps) and closes. Keys: h j k l or arrows, Enter, Esc.
Scope {
    id: root

    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"
    readonly property string themeCmd: Quickshell.env("HOME") + "/.local/bin/theme"

    property bool opened: false
    property real closedAt: 0
    property var themes: []
    property string current: ""
    property int index: 0
    property bool applying: false
    property string error: ""
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    readonly property int cell: 236
    readonly property int gap: 12
    // as many tiles as fit the screen, at most 4 a row; rows scroll if needed
    property int screenWidth: 1920
    readonly property int columns: Math.max(1, Math.min(4, themes.length || 4, Math.floor((screenWidth - 64 - 36 + gap) / (cell + gap))))

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
    function move(dx, dy) {
        if (!root.themes.length) return
        let i = root.index + dx + dy * root.columns
        if (dx !== 0) i = Math.max(0, Math.min(root.themes.length - 1, i))
        else if (i < 0 || i >= root.themes.length) return
        root.index = i
        const item = grid.children[i]
        if (item) {
            if (item.y < flick.contentY) flick.contentY = item.y
            else if (item.y + item.height > flick.contentY + flick.height)
                flick.contentY = item.y + item.height - flick.height
        }
    }
    function apply(i) {
        if (root.applying || i < 0 || i >= root.themes.length) return
        root.index = i
        if (root.themes[i].name === root.current) { root.close(); return }
        root.applying = true
        root.error = ""
        setProc.command = [root.themeCmd, "set", root.themes[i].name]
        setProc.running = true
    }

    Process {
        id: listProc
        command: [root.themeCmd, "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.themes = d.themes || []
                    root.current = d.current || ""
                    const i = root.themes.findIndex(t => t.name === root.current)
                    root.index = i >= 0 ? i : 0
                } catch (e) {
                    root.error = "Couldn't read the themes (theme list --json)"
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
                root.current = root.themes[root.index].name
                root.close()
            } else {
                root.error = setErr.text.trim() || "Couldn't switch the theme"
            }
        }
    }

    IpcHandler {
        target: "themes"
        function toggle(): void { root.toggle() }
        function open(): void { root.open() }
        function close(): void { root.close() }
        function openOn(screen: string): void { root.openOn(screen) }   // tests
        function nav(dx: int, dy: int): void { root.move(dx, dy) }      // tests
    }

    component Label: Text {
        color: Theme.fg
        font.family: Theme.font
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    PanelWindow {
        id: win
        visible: root.opened
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.alpha(Theme.bgDark, 0.55)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "themepicker"
        WlrLayershell.keyboardFocus: root.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
        onWidthChanged: if (width > 0) root.screenWidth = width

        MouseArea { anchors.fill: parent; onClicked: root.close() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - 64, root.columns * root.cell + (root.columns - 1) * root.gap + 36)
            height: Math.min(parent.height - 96, body.implicitHeight + 36)
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
                    else if (k === Qt.Key_H || k === Qt.Key_Left) root.move(-1, 0)
                    else if (k === Qt.Key_L || k === Qt.Key_Right || k === Qt.Key_Tab) root.move(1, 0)
                    else if (k === Qt.Key_K || k === Qt.Key_Up) root.move(0, -1)
                    else if (k === Qt.Key_J || k === Qt.Key_Down) root.move(0, 1)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.apply(root.index)
                    else return
                    e.accepted = true
                }
            }

            Column {
                id: body
                x: 18
                y: 18
                width: parent.width - 36
                spacing: 14

                Row {
                    spacing: 10
                    Text {
                        text: "󰏘"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label { text: "Theme"; font.pixelSize: 15; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.faint
                        font.pixelSize: 12
                        text: root.themes.length ? root.themes.length + " themes" : "Loading…"
                    }
                }

                Flickable {
                    id: flick
                    width: parent.width
                    height: Math.min(grid.implicitHeight, win.height - 96 - 36 - 60)
                    contentHeight: grid.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                Grid {
                    id: grid
                    columns: root.columns
                    spacing: root.gap

                    Repeater {
                        model: root.themes
                        delegate: Item {
                            id: tile
                            required property var modelData
                            required property int index
                            readonly property bool selected: root.index === index
                            readonly property bool isCurrent: modelData.name === root.current
                            width: root.cell
                            height: root.cell * 9 / 16 + 34

                            Rectangle {
                                id: frame
                                width: parent.width
                                height: parent.width * 9 / 16
                                radius: 13
                                color: "transparent"
                                border.width: tile.selected ? 2 : 1
                                border.color: tile.selected ? Theme.accent : Theme.edge
                                Behavior on border.color { ColorAnimation { duration: 100 } }

                                ClippingRectangle {
                                    anchors.fill: parent
                                    anchors.margins: tile.selected ? 4 : 1
                                    radius: tile.selected ? 9 : 12
                                    color: tile.modelData.colors.background
                                    Behavior on anchors.margins { NumberAnimation { duration: 120 } }
                                    Image {
                                        anchors.fill: parent
                                        source: tile.modelData.preview ? "file://" + tile.modelData.preview : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth: true
                                        opacity: status === Image.Ready ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                    }
                                    // the palette, along the bottom edge
                                    Row {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: 6
                                        Repeater {
                                            model: ["accent", "accent2", "red", "yellow", "green", "blue", "magenta", "cyan"]
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: parent.width / 8
                                                height: 6
                                                color: tile.modelData.colors[modelData]
                                            }
                                        }
                                    }
                                }

                                Rectangle {     // the theme in use now
                                    visible: tile.isCurrent
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 10
                                    width: 24; height: 24; radius: 12
                                    color: Theme.accent
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰄬"
                                        color: Theme.onAccent
                                        font.family: Theme.font
                                        font.pixelSize: 15
                                    }
                                }

                                Rectangle {     // switching
                                    anchors.fill: parent
                                    radius: 13
                                    color: "#99000000"
                                    visible: root.applying && tile.selected
                                    Label { anchors.centerIn: parent; text: "Applying…"; color: "#ffffff" }
                                }
                            }

                            Label {
                                anchors.top: frame.bottom
                                anchors.topMargin: 8
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: tile.modelData.title
                                font.weight: tile.selected ? Font.Bold : Font.Normal
                                color: tile.selected ? Theme.fgBright : Theme.muted
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.index = tile.index
                                onClicked: root.apply(tile.index)
                            }
                        }
                    }
                }
                }

                Label {
                    width: parent.width
                    font.pixelSize: 11
                    color: root.error ? Theme.red : Theme.faint
                    text: root.error ? root.error : "h j k l move   Enter apply   Esc close   ·   fonts: Super Ctrl F   ·   wallpaper: Super Ctrl Space"
                }
            }
        }
    }
}
