// The shell of Strix (12-desktop): wallpaper, top bar, dock, lock screen, search, cheat sheet,
// notifications, the OSD, the battery warning, the clipboard history, the theme picker and
// Settings, built from the QML module of StrixUI (import Strix).
// The colors are the session's theme (strix-theme session), which changes every 10 minutes.
//
// Installed as /etc/xdg/quickshell/strix and started by the user service strix-shell:
//   qs -c strix
// Hyprland and scripts reach it with `qs -c strix ipc call <target> <function>`; the targets are
// the IpcHandlers in these files (qs -c strix ipc show lists them).
//
// The icons of apps (the dock) come from Papirus, where it is installed.
//@ pragma IconTheme Papirus-Dark
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

    // Covered by the lock screen or the theme picker, the wallpaper changes without its reveal
    Background { quiet: lock.active || picker.present }
    Bar { id: bar }
    Dock {}
    Lock { id: lock; themeFile: themeFile }
    SearchPanel {}
    Cheatsheet {}
    Notifications { id: notifications }
    VolumeOsd {}
    BatteryWatch {}
    Clipboard {}
    ThemePicker { id: picker }
    Settings { picker: picker }
}
