// Wallpaper picker (SUPER + CTRL + SPACE), like Omarchy's background switcher.
// A grid of the current theme's wallpapers, then every image in
// ~/Pictures/Wallpapers, on the focused screen.
// Enter / click sets it on every screen and closes; the choice is kept for
// the next login (wallctl.py). Started by ./wallpicker, quits when done.
//
// Keys: h j k l or arrows move, Enter / Space set, o opens the folder, Esc closes.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets

ShellRoot {
    id: root

    readonly property string wallctl: decodeURIComponent(Qt.resolvedUrl("wallctl.py").toString().replace("file://", ""))
    // WALLPICK_SCREEN=<output> WALLPICK_TEST=1: open on a hidden output without taking the keyboard.
    readonly property bool testMode: Quickshell.env("WALLPICK_TEST") === "1"
    readonly property string screenName: Quickshell.env("WALLPICK_SCREEN")
        || (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")

    property var items: []
    property string current: ""
    property string folder: ""
    property string themeTitle: ""
    property int index: 0
    property bool loaded: false
    property bool applying: false
    property string error: ""

    // as many 248 px tiles as fit the screen, at most 4
    property int screenWidth: 1920
    readonly property int columns: Math.max(1, Math.min(4, items.length, Math.floor((screenWidth - 64 - 36 + 12) / (248 + 12))))

    function quit() { Qt.quit() }

    function apply(i) {
        if (applying || i < 0 || i >= items.length) return
        applying = true
        index = i
        setProc.command = [wallctl, "set", items[i].path]
        setProc.running = true
    }

    function move(dx, dy) {
        if (!items.length) return
        let i = index + dx + dy * columns
        if (dx !== 0) i = Math.max(0, Math.min(items.length - 1, i))
        else if (i < 0 || i >= items.length) return
        index = i
        const item = grid.children[i]
        if (item) {
            if (item.y < flick.contentY) flick.contentY = item.y
            else if (item.y + item.height > flick.contentY + flick.height)
                flick.contentY = item.y + item.height - flick.height
        }
    }

    Process {
        running: true
        command: [root.wallctl, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {}
                try { d = JSON.parse(text) } catch (e) { root.error = "Couldn't read the wallpapers"; return }
                root.items = d.items || []
                root.current = d.current || ""
                root.folder = d.dir || ""
                root.themeTitle = d.theme || ""
                const i = root.items.findIndex(it => it.path === root.current)
                root.index = i >= 0 ? i : 0
                root.loaded = true
            }
        }
    }

    Process {
        id: setProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {}
                try { d = JSON.parse(text) } catch (e) {}
                if (d.ok) root.quit()
                else { root.applying = false; root.error = d.error || "Couldn't set the wallpaper" }
            }
        }
    }

    component Label: Text {
        color: Theme.fg
        font.family: Theme.sans
        font.pixelSize: 13
        font.weight: Font.Medium
        elide: Text.ElideRight
    }

    PanelWindow {
        id: win
        screen: {
            for (const s of Quickshell.screens) if (s.name === root.screenName) return s
            return Quickshell.screens[0]
        }
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.alpha(Theme.bgDark, 0.55)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "wallpicker"
        onWidthChanged: if (width > 0) root.screenWidth = width
        WlrLayershell.keyboardFocus: root.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        // click outside the card closes
        MouseArea { anchors.fill: parent; onClicked: root.quit() }

        Rectangle {
            id: card
            anchors.centerIn: parent
            readonly property int cell: 248
            readonly property int gap: 12
            width: Math.min(parent.width - 64, root.columns * cell + (root.columns - 1) * gap + 36)
            height: Math.min(parent.height - 96, body.implicitHeight + 36)
            radius: 18
            color: Theme.ink
            border.width: 1
            border.color: Theme.edge
            opacity: 0
            scale: 0.97
            Component.onCompleted: { opacity = 1; scale = 1 }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            MouseArea { anchors.fill: parent }   // clicks on the card don't close

            Item {
                id: keys
                focus: true
                Component.onCompleted: forceActiveFocus()
                Keys.onPressed: e => {
                    const k = e.key
                    if (k === Qt.Key_Escape || k === Qt.Key_Q) root.quit()
                    else if (k === Qt.Key_H || k === Qt.Key_Left) root.move(-1, 0)
                    else if (k === Qt.Key_L || k === Qt.Key_Right || k === Qt.Key_Tab) root.move(1, 0)
                    else if (k === Qt.Key_K || k === Qt.Key_Up) root.move(0, -1)
                    else if (k === Qt.Key_J || k === Qt.Key_Down) root.move(0, 1)
                    else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.apply(root.index)
                    else if (k === Qt.Key_O) { Quickshell.execDetached(["xdg-open", root.folder]); root.quit() }
                    else return
                    e.accepted = true
                }
            }

            ColumnLayout {
                id: body
                x: 18
                y: 18
                width: parent.width - 36
                height: parent.height - 36
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    Text {
                        text: "󰸉"
                        color: Theme.cyan
                        font.family: Theme.icons
                        font.pixelSize: 18
                    }
                    Label { text: "Wallpaper"; font.pixelSize: 15; font.weight: Font.Bold }
                    Label {
                        Layout.fillWidth: true
                        color: Theme.faint
                        font.pixelSize: 12
                        text: root.loaded ? root.items.length + (root.items.length === 1 ? " image" : " images") + "  ·  " + (root.themeTitle ? root.themeTitle + " + " : "") + root.folder.replace(/^\/home\/[^/]+/, "~") : "Loading…"
                    }
                }

                Flickable {
                    id: flick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: grid.implicitHeight
                    contentHeight: grid.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Grid {
                        id: grid
                        columns: root.columns
                        spacing: card.gap

                        Repeater {
                            model: root.items
                            delegate: Item {
                                id: tile
                                required property var modelData
                                required property int index
                                readonly property bool selected: root.index === index
                                readonly property bool isCurrent: modelData.path === root.current
                                width: card.cell
                                height: card.cell * 9 / 16 + 30

                                Rectangle {
                                    id: frame
                                    width: parent.width
                                    height: parent.width * 9 / 16
                                    radius: 13
                                    color: "transparent"
                                    border.width: tile.selected ? 2 : 1
                                    border.color: tile.selected ? Theme.cyan : Theme.edge
                                    Behavior on border.color { ColorAnimation { duration: 100 } }

                                    ClippingRectangle {
                                        anchors.fill: parent
                                        anchors.margins: tile.selected ? 4 : 1
                                        radius: tile.selected ? 9 : 12
                                        color: Theme.field
                                        Behavior on anchors.margins { NumberAnimation { duration: 120 } }
                                        Image {
                                            anchors.fill: parent
                                            source: tile.modelData.thumb ? "file://" + tile.modelData.thumb : ""
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            smooth: true
                                            opacity: status === Image.Ready ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: 160 } }
                                        }
                                    }

                                    // the wallpaper on screen now
                                    Rectangle {
                                        visible: tile.isCurrent
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: 10
                                        width: 24; height: 24; radius: 12
                                        color: Theme.green
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰄬"
                                            color: Theme.onAccent
                                            font.family: Theme.icons
                                            font.pixelSize: 15
                                        }
                                    }

                                    // applying spinner-ish dim
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 13
                                        color: "#99000000"
                                        visible: root.applying && tile.selected
                                        Label { anchors.centerIn: parent; text: "Setting…"; color: Theme.cyan }
                                    }
                                }

                                Label {
                                    anchors.top: frame.bottom
                                    anchors.topMargin: 7
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: tile.modelData.name
                                    font.pixelSize: 12
                                    color: tile.selected ? Theme.fg : Theme.muted
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
                    visible: root.loaded && root.items.length === 0
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    color: Theme.muted
                    text: "No images yet. Put some in " + root.folder.replace(/^\/home\/[^/]+/, "~")
                }

                Label {
                    Layout.fillWidth: true
                    font.pixelSize: 11
                    color: root.error ? Theme.red : Theme.faint
                    text: root.error ? root.error : "h j k l move   Enter set   o open folder   Esc close"
                }
            }
        }
    }
}
