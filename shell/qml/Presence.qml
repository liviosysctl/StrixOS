// Arriving and leaving of a panel or overlay (motion.md): `shown` runs from 0 to 1 while `open`
// turns on, with ease-out in `duration`, and back to 0 one duration step faster with ease-in.
// `present` stays true until it has left, so the window stays mapped for the way out. A new
// trigger starts from where `shown` stands, never from the start.
import QtQuick
import Strix

Item {
    id: root

    property bool open: false
    property int duration: Theme.durBase
    property int leaveDuration: Theme.durFast

    property real shown: open ? 1 : 0
    readonly property bool present: open || shown > 0

    visible: false

    Behavior on shown {
        NumberAnimation {
            duration: root.open ? root.duration : root.leaveDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.open ? Theme.easeOut : Theme.easeIn
        }
    }
}
