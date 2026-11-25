// Settings in the proof of concept: a first page with a card for every page, then Network,
// Bluetooth, Sound, Display, Input, Power, Hotkeys, Versions and About, as on main; each page but
// About is its own file. The theme is fixed, so there is no page for themes.
// Opened by strix-settings [PAGE [ROW]] (ipc: settings open), from Search or the system menu.
// Hotkeys: every key, from the search service (Backend "search", hotkeys), changed one by one.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix
import Strix.Shell

Scope {
    id: root

    property bool open: false
    /// "home" is the first page: every other page with a line about it
    property string page: "home"
    property string row: ""
    property string version: ""
    readonly property var pages: [
        { id: "network", title: "Network", icon: "wifi", about: "Wi-Fi and wired networks" },
        { id: "bluetooth", title: "Bluetooth", icon: "bluetooth", about: "Devices to pair and connect" },
        { id: "sound", title: "Sound", icon: "volume-2", about: "Outputs, inputs and their volume" },
        { id: "display", title: "Display", icon: "monitor", about: "Screens, their size, place and scale, the night light" },
        { id: "input", title: "Input", icon: "mouse", about: "Keyboard layouts, mouse and touchpad" },
        { id: "power", title: "Power", icon: "zap", about: "What happens when nobody is at the machine, and the lid" },
        { id: "hotkeys", title: "Hotkeys", icon: "keyboard", about: "Every key, and keys of your own" },
        { id: "versions", title: "Versions", icon: "history", about: "The versions still installed, what they changed, going back" },
        { id: "about", title: "About", icon: "info", about: "This machine and the distribution" }
    ]

    function show(page, row) {
        root.page = root.pages.some(p => p.id === page) ? page : "home"
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

            // The pages; the first page has them as cards instead
            Rectangle {
                visible: root.page !== "home"
                width: 220
                height: parent.height
                // A well in the glass of the window, as the cards are
                color: Theme.alpha(Theme.text, 0.04)
                Column {
                    anchors { fill: parent; margins: Theme.space2 }
                    spacing: Theme.space1
                    // The title leads back to the first page
                    Label {
                        x: Theme.space2
                        textStyle: "title"
                        color: Theme.text
                        text: "Settings"
                        bottomPadding: Theme.space2
                        HoverHandler { cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.page = "home" }
                    }
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
                width: parent.width - (root.page !== "home" ? 220 : 0)
                height: parent.height
                contentHeight: content.implicitHeight + 2 * Theme.space5
                clip: true

                Column {
                    id: content
                    x: Theme.space5
                    y: Theme.space5
                    width: parent.width - 2 * Theme.space5
                    spacing: Theme.space4

                    // ------------------------------------------------ the first page
                    Column {
                        visible: root.page === "home"
                        width: parent.width
                        spacing: Theme.space1

                        Label { textStyle: "title"; color: Theme.text; text: "Settings" }
                        Label {
                            width: parent.width
                            textStyle: "caption"
                            color: Theme.textFaint
                            bottomPadding: Theme.space3
                            text: root.version + ". Search finds every single setting by its name."
                        }
                        // A card for every page
                        Grid {
                            id: cards
                            width: parent.width
                            columns: 3
                            spacing: Theme.space3
                            Repeater {
                                model: root.pages
                                Item {
                                    id: tile
                                    required property var modelData
                                    width: (cards.width - 2 * cards.spacing) / 3
                                    height: 96
                                    Card {
                                        anchors.fill: parent
                                        interactive: true
                                        title: tile.modelData.title
                                        text: tile.modelData.about
                                        onClicked: root.page = tile.modelData.id
                                    }
                                    Icon {
                                        anchors { right: parent.right; rightMargin: Theme.space3; top: parent.top; topMargin: Theme.space3 }
                                        name: tile.modelData.icon
                                        color: Theme.textMuted
                                    }
                                }
                            }
                        }
                    }

                    SettingsNetwork { visible: root.page === "network"; active: root.open && visible; width: parent.width }
                    SettingsBluetooth { visible: root.page === "bluetooth"; active: root.open && visible; width: parent.width }
                    SettingsSound { visible: root.page === "sound"; width: parent.width }
                    SettingsDisplay { visible: root.page === "display"; width: parent.width }
                    SettingsInput { visible: root.page === "input"; width: parent.width }
                    SettingsPower { visible: root.page === "power"; active: root.open && visible; width: parent.width }
                    SettingsHotkeys { visible: root.page === "hotkeys"; active: root.open && visible; width: parent.width }

                    SettingsVersions {
                        visible: root.page === "versions"
                        active: root.open && visible
                        width: parent.width
                        onRun: script => root.asRoot(script)
                    }

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
                            text: "Fetch the newest version"
                            Button { text: "Update now"; onClicked: root.asRoot("sudo strix-update") }
                        }
                    }
                }
            }
        }
    }
}
