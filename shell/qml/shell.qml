// The shell of Strix (12-desktop): wallpaper, top bar, lock screen, search, cheat sheet,
// notifications, the OSD, the theme picker and Settings, built from the QML module of StrixUI (import Strix).
// The colors are the session's theme (strix-theme session), which changes every 10 minutes.
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
    Cheatsheet {}
    Notifications { id: notifications }
    VolumeOsd {}
    ThemePicker { id: picker }
    Settings { picker: picker }
}
