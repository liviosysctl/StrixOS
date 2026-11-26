// The engraving of the current theme behind everything, on every screen. Follows the theme at
// once: Theme.wallpaper() changes with ThemeFile. A plain picture, decoded no larger than the
// screen shows it: the Wallpaper of StrixUI would keep its blur ready for nothing here.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Strix

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: window
        required property var modelData
        screen: modelData

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "strix-wallpaper"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.background

        Image {
            anchors.fill: parent
            source: Theme.wallpaper()
            fillMode: Image.PreserveAspectCrop
            // The lock screen asks for the same size and shares the picture (Lock)
            sourceSize: Qt.size(Math.ceil(window.modelData.width * window.modelData.devicePixelRatio),
                Math.ceil(window.modelData.height * window.modelData.devicePixelRatio))
            asynchronous: true
        }
    }
}
