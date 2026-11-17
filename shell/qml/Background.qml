// The engraving of the current theme behind everything, on every screen, with its plate caption
// bottom left. When the theme changes, the new engraving grows as a circle from the middle of the
// screen and the caption fades over (motion.md); while something covers the desktop (the lock
// screen, the theme picker) it changes at once.
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

        Plate {
            id: plate
            anchors { left: parent.left; bottom: parent.bottom; margins: Theme.space4 }
            width: Math.min(parent.width / 2, 520)
            wrapMode: Text.WordWrap
            readonly property string wanted: Theme.about.plate || ""
            text: wanted
            onWantedChanged: if (!root.quiet) recaption.restart(); else text = wanted

            // The old caption fades out, the new one in
            SequentialAnimation {
                id: recaption
                NumberAnimation { target: plate; property: "opacity"; to: 0; duration: Theme.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeIn }
                ScriptAction { script: plate.text = plate.wanted }
                NumberAnimation { target: plate; property: "opacity"; to: 1; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }
        }
    }
}
