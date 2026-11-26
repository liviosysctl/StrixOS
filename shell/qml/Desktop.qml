// What the desktop shows on the picture besides the god, as set in Settings › Themes, kept in
// ~/.config/strix/desktop.json. Read by the wallpaper (Background): the clock, with what is
// playing under it.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    /// Date and time on the picture, beside the god
    property bool clock: true

    function setClock(on) {
        root.clock = on
        store.setText(JSON.stringify({ clock: on }, null, 2) + "\n")
    }

    FileView {
        id: store
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/strix/desktop.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.clock = JSON.parse(text()).clock !== false } catch (e) { root.clock = true }
        }
    }
}
