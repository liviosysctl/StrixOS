// The shell of Strix in the proof of concept, kept simple: wallpaper, top bar, lock screen, search,
// notifications, the volume OSD, the cheat sheet, Settings and the Store, built from the QML module of StrixUI
// (import Strix). One theme, Saturnus; it does not change by itself.
//
// Installed as /etc/xdg/quickshell/strix and started by the user service strix-shell:
//   qs -c strix
// Hyprland and scripts reach it with `qs -c strix ipc call <target> <function>`; the targets are
// the IpcHandlers in these files (qs -c strix ipc show lists them).
import QtQuick
import Quickshell
import Strix
import Strix.Shell

ShellRoot {
    id: root

    ThemeFile {
        id: themeFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/strix/theme/tokens.json"
    }

    Background {}
    Bar { id: bar }
    Lock { id: lock; themeFile: themeFile }
    SearchPanel {}
    Notifications { id: notifications }
    VolumeOsd {}
    Cheatsheet {}
    Settings {}
    Store {}
}
