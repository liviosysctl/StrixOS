// Settings › Sound: where the sound goes and where it comes from, with the volume of each.
// PipeWire through Quickshell.Services.Pipewire; the choice is PipeWire's default device.
import QtQuick
import Quickshell.Services.Pipewire
import Strix

Column {
    id: page

    spacing: Theme.space2

    readonly property var devices: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var outputs: page.devices.filter(n => n.isSink)
    readonly property var inputs: page.devices.filter(n => !n.isSink)

    PwObjectTracker { objects: page.devices }

    component Device: SettingRow {
        required property var node
        required property bool chosen
        property bool output: true
        width: page.width
        title: node.description || node.nickname || node.name
        text: chosen ? "In use" : ""
        Row {
            spacing: Theme.space3
            Slider {
                width: 200
                from: 0
                to: 1
                value: node.audio ? node.audio.volume : 0
                onMoved: if (node.audio) node.audio.volume = value
            }
            IconButton {
                small: true
                iconName: node.audio && node.audio.muted ? "x" : "volume-2"
                onClicked: if (node.audio) node.audio.muted = !node.audio.muted
            }
            Button {
                small: true
                visible: !chosen
                text: "Use"
                onClicked: {
                    if (output) Pipewire.preferredDefaultAudioSink = node
                    else Pipewire.preferredDefaultAudioSource = node
                }
            }
        }
    }

    Label { textStyle: "title"; color: Theme.text; text: "Sound" }

    Label { textStyle: "subtitle"; color: Theme.text; text: "Output" }
    Label { visible: page.outputs.length === 0; textStyle: "body"; color: Theme.textFaint; text: "No speakers or headphones found." }
    Repeater {
        model: page.outputs
        Device { required property var modelData; node: modelData; chosen: Pipewire.defaultAudioSink === modelData }
    }

    Item { width: 1; height: Theme.space3 }
    Label { textStyle: "subtitle"; color: Theme.text; text: "Input" }
    Label { visible: page.inputs.length === 0; textStyle: "body"; color: Theme.textFaint; text: "No microphone found." }
    Repeater {
        model: page.inputs
        Device { required property var modelData; node: modelData; chosen: Pipewire.defaultAudioSource === modelData; output: false }
    }
}
