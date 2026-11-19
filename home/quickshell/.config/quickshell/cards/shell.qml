// The desktop's Quickshell pieces, in one resident instance (started at login
// by hypr/conf.d/autostart.lua) so each opens instantly and they share one
// process. Everything follows the current theme and font (Theme.qml).
//   NetCard.qml      network (bar Wi-Fi icon, SUPER + N)
//   BtCard.qml       Bluetooth (bar Bluetooth icon, SUPER + B)
//   AgentsCard.qml   AI agents: limits, usage, start one (bar robot icon, SUPER + CTRL + A)
//   Dock.qml         dock on floating workspaces (SUPER + ALT + L), app grid (SUPER + ALT + SPACE)
//   ThemePicker.qml  themes (SUPER + CTRL + T)
//   FontPicker.qml   fonts (SUPER + CTRL + F)
//   KeysCard.qml     every keybind, search and run (SUPER + K); also vim / tmux (Arch menu > Learn)
//   MenuCard.qml     the Arch menu: apps, settings, toggles, power (bar Arch logo, SUPER + D)
//   OsdCard.qml      brightness and volume pill above the dock, shown by osd.sh on the media keys
// Opened / closed by ./card <menu|netcard|bluetooth|agents|apps|themes|fonts|keys [vim|tmux]>.
// Nothing polls while closed.
import Quickshell

ShellRoot {
    MenuCard {}
    NetCard {}
    BtCard {}
    AgentsCard {}
    Dock {}
    ThemePicker {}
    FontPicker {}
    KeysCard {}
    OsdCard {}
}
