import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "DockModel.js" as DockModel

// The dock on floating workspaces (SUPER + ALT + L floats one), matching
// Omarchy 4.5's transparent borderless dock (shell/plugins/dock, MIT).
// Pinned apps, running apps and minimized windows (SUPER + ALT + M, or the
// titlebar's −). Click: focus / start, middle-click: new window, right-click:
// menu, drag: reorder. The first button, or SUPER + ALT + SPACE, opens a grid
// of every app (AppGrid.qml).
//   pins and auto-hide:   ~/.local/state/dock.json
//   floating workspaces:  $XDG_RUNTIME_DIR/workspace-modes (hypr/conf.d/workspace-modes.lua)
Scope {
    id: root

    readonly property bool testMode: Quickshell.env("CARDS_TEST") === "1"
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    readonly property var defaultPins: ["brave-browser", "kitty", "org.kde.dolphin", "com.microsoft.VSCode",
                                        "spotify", "discord", "org.mozilla.Thunderbird"]

    // ── settings: pins and auto-hide ────────────────────────────────────
    property var config: ({})
    readonly property bool autohide: config.autohide === true
    // A reorder shows at once; the saved file catches up after.
    property var pendingPins: null
    readonly property var pinnedKeys: pendingPins || DockModel.pinnedIds(config, { pinned: defaultPins })

    FileView {
        id: configFile
        path: root.stateHome + "/dock.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { root.config = JSON.parse(text()) || {} } catch (e) { root.config = {} }
            root.pendingPins = null
        }
        onLoadFailed: root.config = ({})
    }

    function saveConfig(changes) {
        const next = Object.assign({}, root.config, changes)
        root.config = next
        configFile.setText(JSON.stringify(next, null, 1) + "\n")
    }

    // ── which workspaces float ──────────────────────────────────────────
    property var floating: ({})

    FileView {
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/workspace-modes"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const f = {}
            for (const line of text().split("\n")) {
                const m = line.match(/^\s*(\d+)\s+floating\b/)
                if (m) f[m[1]] = true
            }
            root.floating = f
        }
        onLoadFailed: root.floating = ({})
    }

    function isFloating(id) { return id >= 1 && root.floating[String(id)] === true }

    // ── apps in the dock ────────────────────────────────────────────────
    // The dock's order for the session, as desktop ids; pins are saved in it.
    property var order: []

    // Entries that can claim a terminal app's window.
    readonly property var terminalEntries: {
        const values = DesktopEntries.applications.values
        const out = []
        for (const entry of values) {
            if (entry.runInTerminal || String(entry.execString || "").indexOf("--app-id=") >= 0)
                out.push({ id: entry.id, execString: entry.execString, command: entry.command, runInTerminal: entry.runInTerminal })
        }
        return out
    }

    function entryForAppId(appId) {
        const entry = DesktopEntries.heuristicLookup(appId)
        if (entry) return entry
        const id = DockModel.claimingEntryId(appId, root.terminalEntries)
        return id ? DesktopEntries.byId(id) : null
    }

    // A pinned app that isn't installed has nothing to launch, so it's left out.
    readonly property var items: {
        const appsRevision = DesktopEntries.applications.values.length
        const pinned = root.pinnedKeys.filter(id => !!DesktopEntries.byId(id))
        const windows = []
        const toplevels = Hyprland.toplevels.values
        for (let i = 0; i < toplevels.length; i++) {
            const toplevel = toplevels[i].wayland
            if (!toplevel || !toplevel.appId || toplevel.parent) continue
            const entry = root.entryForAppId(toplevel.appId)
            const workspace = toplevels[i].workspace
            windows.push({
                key: entry ? entry.id : toplevel.appId,
                hasEntry: !!entry && !entry.noDisplay,
                workspaceId: workspace ? workspace.id : -1,
                minimized: !!workspace && DockModel.isMinimizedWorkspace(workspace.name),
                address: toplevels[i].address,
                toplevel: toplevel
            })
        }
        return DockModel.orderItems(DockModel.buildItems(pinned, windows), root.order)
    }

    readonly property var itemsByKey: {
        const byKey = {}
        for (const item of root.items) byKey[item.key] = item
        return byKey
    }

    function itemFor(key) { return root.itemsByKey[key] || null }

    // Slots follow this model rather than the list itself, so a slot survives
    // a window opening or closing instead of being rebuilt under the pointer.
    property alias itemModel: itemModel
    ListModel { id: itemModel }
    onItemsChanged: syncItemModel()

    function shownKeys() { return root.items.map(item => item.key) }

    function syncItemModel() {
        const keys = root.shownKeys()
        for (let i = 0; i < keys.length; i++) {
            if (i < itemModel.count && itemModel.get(i).key === keys[i]) continue
            let found = -1
            for (let j = i + 1; j < itemModel.count; j++) {
                if (itemModel.get(j).key === keys[i]) { found = j; break }
            }
            if (found >= 0) itemModel.move(found, i, 1)
            else itemModel.insert(i, { key: keys[i] })
        }
        if (itemModel.count > keys.length) itemModel.remove(keys.length, itemModel.count - keys.length)
        root.settleLaunches()
    }

    // An app started from the dock pulses until a new window of it shows up,
    // or for ten seconds.
    property var launches: ({})

    function isLaunching(key) { return root.launches[key] !== undefined }

    function settleLaunches() {
        const next = {}
        let changed = false
        const now = Date.now()
        for (const key in root.launches) {
            const launch = root.launches[key]
            const item = root.itemsByKey[key]
            const windows = item ? item.windows.length : 0
            if (windows > launch.windows || now - launch.at > 10000) changed = true
            else next[key] = launch
        }
        if (changed) root.launches = next
    }

    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(root.launches).length > 0
        onTriggered: root.settleLaunches()
    }

    function entryFor(item) { return item ? DesktopEntries.byId(item.key) : null }

    function iconSource(icon) {
        if (!icon) return Quickshell.iconPath("application-x-executable", true)
        if (String(icon).startsWith("/")) return "file://" + icon
        return Quickshell.iconPath(icon, "application-x-executable")
    }

    function iconFor(item) {
        const entry = entryFor(item)
        return root.iconSource(entry && entry.icon ? entry.icon : (item ? item.key : ""))
    }

    function nameFor(item) {
        const entry = entryFor(item)
        if (entry && entry.name) return entry.name
        return item ? item.key : ""
    }

    function launch(item) {
        const entry = entryFor(item)
        if (!entry) return
        const next = Object.assign({}, root.launches)
        next[item.key] = { at: Date.now(), windows: item.windows.length }
        root.launches = next
        root.launchEntry(entry)
    }

    // Terminal apps get a kitty; DesktopEntry.execute() ignores runInTerminal.
    function launchEntry(entry) {
        if (!entry) return
        if (entry.runInTerminal) Quickshell.execDetached(["kitty", "-e"].concat(entry.command))
        else entry.execute()
    }

    function dispatch(steps) {
        Quickshell.execDetached(["sh", "-c", steps.map(s => "hyprctl dispatch '" + s + "' >/dev/null").join(" && ")])
    }

    function activate(item) {
        if (!item) return
        if (item.windows.length === 0) {
            root.launch(item)
            return
        }
        const monitor = Hyprland.focusedMonitor
        const workspaceId = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
        const index = DockModel.pickWindow(item.windows.map(w => ({ workspaceId: w.workspaceId, minimized: w.minimized, activated: w.toplevel.activated })), workspaceId)
        root.bringForward(item.windows[index])
    }

    // The window comes to the front, focused; a minimized one first comes back
    // to the workspace in front of the user.
    function bringForward(window) {
        let address = String(window.address || "")
        if (!address) {
            window.toplevel.activate()
            return
        }
        if (address.indexOf("0x") !== 0) address = "0x" + address
        const target = 'window = "address:' + address + '"'
        const steps = []
        if (window.minimized) {
            const monitor = Hyprland.focusedMonitor
            const workspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
            if (!(workspace >= 1)) return
            steps.push('hl.dsp.window.move({ workspace = "' + workspace + '", ' + target + ' })')
        }
        steps.push("hl.dsp.focus({ " + target + " })")
        steps.push('hl.dsp.window.alter_zorder({ mode = "top", ' + target + " })")
        root.dispatch(steps)
    }

    function quit(item) {
        if (!item) return
        for (const window of item.windows.slice()) window.toplevel.close()
    }

    function openApps() { appGrid.open() }

    function isPinned(key) { return root.pinnedKeys.indexOf(key) >= 0 }

    // Moves an app to a slot in the dock's order, pinning it there.
    function placeAt(key, index) {
        if (!key) return
        root.order = DockModel.orderWithKeyAt(root.shownKeys(), key, index)
        const pinned = {}
        for (const other of root.pinnedKeys) pinned[other] = true
        pinned[key] = true
        root.savePins(DockModel.pinsInOrder(root.order, pinned, root.pinnedKeys))
    }

    function savePins(pins) {
        root.pendingPins = pins
        root.saveConfig({ pinned: pins })
    }

    function moveItem(fromIndex, toIndex) {
        if (fromIndex !== toIndex) root.placeAt(root.shownKeys()[fromIndex], toIndex)
    }

    // Keeping an app puts it at the end; taking one out leaves it while it runs.
    function setPinned(key, pinned) {
        if (!key) return
        if (pinned) root.placeAt(key, root.shownKeys().length)
        else root.savePins(root.pinnedKeys.filter(other => other !== key))
    }

    // Hyprland's window and workspace lists don't follow fullscreen on their own.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event && String(event.name) === "fullscreen") {
                Hyprland.refreshWorkspaces()
                Hyprland.refreshToplevels()
            }
        }
    }

    IpcHandler {
        target: "dock"
        function apps(): void { appGrid.toggle() }                  // SUPER + ALT + SPACE
        function toggle(): void { appGrid.toggle() }                // ./card apps
        function open(): void { appGrid.open() }
        function closeApps(): void { appGrid.close() }
        function appsOn(screen: string): void { appGrid.openOn(screen) } // tests
        function filter(text: string): void { appGrid.setFilter(text) }   // tests
        function toggleAutohide(): void { root.saveConfig({ autohide: !root.autohide }) }
    }

    Variants {
        model: Quickshell.screens
        delegate: Component {
            DockWindow {
                required property var modelData
                screen: modelData
                dock: root
            }
        }
    }

    AppGrid {
        id: appGrid
        dock: root
    }
}
