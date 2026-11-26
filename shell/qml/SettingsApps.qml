// Settings › Default apps: which app opens links, text, folders, pictures, video, music, PDFs and
// archives (strix-defaults). A choice goes into the person's mimeapps.list and counts at once for
// xdg-open, Files, the browser key and every app that opens something.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix

Column {
    id: page

    property bool active: false
    property var kinds: []
    property string error: ""

    spacing: Theme.space2

    onActiveChanged: if (active) list.running = true

    Process {
        id: list
        command: ["strix-defaults", "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.kinds = JSON.parse(text) } catch (e) { page.kinds = [] } }
        }
    }
    Process {
        id: set
        stderr: StdioCollector { onStreamFinished: page.error = text.trim() }
        onExited: list.running = true
    }

    function choose(kind, app) {
        page.error = ""
        set.command = ["strix-defaults", "set", kind, app]
        set.running = true
    }

    Label { textStyle: "title"; color: Theme.text; text: "Default apps" }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.textMuted
        text: "What opens when you open something. Only the apps that can open it are offered."
    }
    Label {
        visible: page.error !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.error
        text: page.error
    }

    Repeater {
        model: page.kinds.filter(k => k.apps.length > 0)

        Column {
            id: kind
            required property var modelData
            width: page.width
            spacing: Theme.space1
            topPadding: Theme.space2

            Label { textStyle: "label"; color: Theme.text; text: kind.modelData.title }
            Flow {
                width: parent.width
                spacing: Theme.space2
                Repeater {
                    model: kind.modelData.apps
                    Chip {
                        required property var modelData
                        plate: true
                        on: modelData.id === kind.modelData.current
                        text: modelData.name
                        onClicked: if (!on) page.choose(kind.modelData.kind, modelData.id)
                    }
                }
            }
        }
    }
}
