// The answer to the volume keys (Osd in StrixUI): a pill at the bottom centre that leaves by itself
// after 1.5 seconds. It follows the default output of PipeWire.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Strix

Scope {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    property bool shown: false

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() { root.flash() }
        function onMutedChanged() { root.flash() }
    }

    function flash() {
        root.shown = true
        hide.restart()
    }

    Timer { id: hide; interval: 1500; onTriggered: root.shown = false }

    PanelWindow {
        visible: root.shown
        WlrLayershell.namespace: "strix-osd"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors.bottom: true
        margins.bottom: Theme.space8
        implicitWidth: osd.implicitWidth
        implicitHeight: osd.implicitHeight
        color: "transparent"
        mask: Region {}

        Osd {
            id: osd
            iconName: root.sink && root.sink.audio && root.sink.audio.muted ? "x" : "volume-2"
            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
        }
    }
}
