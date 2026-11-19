import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

// On-screen display for the brightness and volume keys (option A): a pill
// just above the dock on the focused monitor, shown for 1.5 s after each key press.
// osd.sh changes the level and calls  show(kind, value, muted)  through IPC:
//   qs ipc -c cards call osd pop sound 45 false
// It takes no input (the mask is empty), so it never blocks the desktop.
Scope {
    id: root

    property bool shown: false
    property string kind: "sound"   // "sound" or "light"
    property int value: 0
    property bool muted: false
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    readonly property string label: kind === "light" ? "Brightness" : (muted ? "Muted" : "Volume")
    // Nerd Font codepoints, the same ones the bar uses (sun, speaker, muted speaker)
    readonly property string glyph: kind === "light" ? String.fromCodePoint(0xF00E0)
        : (muted || value === 0 ? String.fromCodePoint(0xF075F) : String.fromCodePoint(0xF057E))

    function show(k, v, m) {
        root.kind = k === "light" ? "light" : "sound"
        root.value = Math.max(0, Math.min(100, v))
        root.muted = m
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
        for (const s of Quickshell.screens) if (s.name === name) root.targetScreen = s
        root.shown = true
        hideTimer.restart()
    }
    function hide() { root.shown = false }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: root.hide()
    }

    IpcHandler {
        target: "osd"
        function pop(kind: string, value: int, muted: bool): void { root.show(kind, value, muted) }
        function hide(): void { root.hide() }
    }

    PanelWindow {
        id: win
        // Stays mapped so the slide-in can run from its start position. With
        // nothing shown the mask is empty, so it takes no input and draws nothing.
        visible: true
        screen: root.targetScreen
        color: "transparent"

        WlrLayershell.namespace: "osd"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        // Resting pill bottom = 82 px above the screen bottom: the dock island
        // (DockWindow.qml) is 66 px tall and 6 px off the edge, so its top is at 72 px;
        // this leaves 10 px between them. The window holds 28 px more below the pill
        // for the slide-in, which starts 28 px lower and rises into place.
        anchors { bottom: true; left: true; right: true }
        margins { bottom: 54 }
        implicitHeight: pill.height + 28

        mask: Region {
            item: root.shown ? pill : null
        }

        Rectangle {
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            width: 340
            height: 50
            radius: height / 2
            color: Theme.ink
            border.color: Theme.edge
            border.width: 1

            // Rises from below into its resting place, and sinks back on hide.
            y: root.shown ? 0 : 28
            opacity: root.shown ? 1 : 0
            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 16
                spacing: 14

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    text: root.glyph
                    color: root.muted ? Theme.faint : Theme.accent
                    font.family: Theme.icons
                    font.pixelSize: 18
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 84
                    text: root.label
                    color: Theme.fgBright
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Item {
                    id: meter
                    anchors.verticalCenter: parent.verticalCenter
                    width: 118
                    height: 4

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Theme.alpha(Theme.fg, 0.13)
                    }
                    Rectangle {
                        id: fill
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        radius: 2
                        width: meter.width * (root.muted ? 0 : root.value) / 100
                        color: root.muted ? Theme.faint : Theme.accent
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    }
                }

                Text {
                    id: valueText
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    text: root.muted ? "off" : root.value + "%"
                    color: root.muted ? Theme.red : Theme.fgBright
                    font.family: Theme.sans
                    font.pixelSize: 13
                    font.weight: Font.Bold
                }
            }
        }
    }
}
