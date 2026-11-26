// Settings › Storage: how full the disk is, the trash, the snapshots of the home and the
// versions of the system still installed (strix-storage). The trash empties here for good; old
// versions are tidied up by strix-generations in a terminal (keeps the last five).
import QtQuick
import Quickshell
import Quickshell.Io
import Strix

Column {
    id: page

    property bool active: false
    property var info: null

    /// A command for the terminal of Settings
    signal run(string script)

    spacing: Theme.space2

    onActiveChanged: if (active) show.running = true

    Process {
        id: show
        command: ["strix-storage", "show"]
        stdout: StdioCollector { onStreamFinished: { try { page.info = JSON.parse(text) } catch (e) { page.info = null } } }
    }
    Process {
        id: empty
        command: ["strix-storage", "empty-trash"]
        onExited: show.running = true
    }

    /// 1234567890 as "1.1 GB"
    function bytes(n) {
        if (!n) return "0 B"
        const units = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (n >= 1000 && i < units.length - 1) { n /= 1000; i += 1 }
        return (n < 10 && i > 0 ? n.toFixed(1) : Math.round(n)) + " " + units[i]
    }

    Label { textStyle: "title"; color: Theme.text; text: "Storage" }

    // The disk: a hair line filled in the accent as far as it is used
    Column {
        width: parent.width
        spacing: Theme.space2
        topPadding: Theme.space2
        bottomPadding: Theme.space3
        ProgressBar {
            width: parent.width
            from: 0
            to: page.info ? page.info.disk.size : 1
            value: page.info ? page.info.disk.used : 0
            label: "The disk"
            valueText: page.info ? page.bytes(page.info.disk.used) + " of " + page.bytes(page.info.disk.size) : ""
        }
        Label {
            textStyle: "caption"
            color: Theme.textMuted
            text: page.info ? page.bytes(page.info.disk.free) + " free" : ""
        }
    }

    SettingRow {
        width: parent.width
        title: "Trash"
        text: !page.info ? "" : page.info.trash.items === 0 ? "Empty"
            : page.info.trash.items + (page.info.trash.items === 1 ? " item, " : " items, ") + page.bytes(page.info.trash.bytes)
        Row {
            spacing: Theme.space2
            Button {
                text: "Open"
                onClicked: Quickshell.execDetached(["nautilus", "--new-window", "trash:///"])
            }
            Button {
                text: "Empty"
                variant: "danger"
                enabled: !!page.info && page.info.trash.items > 0
                onClicked: empty.running = true
            }
        }
    }

    SettingRow {
        width: parent.width
        title: "Snapshots of your home"
        text: !page.info || page.info.snapshots.count === 0 ? "None yet; one is taken every hour"
            : page.info.snapshots.count + " kept, the newest from " + (page.info.snapshots.newest || "").slice(0, 16) + ". Earlier versions of your files are there."
        Button {
            text: "Open"
            enabled: !!page.info && page.info.snapshots.count > 0
            onClicked: Quickshell.execDetached(["nautilus", "--new-window", "/home/.snapshots"])
        }
    }

    SettingRow {
        width: parent.width
        title: "Versions of the system"
        text: page.info ? page.info.generations + " installed; the boot menu starts each of them" : ""
        Button {
            text: "Tidy up"
            onClicked: page.run("sudo strix-generations clean")
        }
    }
}
