.pragma library

// Which desktop entries count as apps you'd open from the desktop. Dev kits,
// SDK helpers and test utilities (OpenJDK consoles, Qt Designer/Linguist,
// CMake, V4L2 testers...) install launchers too; the app grid (SUPER + ALT +
// SPACE) and the Arch menu search leave them out.
//
// To hide another app, add its desktop id (the .desktop file name without
// ".desktop") to HIDDEN_IDS. To bring one back, add it to KEEP_IDS.

const HIDDEN_IDS = [
    "cmake-gui",                          // CMake
    "qv4l2", "qvidcap",                   // Qt V4L2 test / capture utilities
    "lstopo",                             // hwloc topology viewer
    "xgps", "xgpsspeed",                  // gpsd test clients
    "org.kde.drkonqi.coredump.gui",       // crashed processes viewer
    "org.kde.xwaylandvideobridge",
    "org.kde.plasma-welcome",             // Plasma only
    "org.kde.kmenuedit",                  // Plasma only
    "blueman-adapters",                   // XFCE / MATE only
    "rofi", "rofi-theme-selector",
    "networkmanager_dmenu",
    "claude-code-url-handler",
]

const KEEP_IDS = []

// Development tools that aren't editors or IDEs: Qt Assistant, Designer,
// Linguist, D-Bus viewer, build and debugger front ends.
const DEV_ONLY = ["Building", "Debugger", "GUIDesigner", "Translation", "Profiling", "RevisionControl"]
const USER_FACING = ["TextEditor", "IDE"]

// SDK launchers named after the runtime (jconsole-java17-openjdk, jshell-...).
const SDK_RE = /(openjdk|^jconsole|^jshell|^jvisualvm|^jmc$)/i

function isUserApp(entry) {
    if (!entry || entry.noDisplay) return false
    const id = String(entry.id || "").replace(/\.desktop$/, "")
    if (KEEP_IDS.indexOf(id) >= 0) return true
    if (HIDDEN_IDS.indexOf(id) >= 0) return false
    if (SDK_RE.test(id) || /openjdk/i.test(String(entry.name || ""))) return false

    const cats = (entry.categories || []).map(String)
    const has = c => cats.indexOf(c) >= 0
    if (has("Development") && !USER_FACING.some(has)) {
        if (has("Qt") || DEV_ONLY.some(has)) return false
    }
    return true
}
