// Settings › Date and time: the time zone of the machine and whether the clock follows the
// internet (timedated; both ask for the password of an administrator). On a machine whose
// machine.nix still names the time zone (installed before 0.7) NixOS keeps it fixed: one step in a
// terminal hands it over, it removes the line and rebuilds.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix

Column {
    id: page

    property bool active: false
    property string zone: ""
    property bool synced: false
    property bool ntp: false
    property var zones: []
    property string filter: ""
    property string error: ""
    /// machine.nix names the time zone: NixOS does not let it be changed
    property bool fixed: false

    /// A command for the terminal of Settings
    signal run(string script)

    spacing: Theme.space2

    function refresh() {
        status.running = true
        machine.reload()
        if (page.zones.length === 0) list.running = true
    }
    onActiveChanged: if (active) refresh()

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Process {
        id: status
        command: ["timedatectl", "show", "--property=Timezone", "--property=NTP", "--property=NTPSynchronized"]
        stdout: StdioCollector {
            onStreamFinished: {
                const get = key => ((new RegExp("^" + key + "=(.*)$", "m")).exec(text) || [])[1] || ""
                page.zone = get("Timezone")
                page.ntp = get("NTP") === "yes"
                page.synced = get("NTPSynchronized") === "yes"
            }
        }
    }
    Process {
        id: list
        command: ["timedatectl", "list-timezones", "--no-pager"]
        stdout: StdioCollector { onStreamFinished: page.zones = text.split("\n").filter(z => z !== "") }
    }
    FileView {
        id: machine
        path: "/etc/nixos/machine.nix"
        printErrors: false
        onLoaded: page.fixed = /^\s*time\.timeZone\s*=/m.test(text())
    }
    Process {
        id: change
        stderr: StdioCollector { onStreamFinished: if (text.trim() !== "") page.error = text.trim() }
        onExited: code => { if (code === 0) page.error = ""; status.running = true }
    }

    function setZone(name) {
        page.error = ""
        change.command = ["timedatectl", "set-timezone", name]
        change.running = true
    }

    Label { textStyle: "title"; color: Theme.text; text: "Date and time" }

    SettingRow {
        width: parent.width
        title: Qt.formatDateTime(clock.date, "HH:mm, dddd d MMMM yyyy")
        text: page.zone !== "" ? page.zone.replace(/_/g, " ") : "The time zone is not known"
    }

    SettingRow {
        width: parent.width
        title: "Time from the internet"
        text: page.ntp ? (page.synced ? "On; the clock is right to the second" : "On; waiting for the network") : "Off; the clock runs by itself"
        Switch {
            checked: page.ntp
            onToggled: {
                change.command = ["timedatectl", "set-ntp", checked ? "true" : "false"]
                change.running = true
            }
        }
    }

    Item { width: 1; height: Theme.space4 }
    Label { textStyle: "subtitle"; color: Theme.text; text: "Time zone" }

    // Installed before Settings could change it: machine.nix holds it
    Column {
        visible: page.fixed
        width: parent.width
        spacing: Theme.space2
        Label {
            width: parent.width
            wrapMode: Text.WordWrap
            textStyle: "caption"
            color: Theme.textMuted
            text: "The time zone is written in /etc/nixos/machine.nix, so it cannot change here. Once that line is gone, it is the machine's own and changes here at once, also on the way."
        }
        Button {
            text: "Change it here from now on"
            variant: "primary"
            onClicked: page.run("sudo sed -i '/^[[:space:]]*time\\.timeZone[[:space:]]*=/d' /etc/nixos/machine.nix && sudo strix-rebuild switch && sudo timedatectl set-timezone " + page.zone)
        }
    }

    Column {
        visible: !page.fixed
        width: parent.width
        spacing: Theme.space2

        SearchField {
            width: parent.width
            onTextChanged: page.filter = text.toLowerCase().replace(/ /g, "_")
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
            // The first 40 that match; typing finds the rest
            model: page.zones.filter(z => page.filter === "" ? z === page.zone : z.toLowerCase().indexOf(page.filter) >= 0).slice(0, 40)
            ListRow {
                required property var modelData
                width: page.width
                text: modelData.split("/").pop().replace(/_/g, " ")
                detail: modelData.split("/").slice(0, -1).join(" / ").replace(/_/g, " ")
                selected: modelData === page.zone
                onClicked: page.setZone(modelData)
            }
        }
        Label {
            visible: page.filter === ""
            textStyle: "caption"
            color: Theme.textFaint
            text: "Type a city or a region to find its time zone."
        }
    }
}
