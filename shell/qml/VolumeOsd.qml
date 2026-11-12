// The answer to the volume and brightness keys (Osd in StrixUI): a pill at the bottom centre that
// leaves by itself after 1.5 seconds. Volume follows the default output of PipeWire; brightness
// goes through here (ipc: osd brightness 5%+), because the backlight tells nobody it changed.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Strix

Scope {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    property bool shown: false
    /// "volume" or "brightness": what the pill shows
    property string kind: "volume"
    property real brightness: 0

    IpcHandler {
        target: "osd"
        function brightness(step: string): void {
            light.command = ["brightnessctl", "-m", "-e4", "-n2", "set", step]
            light.running = true
        }
    }

    // brightnessctl -m prints device,class,value,percent,max
    Process {
        id: light
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n").pop().split(",")
                if (f.length >= 5 && Number(f[4]) > 0) {
                    root.brightness = Number(f[2]) / Number(f[4])
                    root.kind = "brightness"
                    root.flash()
                }
            }
        }
    }

    PwObjectTracker { objects: root.sink ? [root.sink] : [] }

    Connections {
        target: root.sink ? root.sink.audio : null
        function onVolumeChanged() { root.kind = "volume"; root.flash() }
        function onMutedChanged() { root.kind = "volume"; root.flash() }
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
            iconName: root.kind === "brightness" ? "sun"
                : root.sink && root.sink.audio && root.sink.audio.muted ? "x" : "volume-2"
            value: root.kind === "brightness" ? root.brightness
                : root.sink && root.sink.audio ? root.sink.audio.volume : 0
        }
    }
}
