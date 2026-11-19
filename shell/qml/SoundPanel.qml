// Sound in a quick panel: the volume of the output with its mute, the microphone's mute, the
// outputs to switch between (speakers, headphones, HDMI) and the way to Settings › Sound.
import QtQuick
import Quickshell.Services.Pipewire
import Strix

QuickPanel {
    id: root

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink)
    PwObjectTracker { objects: [root.sink, root.source].filter(n => n).concat(root.outputs) }

    readonly property bool muted: !!(root.sink && root.sink.audio && root.sink.audio.muted)
    readonly property bool micMuted: !!(root.source && root.source.audio && root.source.audio.muted)

    title: "Sound"
    corner: Label {
        textStyle: "caption"
        color: Theme.textMuted
        text: !(root.sink && root.sink.audio) ? "" : root.muted ? "off" : Math.round(root.sink.audio.volume * 100) + "%"
    }

    Item {
        width: parent.width
        height: Theme.controlMd
        Slider {
            x: Theme.space2
            width: parent.width - 2 * Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            iconName: root.muted ? "x" : "volume-2"
            from: 0
            to: 1
            enabled: !!(root.sink && root.sink.audio)
            value: root.sink && root.sink.audio ? root.sink.audio.volume : 0
            onMoved: {
                root.sink.audio.muted = false
                root.sink.audio.volume = value
            }
        }
    }
    ListRow {
        width: parent.width
        iconName: root.muted ? "volume-2" : "x"
        text: root.muted ? "Unmute" : "Mute"
        enabled: !!(root.sink && root.sink.audio)
        onClicked: root.sink.audio.muted = !root.sink.audio.muted
    }
    ListRow {
        width: parent.width
        visible: !!(root.source && root.source.audio)
        iconName: root.micMuted ? "x" : "check"
        text: root.micMuted ? "Turn the microphone on" : "Turn the microphone off"
        detail: root.micMuted ? "Off" : "On"
        onClicked: root.source.audio.muted = !root.source.audio.muted
    }

    // Where the sound goes, when there is a choice
    Repeater {
        model: root.outputs.length > 1 ? root.outputs : []
        ListRow {
            required property var modelData
            width: parent.width
            iconName: "volume-2"
            text: modelData.description || modelData.nickname || modelData.name
            selected: root.sink === modelData
            detail: root.sink === modelData ? "In use" : ""
            onClicked: Pipewire.preferredDefaultAudioSink = modelData
        }
    }
    ListRow { width: parent.width; iconName: "settings"; text: "Sound settings"; onClicked: root.settings("sound") }
}
