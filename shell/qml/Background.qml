// The engraving of the current theme behind everything, on every screen. When the theme changes,
// the new engraving grows as a circle from the middle of the screen (motion.md); while something
// covers the desktop (the lock screen, the theme picker) it changes at once. The clock of the
// desktop stands on it (DesktopClock).
import QtQuick
import Quickshell
import Quickshell.Wayland
import Strix

Variants {
    id: root

    model: Quickshell.screens
    /// Change without the reveal: nobody sees the desktop right now
    property bool quiet: false

    PanelWindow {
        id: window
        required property var modelData
        screen: modelData

        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "strix-wallpaper"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.background

        /// The picture the theme wants, and the next one when it changed during a reveal
        readonly property url wanted: Theme.wallpaper()
        property url next: ""

        function change(picture) {
            if (picture.toString() === base.source.toString()) return
            if (root.quiet) {
                reveal.clear()
                base.source = picture
                return
            }
            if (reveal.busy) {
                window.next = picture
                return
            }
            reveal.play(Qt.point(width / 2, height / 2), picture)
        }

        onWantedChanged: change(wanted)

        Image {
            id: base
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            Component.onCompleted: source = window.wanted
            // The grown circle covers everything until the picture below shows the same
            onStatusChanged: if (status === Image.Ready && source.toString() === reveal.source.toString() && !reveal.busy) reveal.clear()
        }

        CircleReveal {
            id: reveal
            anchors.fill: parent
            z: 1
            onFinished: {
                base.source = reveal.source
                if (base.status === Image.Ready) reveal.clear()
                if (window.next.toString() !== "") {
                    const picture = window.next
                    window.next = ""
                    window.change(picture)
                }
            }
        }

        // Over the picture, under the circle of a new one, which takes it along
        DesktopClock {
            anchors.fill: parent
            screen: window.modelData
        }
    }
}
