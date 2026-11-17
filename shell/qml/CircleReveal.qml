// A new wallpaper that grows as a circle from `origin` over what lies below it (Theme apply in
// motion.md). play() waits until the picture is loaded, so the circle never shows an empty frame;
// it stays covering everything once grown, until clear().
import QtQuick
import QtQuick.Effects
import Strix

Item {
    id: root

    property url source
    property point origin: Qt.point(width / 2, height / 2)
    property real progress: 0
    readonly property bool busy: grow.running || waiting
    property bool waiting: false

    /// From the origin to the farthest corner: the radius that covers everything
    readonly property real reach: Math.max(
        Math.hypot(origin.x, origin.y), Math.hypot(width - origin.x, origin.y),
        Math.hypot(origin.x, height - origin.y), Math.hypot(width - origin.x, height - origin.y))

    signal finished()

    function play(from, picture) {
        grow.stop()
        root.origin = from
        root.progress = 0
        root.source = picture
        root.waiting = true
        if (image.status === Image.Ready) root.start()
    }

    function clear() {
        grow.stop()
        root.waiting = false
        root.progress = 0
    }

    function start() {
        root.waiting = false
        grow.restart()
    }

    Image {
        id: image
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
        onStatusChanged: if (status === Image.Ready && root.waiting) root.start()
    }

    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            readonly property real r: root.progress * root.reach
            x: root.origin.x - r
            y: root.origin.y - r
            width: 2 * r
            height: 2 * r
            radius: r
            antialiasing: true
            color: "white"
        }
    }

    MultiEffect {
        anchors.fill: parent
        visible: root.progress > 0
        source: image
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.1
    }

    NumberAnimation {
        id: grow
        target: root
        property: "progress"
        from: 0
        to: 1
        duration: Theme.durReveal
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.easeInOut
        onFinished: root.finished()
    }
}
