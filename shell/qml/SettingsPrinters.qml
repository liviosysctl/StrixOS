// Settings › Printers: the printers CUPS knows (strix-printers) and which one is yours by
// default. Printers on the network that speak IPP come by themselves; others, and the queue of
// one, are in the printer settings of CUPS (system-config-printer).
import QtQuick
import Quickshell
import Quickshell.Io
import Strix

Column {
    id: page

    property bool active: false
    property var printers: []

    spacing: Theme.space2

    onActiveChanged: if (active) list.running = true

    Process {
        id: list
        command: ["strix-printers", "list"]
        stdout: StdioCollector { onStreamFinished: { try { page.printers = JSON.parse(text) } catch (e) { page.printers = [] } } }
    }
    Process {
        id: choose
        onExited: list.running = true
    }
    // A printer that comes or goes on the network shows up without opening the page again
    Timer { interval: 5000; repeat: true; running: page.active; onTriggered: list.running = true }

    Label { textStyle: "title"; color: Theme.text; text: "Printers" }

    Label {
        visible: page.printers.length === 0
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "body"
        color: Theme.textFaint
        text: "No printer yet. A printer on the same network shows up here by itself once it is on; one on a cable or an older one is added in the printer settings."
    }

    Repeater {
        model: page.printers
        SettingRow {
            required property var modelData
            width: page.width
            title: modelData.name.replace(/_/g, " ")
            text: (modelData.state === "printing" ? "Printing" : modelData.state === "off" ? "Switched off in CUPS" : "Ready")
                + (modelData.default ? ", the default" : "")
            Button {
                visible: !modelData.default
                text: "Make default"
                onClicked: {
                    choose.command = ["strix-printers", "default", modelData.name]
                    choose.running = true
                }
            }
        }
    }

    Row {
        spacing: Theme.space2
        topPadding: Theme.space2
        Button {
            text: "Printer settings"
            iconName: "settings"
            onClicked: Quickshell.execDetached(["system-config-printer"])
        }
    }
}
