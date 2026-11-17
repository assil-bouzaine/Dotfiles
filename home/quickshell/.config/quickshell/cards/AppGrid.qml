import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Every app on one grid (SUPER + ALT + SPACE, or the dock's first button), like
// Omarchy 4.5's app grid. Type to search, arrows move, Enter starts the app,
// right-click keeps it in the dock. Esc clears the search, then closes.
Scope {
    id: root

    property var dock: null
    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"

    property bool opened: false
    property real closedAt: 0
    property string filterText: ""
    property int selectedIndex: 0
    property var apps: []
    property var targetScreen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
    property var menuEntry: null
    property point menuPoint

    readonly property int iconSize: 52
    readonly property int cellWidth: 126
    readonly property int cellHeight: 120
    readonly property int maxColumns: 7
    readonly property int visibleRows: 4

    // A match on the start of the name beats one inside it, which beats the
    // generic name, keywords or id.
    function score(entry, q) {
        const name = String(entry.name || "").toLowerCase()
        if (name.startsWith(q)) return 100
        if (name.split(/[\s\-_.]+/).some(w => w.startsWith(q))) return 80
        if (name.includes(q)) return 60
        const extra = [entry.genericName, entry.comment, entry.id].concat(entry.keywords || []).join(" ").toLowerCase()
        return extra.includes(q) ? 30 : 0
    }

    function rebuild() {
        const seen = {}
        let list = []
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay || seen[e.id]) continue
            seen[e.id] = true
            list.push(e)
        }
        const q = root.filterText.trim().toLowerCase()
        const byName = (a, b) => String(a.name).toLowerCase().localeCompare(String(b.name).toLowerCase())
        if (q) {
            list = list.map(e => ({ e: e, s: root.score(e, q) }))
                       .filter(x => x.s > 0)
                       .sort((a, b) => b.s - a.s || byName(a.e, b.e))
                       .map(x => x.e)
        } else {
            list.sort(byName)
        }
        root.apps = list
        root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, list.length - 1))
        grid.positionViewAtBeginning()
    }

    function openOn(name) {
        for (const s of Quickshell.screens) if (s.name === name) root.targetScreen = s
        root.filterText = ""
        root.selectedIndex = 0
        root.menuEntry = null
        root.rebuild()
        root.opened = true
        Qt.callLater(() => keys.forceActiveFocus())
    }
    function open() { openOn(Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "") }
    function close() {
        if (!root.opened) return
        root.opened = false
        root.menuEntry = null
        root.closedAt = Date.now()
    }
    function toggle() {
        if (root.opened) close()
        else if (Date.now() - root.closedAt > 300) open()
    }
    function setFilter(text) {
        root.filterText = text
        root.selectedIndex = 0
        root.rebuild()
    }
    function select(delta) {
        if (root.apps.length === 0) return
        root.selectedIndex = Math.max(0, Math.min(root.apps.length - 1, root.selectedIndex + delta))
        grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
    }
    function launch(index) {
        const entry = root.apps[index]
        if (!entry) return
        root.close()
        if (root.dock) root.dock.launchEntry(entry)
        else entry.execute()
    }

    PanelWindow {
        id: panel
        visible: root.opened
        screen: root.targetScreen
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: Theme.alpha(Theme.bgDark, 0.55)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "dock-apps"
        WlrLayershell.keyboardFocus: root.testMode ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive

        readonly property int columns: Math.max(1, Math.min(root.maxColumns, Math.floor((width - 120) / root.cellWidth)))

        // click outside the card closes (or closes the menu first)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: {
                if (root.menuEntry) root.menuEntry = null
                else root.close()
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: panel.columns * root.cellWidth + 36
            height: Math.min(panel.height - 80, 18 + 44 + 14 + root.visibleRows * root.cellHeight + 18 + 26)
            radius: 18
            color: Theme.ink
            border.width: 1
            border.color: Theme.edge
            opacity: root.opened ? 1 : 0
            scale: root.opened ? 1 : 0.97
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            MouseArea {     // clicks on the card don't close it
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: root.menuEntry = null
            }

            Item {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    const k = event.key
                    if (k === Qt.Key_Escape) {
                        if (root.menuEntry) root.menuEntry = null
                        else if (root.filterText) root.setFilter("")
                        else root.close()
                    } else if (k === Qt.Key_Backspace) {
                        if (root.filterText) root.setFilter(root.filterText.slice(0, -1))
                    } else if (k === Qt.Key_Left) {
                        root.select(-1)
                    } else if (k === Qt.Key_Right || k === Qt.Key_Tab) {
                        root.select(1)
                    } else if (k === Qt.Key_Up) {
                        root.select(-panel.columns)
                    } else if (k === Qt.Key_Down) {
                        root.select(panel.columns)
                    } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                        root.launch(root.selectedIndex)
                    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
                        root.setFilter(root.filterText + event.text)
                    } else {
                        return
                    }
                    event.accepted = true
                }
            }

            // search field
            Rectangle {
                id: search
                x: 18
                y: 18
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
                    anchors.right: count.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.filterText || "Search apps"
                    color: root.filterText ? Theme.fg : Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 15
                    elide: Text.ElideRight
                }
                Text {
                    id: count
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.apps.length + (root.apps.length === 1 ? " app" : " apps")
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }

            GridView {
                id: grid
                x: 18
                y: search.y + search.height + 14
                width: panel.columns * root.cellWidth
                height: card.height - y - 18 - 26
                model: root.apps
                clip: true
                cellWidth: root.cellWidth
                cellHeight: root.cellHeight
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: cell
                    required property int index
                    required property var modelData
                    readonly property bool selected: index === root.selectedIndex
                    width: root.cellWidth
                    height: root.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 14
                        color: cell.selected ? Theme.lift : "transparent"
                        border.width: cell.selected ? 1 : 0
                        border.color: Theme.alpha(Theme.accent, 0.45)
                    }
                    Image {
                        id: icon
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 14
                        width: root.iconSize
                        height: root.iconSize
                        sourceSize: Qt.size(root.iconSize * 2, root.iconSize * 2)
                        source: root.dock ? root.dock.iconSource(cell.modelData.icon) : ""
                        fillMode: Image.PreserveAspectFit
                        // Not asynchronous: after a Quickshell hot reload (any edit in
                        // this folder) async loads through the icon provider come back
                        // blank, and the grid lost every icon (2026-11-17).
                        asynchronous: false
                        smooth: true
                        mipmap: true
                    }
                    Text {
                        anchors.top: icon.bottom
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 16
                        text: cell.modelData.name
                        color: cell.selected ? Theme.fgBright : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: 12
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onContainsMouseChanged: if (containsMouse) root.selectedIndex = cell.index
                        onClicked: event => {
                            if (event.button === Qt.RightButton) {
                                root.menuEntry = cell.modelData
                                root.menuPoint = cell.mapToItem(panel.contentItem, event.x, event.y)
                                return
                            }
                            root.menuEntry = null
                            root.launch(cell.index)
                        }
                    }
                }
            }

            Text {
                anchors.centerIn: grid
                visible: root.apps.length === 0
                text: "No apps match “" + root.filterText + "”"
                color: Theme.muted
                font.family: Theme.font
                font.pixelSize: 14
            }

            Text {
                x: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                text: "type to search   arrows move   Enter open   right-click keep in dock   Esc close"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        // Right-click on an app: open it, or keep it in the dock / take it out.
        Rectangle {
            id: menu
            readonly property var entry: root.menuEntry
            readonly property bool pinned: !!entry && !!root.dock && root.dock.isPinned(String(entry.id || ""))
            visible: !!entry
            width: 200
            height: menuColumn.implicitHeight + 12
            x: Math.min(root.menuPoint.x, panel.width - width - 8)
            y: Math.min(root.menuPoint.y, panel.height - height - 8)
            radius: 12
            color: Theme.ink
            border.width: 1
            border.color: Theme.edge

            Column {
                id: menuColumn
                x: 6
                y: 6
                width: menu.width - 12
                Repeater {
                    model: [
                        { label: "Open", act: () => { const e = menu.entry; root.close(); if (root.dock) root.dock.launchEntry(e); else e.execute() } },
                        { label: menu.pinned ? "Remove from dock" : "Keep in dock", act: () => { if (root.dock) root.dock.setPinned(String(menu.entry.id || ""), !menu.pinned); root.menuEntry = null } }
                    ]
                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        width: menuColumn.width
                        height: 30
                        radius: 8
                        color: rowMouse.containsMouse ? Theme.lift : "transparent"
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            x: 10
                            text: row.modelData.label
                            color: Theme.fg
                            font.family: Theme.font
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: row.modelData.act()
                        }
                    }
                }
            }
        }
    }
}
