// Loads every component of the design system in Quickshell, without a screen (eval.nix: ui).
import QtQuick
import Quickshell
import Strix
import Strix.Shell

ShellRoot {
    ThemeFile { path: Quickshell.env("TOKENS") }
    Item {
        Loader {
            id: gallery
            source: Quickshell.env("GALLERY")
        }
    }
    Timer {
        interval: 1500
        running: true
        onTriggered: {
            console.log("STRIX-RESULT gallery=" + gallery.status + " theme=" + Theme.current + " accent=" + Theme.accent)
            Qt.exit(0)
        }
    }
}
