// The desktop's Quickshell pieces, in one resident instance (started at login
// by hypr/conf.d/autostart.lua) so each opens instantly and they share one
// process. Everything follows the current theme and font (Theme.qml).
//   NetCard.qml      network (bar Wi-Fi icon, SUPER + N)
//   BtCard.qml       Bluetooth (bar Bluetooth icon, SUPER + B)
//   AgentsCard.qml   AI agents: limits, usage, start one (bar robot icon, SUPER + CTRL + A)
//   Dock.qml         dock on floating workspaces (SUPER + ALT + L), app grid (SUPER + ALT + SPACE)
//   ThemePicker.qml  themes (SUPER + CTRL + T)
//   FontPicker.qml   fonts (SUPER + CTRL + F)
//   KeysCard.qml     every keybind, search and run (SUPER + K)
// Opened / closed by ./card <netcard|bluetooth|agents|apps|themes|fonts|keys>.
// Nothing polls while closed.
import Quickshell

ShellRoot {
    NetCard {}
    BtCard {}
    AgentsCard {}
    Dock {}
    ThemePicker {}
    FontPicker {}
    KeysCard {}
}
