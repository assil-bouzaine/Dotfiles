import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "DockModel.js" as DockModel

// One screen's dock (see Dock.qml), at the bottom. Adapted from Omarchy 4.5's
// DockWindow.qml (MIT). It stays mapped and only hides its contents, so moving
// to a floating workspace doesn't wait for a new surface; while hidden its
// input region is empty and clicks fall through to the windows below.
PanelWindow {
    id: window

    property var dock: null

    readonly property var monitor: Hyprland.monitorFor(screen)
    readonly property var workspace: monitor ? monitor.activeWorkspace : null
    readonly property int workspaceId: workspace ? workspace.id : -1
    // The most fullscreen window on the workspace: 1 maximized, 2-3 fullscreen.
    readonly property int fullscreenMode: {
        let mode = 0
        for (const t of Hyprland.toplevels.values) {
            if (!t.workspace || t.workspace.id !== workspaceId) continue
            const ipc = t.lastIpcObject
            mode = Math.max(mode, ipc && ipc.fullscreen ? ipc.fullscreen : 0)
        }
        return mode
    }
    readonly property bool shown: !!dock && dock.isFloating(workspaceId) && fullscreenMode < 2
    // Auto-hide (or a maximized window) tucks the dock away until the pointer
    // reaches the screen edge.
    readonly property bool autohide: !!dock && (dock.autohide || fullscreenMode === 1)
    property bool revealed: false
    readonly property bool menuOpen: menuItem !== null || settingsMenu
    readonly property bool tucked: autohide && !(revealed || menuOpen || dragging)
    readonly property bool contentShown: shown && !tucked

    readonly property int gap: 6        // screen edge to the island, like gaps_out
    readonly property int pad: 6        // island edge to the icons
    readonly property int iconSize: 38
    readonly property int iconInset: 8
    readonly property int slotSize: iconSize + iconInset * 2
    readonly property real idleOpacity: 0.62   // pinned but not running
    readonly property int rowHeight: 30
    // Room above the island for its menu (5 rows) and the hover label.
    readonly property int popupRoom: rowHeight * 5 + 14 + gap * 3

    // Drag to reorder: the app being dragged, how far, and where it'd land.
    property int dragIndex: -1
    property int dropIndex: -1
    property real dragOffset: 0
    readonly property bool dragging: dragIndex >= 0
    property bool animateShifts: true
    // After a drop the slots moved under a pointer that didn't: hover is stale
    // until it moves again.
    property bool hoverStale: false
    property point dropPoint

    property var menuItem: null
    property Item menuSlot: null
    property bool settingsMenu: false
    property Item hoverSlot: null
    property string hoverText: ""

    onShownChanged: {
        if (shown) return
        closeMenu()
        revealed = false
    }
    onAutohideChanged: revealed = false

    function openMenu(item, slot) {
        settingsMenu = false
        menuItem = item
        menuSlot = slot
    }
    function openSettingsMenu(slot) {
        menuItem = null
        settingsMenu = true
        menuSlot = slot
    }
    function closeMenu() {
        menuItem = null
        settingsMenu = false
        menuSlot = null
        if (autohide) hideTimer.restart()
    }
    function settleShifts() {
        animateShifts = false
        Qt.callLater(() => { window.animateShifts = true })
    }
    function endDrag() {
        settleShifts()
        hoverStale = true
        dragIndex = -1
        dropIndex = -1
        dragOffset = 0
    }
    // Centred on a slot, kept on screen.
    function popupX(slot, popup) {
        if (!slot) return 0
        const center = slot.mapToItem(window.contentItem, slot.width / 2, 0).x
        return Math.max(gap, Math.min(width - popup.width - gap, center - popup.width / 2))
    }

    color: "transparent"
    WlrLayershell.namespace: "dock"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Reserves nothing: floating windows go where they're put.
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    anchors { bottom: true; left: true; right: true }
    implicitHeight: gap + slotSize + pad * 2 + popupRoom

    mask: Region {
        item: window.contentShown ? body : null
        Region { item: window.shown && window.autohide ? edgeTrigger : null }
        Region { item: menu.visible ? menu : null }
    }

    Timer {
        id: hideTimer
        interval: 150   // long enough to cross from the edge to the icons
        onTriggered: {
            if (!bodyHover.hovered && !edgeHover.hovered && !window.menuOpen && !window.dragging) window.revealed = false
        }
    }

    // The strip along the screen edge that brings an auto-hidden dock back.
    Item {
        id: edgeTrigger
        x: body.x
        y: window.height - height
        width: body.width
        height: window.gap + 2
        HoverHandler {
            id: edgeHover
            onHoveredChanged: {
                if (hovered) window.revealed = true
                else hideTimer.restart()
            }
        }
    }

    HyprlandFocusGrab {
        active: window.menuOpen && !(window.dock && window.dock.testMode)
        windows: [window]
        onCleared: window.closeMenu()
    }

    Item {
        id: body
        width: slots.implicitWidth + window.pad * 2
        height: window.slotSize + window.pad * 2
        // How far it's tucked below the edge (auto-hide).
        property real tuck: window.tucked ? height + window.gap : 0
        Behavior on tuck {
            enabled: window.shown
            NumberAnimation { duration: 170; easing.type: Easing.OutCubic }
        }
        x: Math.round((window.width - width) / 2)
        y: window.height - height - window.gap + tuck
        // Shown and hidden at once with the workspace; by opacity, so the icons
        // keep their textures.
        opacity: window.shown ? 1 : 0

        HoverHandler {
            id: bodyHover
            onHoveredChanged: if (!hovered && window.autohide) hideTimer.restart()
            onPointChanged: {
                if (!window.hoverStale || window.dragging) return
                const at = point.position
                if (Math.hypot(at.x - window.dropPoint.x, at.y - window.dropPoint.y) > 4) window.hoverStale = false
            }
        }

        // the island, like the bar's
        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Theme.ink
            border.width: 1
            border.color: Theme.edge
        }

        Row {
            id: slots
            x: window.pad
            y: window.pad

            AppsSlot {}

            // hairline between the apps button and the apps
            Item {
                width: 9
                height: window.slotSize
                Rectangle { anchors.centerIn: parent; width: 1; height: 26; color: Theme.rule }
            }

            Repeater {
                id: appRepeater
                model: window.dock ? window.dock.itemModel : null
                delegate: AppSlot {}
            }
        }
    }

    // The hovered app's name, above its icon.
    Rectangle {
        id: tip
        visible: window.contentShown && !!window.hoverSlot && !window.dragging && !window.menuOpen && window.hoverText !== ""
        readonly property real cx: window.hoverSlot ? window.hoverSlot.mapToItem(window.contentItem, window.hoverSlot.width / 2, 0).x : 0
        x: Math.max(window.gap, Math.min(window.width - width - window.gap, cx - width / 2))
        y: body.y - height - 8
        width: tipText.implicitWidth + 20
        height: tipText.implicitHeight + 10
        radius: 9
        color: Theme.ink
        border.width: 1
        border.color: Theme.edge
        Text {
            id: tipText
            anchors.centerIn: parent
            text: window.hoverText
            color: Theme.fg
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Medium
        }
    }

    component Slot: Item {
        // Only the dragged icon lifts during a drag.
        property bool hovered: mouse.containsMouse && !window.hoverStale && !window.dragging
        property alias mouse: mouse
        width: window.slotSize
        height: window.slotSize
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        }
    }

    // All apps: a grid of squares reads as "apps" in any icon theme.
    component AppsSlot: Slot {
        id: appsSlot
        onHoveredChanged: {
            if (hovered) { window.hoverSlot = appsSlot; window.hoverText = "All apps" }
            else if (window.hoverSlot === appsSlot) window.hoverSlot = null
        }
        mouse.onClicked: event => {
            if (event.button === Qt.RightButton) {
                window.openSettingsMenu(appsSlot)
                return
            }
            window.closeMenu()
            if (window.dock) window.dock.openApps()
        }
        Item {
            x: window.iconInset
            y: window.iconInset
            width: window.iconSize
            height: window.iconSize
            scale: appsSlot.hovered ? 1.12 : 1
            transformOrigin: Item.Bottom
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Grid {
                readonly property int square: Math.round(window.iconSize * 0.2)
                anchors.centerIn: parent
                columns: 3
                spacing: Math.round(window.iconSize * 0.1)
                Repeater {
                    model: 9
                    delegate: Rectangle {
                        width: parent.square
                        height: parent.square
                        radius: Math.max(1, Math.round(parent.square * 0.25))
                        color: index === 4 ? Theme.accent : Theme.fg
                    }
                }
            }
        }
    }

    component AppSlot: Slot {
        id: appSlot

        required property int index
        required property string key
        readonly property var modelData: window.dock ? window.dock.itemFor(key) : null
        readonly property bool launching: !!window.dock && window.dock.isLaunching(key)
        readonly property bool lifted: window.dragIndex === index
        readonly property int windowCount: modelData ? modelData.windows.length : 0
        readonly property bool focused: !!modelData && modelData.windows.some(w => w.toplevel && w.toplevel.activated)
        readonly property bool allMinimized: windowCount > 0 && modelData.windows.every(w => w.minimized)
        property point pressPoint
        property bool dragged: false
        property real pulse: 1

        // Slots between the dragged app and where it'd land step aside.
        readonly property real shift: !window.dragging ? 0
            : lifted ? window.dragOffset
            : (window.dragIndex < index && index <= window.dropIndex) ? -window.slotSize
            : (window.dropIndex <= index && index < window.dragIndex) ? window.slotSize
            : 0
        property real displayedShift: shift
        Behavior on displayedShift {
            enabled: window.animateShifts && window.dragging && !appSlot.lifted
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
        }
        z: lifted ? 1 : 0

        onHoveredChanged: {
            if (hovered) { window.hoverSlot = appSlot; window.hoverText = window.dock ? window.dock.nameFor(modelData) : "" }
            else if (window.hoverSlot === appSlot) window.hoverSlot = null
        }

        // The slot stays put; only the icon moves. Reading the pointer through a
        // moving slot would feed each move back into the next.
        function bodyPoint(event) { return appSlot.mapToItem(body, event.x, event.y) }

        mouse.onPressed: event => {
            appSlot.dragged = false
            if (event.button === Qt.LeftButton) appSlot.pressPoint = appSlot.bodyPoint(event)
        }
        mouse.onPositionChanged: event => {
            if (!(appSlot.mouse.pressedButtons & Qt.LeftButton)) return
            const point = appSlot.bodyPoint(event)
            const delta = point.x - appSlot.pressPoint.x
            if (Math.hypot(point.x - appSlot.pressPoint.x, point.y - appSlot.pressPoint.y) > 4) appSlot.dragged = true
            if (!window.dragging) {
                if (Math.abs(delta) < 6) return
                window.closeMenu()
                window.dropIndex = appSlot.index   // landing slot first, then the dragged one
                window.dragIndex = appSlot.index
            }
            if (!appSlot.lifted) return
            window.dragOffset = delta
            window.dropIndex = DockModel.dropIndex(appSlot.index, delta, window.slotSize, appRepeater.count)
        }
        mouse.onReleased: event => {
            if (!appSlot.lifted) return
            window.dropPoint = appSlot.mapToItem(body, event.x, event.y)
            const from = window.dragIndex
            const to = window.dropIndex
            appSlot.dragged = true
            window.endDrag()
            window.dock.moveItem(from, to)
        }
        mouse.onCanceled: if (appSlot.lifted) window.endDrag()
        mouse.onClicked: event => {
            if (appSlot.dragged) {            // the end of a drag isn't a click
                appSlot.dragged = false
                return
            }
            if (event.button === Qt.RightButton) {
                window.openMenu(appSlot.modelData, appSlot)
                return
            }
            window.closeMenu()
            if (event.button === Qt.MiddleButton) window.dock.launch(appSlot.modelData)
            else window.dock.activate(appSlot.modelData)
        }

        // Running apps in full, pinned ones that aren't running faded, one
        // that is starting pulses between the two.
        Image {
            x: window.iconInset
            y: window.iconInset
            width: window.iconSize
            height: window.iconSize
            sourceSize: Qt.size(window.iconSize * 2, window.iconSize * 2)
            source: window.dock && appSlot.modelData ? window.dock.iconFor(appSlot.modelData) : ""
            fillMode: Image.PreserveAspectFit
            // Not asynchronous: async icon loads come back blank after a
            // Quickshell hot reload (see AppGrid.qml).
            asynchronous: false
            smooth: true
            mipmap: true
            opacity: appSlot.launching ? appSlot.pulse : (appSlot.windowCount > 0 && !appSlot.allMinimized ? 1 : window.idleOpacity)
            transform: Translate { x: appSlot.displayedShift }
            scale: appSlot.lifted || appSlot.hovered ? 1.12 : 1
            transformOrigin: Item.Bottom
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }

        // Running: a dot; the focused app's is a wider accent pill.
        Rectangle {
            visible: appSlot.windowCount > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height - 4
            width: appSlot.focused ? 12 : 4
            height: 4
            radius: 2
            color: appSlot.focused ? Theme.accent : appSlot.allMinimized ? Theme.faint : Theme.muted
            transform: Translate { x: appSlot.displayedShift }
            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        SequentialAnimation {
            running: appSlot.launching
            loops: Animation.Infinite
            onRunningChanged: if (!running) appSlot.pulse = 1
            NumberAnimation { target: appSlot; property: "pulse"; from: 1; to: window.idleOpacity; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { target: appSlot; property: "pulse"; to: 1; duration: 500; easing.type: Easing.InOutSine }
        }
    }

    // Right-click menus: an app's, or the apps button's (settings).
    Rectangle {
        id: menu

        readonly property var item: window.menuItem
        readonly property bool hasEntry: !!item && !!window.dock && !!window.dock.entryFor(item)
        readonly property bool running: !!item && item.windows.length > 0

        visible: window.contentShown && (!!item || window.settingsMenu)
        width: Math.max(180, menuColumn.implicitWidth) + 12
        height: menuColumn.implicitHeight + 12
        x: window.popupX(window.menuSlot, menu)
        y: body.y - window.gap - height
        radius: 12
        color: Theme.ink
        border.width: 1
        border.color: Theme.edge

        Column {
            id: menuColumn
            x: 6
            y: 6
            width: menu.width - 12

            MenuRow {
                visible: window.settingsMenu
                text: "All apps"
                hint: "Super Alt Space"
                onTriggered: window.dock.openApps()
            }
            MenuRow {
                visible: window.settingsMenu
                text: "Auto-hide"
                checked: !!window.dock && window.dock.autohide
                onTriggered: window.dock.saveConfig({ autohide: !window.dock.autohide })
            }
            MenuRow {
                visible: menu.hasEntry && menu.running
                text: "New window"
                onTriggered: window.dock.launch(menu.item)
            }
            MenuRow {
                visible: menu.hasEntry
                text: menu.item && menu.item.pinned ? "Remove from dock" : "Keep in dock"
                onTriggered: window.dock.setPinned(menu.item.key, !menu.item.pinned)
            }
            MenuRow {
                visible: menu.running
                text: menu.item && menu.item.windows.length > 1 ? "Quit all windows" : "Quit"
                danger: true
                onTriggered: window.dock.quit(menu.item)
            }
        }
    }

    component MenuRow: Rectangle {
        id: row
        property string text: ""
        property string hint: ""
        property bool checked: false
        property bool danger: false
        signal triggered()

        width: parent ? parent.width : 0
        height: visible ? window.rowHeight : 0
        radius: 8
        color: rowMouse.containsMouse ? Theme.lift : "transparent"

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: row.text
            color: row.danger && rowMouse.containsMouse ? Theme.red : Theme.fg
            font.family: Theme.font
            font.pixelSize: 13
        }
        Text {
            visible: row.checked || row.hint !== ""
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 10
            text: row.checked ? "✓" : row.hint
            color: row.checked ? Theme.accent : Theme.faint
            font.family: Theme.font
            font.pixelSize: row.checked ? 13 : 11
        }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                row.triggered()
                window.closeMenu()
            }
        }
    }
}
