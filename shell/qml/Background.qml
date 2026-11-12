// The engraving of the current theme behind everything, on every screen, with its plate caption
// bottom left. Follows the theme at once: Theme.wallpaper() changes with ThemeFile.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Strix

Variants {
    model: Quickshell.screens

    PanelWindow {
        required property var modelData
        screen: modelData

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "strix-wallpaper"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.background

        Wallpaper { anchors.fill: parent }

        Plate {
            anchors { left: parent.left; bottom: parent.bottom; margins: Theme.space4 }
            width: Math.min(parent.width / 2, 520)
            wrapMode: Text.WordWrap
            text: Theme.about.plate || ""
        }
    }
}
