// Settings in the proof of concept, only what is needed: Network, Bluetooth, Sound, Display, Power
// and About; each page but About is its own file. The theme is fixed, keys are not changed here.
// Opened by strix-settings [PAGE [ROW]] (ipc: settings open), from Search or the system menu.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix
import Strix.Shell

Scope {
    id: root

    property bool open: false
    property string page: "network"
    property string row: ""
    property string version: ""
    readonly property var pages: [
        { id: "network", title: "Network", icon: "wifi" },
        { id: "bluetooth", title: "Bluetooth", icon: "bluetooth" },
        { id: "sound", title: "Sound", icon: "volume-2" },
        { id: "display", title: "Display", icon: "monitor" },
        { id: "power", title: "Power", icon: "zap" },
        { id: "about", title: "About", icon: "info" }
    ]

    function show(page, row) {
        root.page = root.pages.some(p => p.id === page) ? page : "network"
        root.row = row || ""
        root.open = true
    }

    /// A command that needs root, in a terminal that stays open
    function asRoot(script) {
        terminal.command = ["ghostty", "--wait-after-command=true", "-e", "sh", "-c", script]
        terminal.running = true
    }

    Process { id: terminal }

    FileView {
        path: "/etc/os-release"
        printErrors: false
        onLoaded: {
            const name = /^NAME="?([^"\n]*)"?/m.exec(text())
            const v = /^VERSION_ID="?([^"\n]*)"?/m.exec(text())
            root.version = (name ? name[1] : "") + " " + (v ? v[1] : "")
        }
    }

    IpcHandler {
        target: "settings"
        function open(page: string, row: string): void { root.show(page, row) }
        function close(): void { root.open = false }
        function isOpen(): bool { return root.open }
        function page(): string { return root.open ? root.page : "" }
    }

    FloatingWindow {
        visible: root.open
        title: "Settings"
        implicitWidth: 920
        implicitHeight: 620
        // Smoked glass: the compositor blurs what lies behind the window
        color: Theme.smoke(Theme.surface)
        onVisibleChanged: if (!visible) root.open = false

        Row {
            anchors.fill: parent

            // The pages
            Rectangle {
                width: 220
                height: parent.height
                // A well in the glass of the window
                color: Theme.alpha(Theme.text, 0.04)
                Column {
                    anchors { fill: parent; margins: Theme.space2 }
                    spacing: Theme.space1
                    Label { x: Theme.space2; textStyle: "title"; color: Theme.text; text: "Settings"; bottomPadding: Theme.space2 }
                    Repeater {
                        model: root.pages
                        ListRow {
                            required property var modelData
                            width: parent.width
                            text: modelData.title
                            iconName: modelData.icon
                            selected: root.page === modelData.id
                            onClicked: root.page = modelData.id
                        }
                    }
                }
            }

            Flickable {
                width: parent.width - 220
                height: parent.height
                contentHeight: content.implicitHeight + 2 * Theme.space5
                clip: true

                Column {
                    id: content
                    x: Theme.space5
                    y: Theme.space5
                    width: parent.width - 2 * Theme.space5
                    spacing: Theme.space4

                    SettingsNetwork { visible: root.page === "network"; active: root.open && visible; width: parent.width }
                    SettingsBluetooth { visible: root.page === "bluetooth"; active: root.open && visible; width: parent.width }
                    SettingsSound { visible: root.page === "sound"; width: parent.width }
                    SettingsDisplay { visible: root.page === "display"; width: parent.width }
                    SettingsPower { visible: root.page === "power"; width: parent.width }

                    // ------------------------------------------------ About
                    Column {
                        visible: root.page === "about"
                        width: parent.width
                        spacing: Theme.space2

                        Label { textStyle: "title"; color: Theme.text; text: "About" }
                        Wordmark {}
                        SettingRow { width: parent.width; title: "Version"; text: root.version }
                        SettingRow {
                            width: parent.width
                            title: "Update"
                            text: "Fetch the newest release and every theme repository"
                            Button { text: "Update now"; onClicked: root.asRoot("sudo strix-update") }
                        }
                    }
                }
            }
        }
    }
}
