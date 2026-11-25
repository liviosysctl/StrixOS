// Settings › Versions: the generations of the system that are still installed. Every update and
// every rebuild leaves the version before it; one click goes back to it (strix-generations).
// "Changes" lists what a version changed against the one before it, package by package.
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

    /// The generation whose changes are listed, and the list (null while it is read)
    property int shown: -1
    property var changes: null
    Process {
        id: readChanges
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    page.changes = page.lines(JSON.parse(text))
                } catch (e) {
                    page.changes = []
                }
            }
        }
    }
    function show(generation) {
        if (page.shown === generation) { page.shown = -1; return }
        page.shown = generation
        page.changes = null
        readChanges.command = ["strix-generations", "diff", String(generation), "--json"]
        readChanges.running = true
    }

    /// What dix found, as lines: "lua 5.3.6 → 5.4.9", "statix 0.5.8, new", "just 1.59.0, removed"
    function lines(diff) {
        return (diff.diffs || []).filter(d => d.kind === "version").map(d => {
            const parts = d.versions.map(v => v.kind === "changed" ? v.old.name + " → " + v.new.name
                : v.version.name + (v.kind === "added" ? ", new" : v.kind === "removed" ? ", removed" : ""))
            return d.name + " " + parts.join("; ")
        })
    }

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
        Column {
            id: version
            required property var modelData
            readonly property bool open: page.shown === modelData.generation
            width: page.width

            SettingRow {
                width: parent.width
                last: version.open
                title: "Generation " + version.modelData.generation + (version.modelData.current ? ", running" : "")
                text: page.when(version.modelData.date) + " · " + version.modelData.nixosVersion
                Row {
                    spacing: Theme.space2
                    Button {
                        variant: "quiet"
                        text: version.open ? "Hide" : "Changes"
                        onClicked: page.show(version.modelData.generation)
                    }
                    Button {
                        visible: !version.modelData.current
                        text: "Go back"
                        onClicked: page.run("sudo strix-generations switch " + version.modelData.generation)
                    }
                }
            }
            Column {
                visible: version.open
                width: parent.width
                bottomPadding: Theme.space3
                spacing: Theme.space1
                Label {
                    visible: page.changes === null || page.changes.length === 0
                    textStyle: "caption"
                    color: Theme.textFaint
                    text: page.changes === null ? "Reading" : "No package changed its version against the version before"
                }
                Repeater {
                    model: version.open && page.changes ? page.changes : []
                    Label {
                        required property string modelData
                        width: version.width
                        elide: Text.ElideRight
                        textStyle: "caption"
                        color: Theme.textMuted
                        text: modelData
                    }
                }
                Rectangle { width: parent.width; height: Theme.lineHair; color: Theme.border }
            }
        }
    }

    SettingRow {
        width: page.width
        title: "Tidy up"
        text: "Keep the last five versions and free the space of the rest"
        Button { text: "Tidy up"; onClicked: page.run("sudo strix-generations clean") }
    }
}
