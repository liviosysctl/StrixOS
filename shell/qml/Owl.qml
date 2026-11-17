// The owl of the distro in the colours of a theme (packages/logo): white eyes, the pupils in the
// accent. blink() closes the eyes once, over a half-closed frame on the way down and up.
// `dir` is the folder of the owls (STRIX_LOGOS), one <theme>-<variant>.png each with -half and
// -closed beside it.
import QtQuick
import Strix

Item {
    id: root

    property string dir
    property string theme: Theme.current
    property string variant: "dark"
    /// 0 open, 1 half closed, 2 closed
    property int lid: 0

    readonly property string base: "file://" + root.dir + "/" + root.theme + "-" + root.variant

    implicitWidth: 128
    implicitHeight: 128

    function blink() {
        if (!Theme.reducedMotion) closing.restart()
    }

    Repeater {
        model: ["", "-half", "-closed"]
        Image {
            required property string modelData
            required property int index
            anchors.fill: parent
            source: root.dir ? root.base + modelData + ".png" : ""
            sourceSize: Qt.size(root.width * 2, root.height * 2)
            smooth: true
            mipmap: true
            visible: root.lid === index
        }
    }

    SequentialAnimation {
        id: closing
        PropertyAction { target: root; property: "lid"; value: 1 }
        PauseAnimation { duration: 40 }
        PropertyAction { target: root; property: "lid"; value: 2 }
        PauseAnimation { duration: Theme.durInstant + 40 }
        PropertyAction { target: root; property: "lid"; value: 1 }
        PauseAnimation { duration: 40 }
        PropertyAction { target: root; property: "lid"; value: 0 }
    }
}
