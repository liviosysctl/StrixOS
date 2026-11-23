// What drops out of the bar or grows out of the dock: the calendar, the quick panels, the tray,
// the messages and the media player. Only one of them is open at a time, and this is the one
// place that knows which, so all of them fold back the same way: a click on the picture, in a
// window or on another part of the shell, Escape, the key of the hotkeys (Super), and whatever
// Hyprland does to the windows meanwhile (another workspace, a new window, another one in front).
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    /// "", "calendar", "update", "wifi", "bluetooth", "sound", "power", "session", "tray",
    /// "notifications" or "media"
    property string current: ""
    /// The screen it is on
    property string screen: ""

    function show(name, screen) {
        root.screen = screen
        root.current = name
    }
    function close() { root.current = "" }
    function toggle(name, screen) {
        if (root.shows(name, screen)) root.close()
        else root.show(name, screen)
    }
    function shows(name, screen) { return root.current === name && root.screen === screen }

    /// The screen that has the focus, for what is opened with a key
    function here() {
        return Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name
            : Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }

    /// A key pressed while one is open. Escape ends here. Super is the start of a hotkey: the
    /// popup is gone and its focus grab with it before Hyprland runs the hotkey, which then
    /// reaches the windows as if nothing had been open.
    function key(event) {
        const hotkey = event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R
        if (event.key !== Qt.Key_Escape && !hotkey) return
        root.close()
        event.accepted = !hotkey
    }

    // What a hotkey without Super, a gesture or an app does: another workspace, a new window,
    // another window in front. Taking the focus for the popup itself reports no window, which is
    // not a change.
    property string window: ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2") {
                if (event.data === "") return
                if (root.window !== "" && root.window !== event.data) root.close()
                root.window = event.data
            } else if (["workspace", "activespecial", "openwindow", "fullscreen"].indexOf(event.name) >= 0) {
                root.close()
            }
        }
    }
}
