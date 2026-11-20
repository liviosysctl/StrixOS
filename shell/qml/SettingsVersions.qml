// Settings › Versions: the generations of the system that are still installed. Every update and
// every rebuild leaves the version before it; one click goes back to it (strix-generations).
import QtQuick
import Quickshell
import Quickshell.Io
import Strix

Column {
    id: page

    spacing: Theme.space2

    /// Reads the list while the page is shown
    property bool active: false
    property var list: []

    /// "2026-11-20 07:02:55" as "20 Nov 2026, 07:02"
    function when(text) {
        const date = new Date(String(text).replace(" ", "T"))
        return isNaN(date.getTime()) ? text : Qt.formatDateTime(date, "d MMM yyyy, HH:mm")
    }

    /// A command for the terminal of Settings, which asks for the password
    signal run(string script)

    Process {
        id: read
        command: ["strix-generations", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.list = JSON.parse(text).sort((a, b) => b.generation - a.generation).slice(0, 12)
                } catch (e) {
                    page.list = []
                }
            }
        }
    }
    onActiveChanged: if (active) read.running = true

    Label { textStyle: "title"; color: Theme.text; text: "Versions" }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.textFaint
        text: "Every update and rebuild keeps the version before it. The boot menu starts them too, should the newest not start at all."
    }

    Repeater {
        model: page.list
        SettingRow {
            required property var modelData
            width: page.width
            title: "Generation " + modelData.generation + (modelData.current ? ", running" : "")
            text: page.when(modelData.date) + " · " + modelData.nixosVersion
            Button {
                visible: !modelData.current
                small: true
                text: "Go back"
                onClicked: page.run("sudo strix-generations switch " + modelData.generation)
            }
        }
    }

    SettingRow {
        width: page.width
        title: "Tidy up"
        text: "Keep the last five versions and free the space of the rest"
        Button { small: true; text: "Tidy up"; onClicked: page.run("sudo strix-generations clean") }
    }
}
