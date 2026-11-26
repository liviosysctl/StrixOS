// Settings in the proof of concept: a first page that lists every page in two groups (Devices:
// Network, Bluetooth, Display, Sound, Input; System: Power, Hotkeys, Versions, About), as on main;
// each page but About is its own file. The pages stand in a column of a readable width in the
// middle of the window. The theme is fixed, so there is no page for themes. About also starts the
// tour (Tour.qml) and turns its question at login on and off.
// Opened by strix-settings [PAGE [ROW]] (ipc: settings open), from Search or the system menu.
// Hotkeys: every key, from the search service (Backend "search", hotkeys), changed one by one.
import QtQuick
import QtQuick.Templates as T
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
    /// The groups of the pages, in the order of the first page and the list at the side
    readonly property var groups: [
        { id: "devices", title: "Devices" },
        { id: "system", title: "System" }
    ]
    readonly property var pages: [
        { id: "network", group: "devices", title: "Network", icon: "wifi", about: "Wi-Fi and wired networks" },
        { id: "bluetooth", group: "devices", title: "Bluetooth", icon: "bluetooth", about: "Devices to pair and connect" },
        { id: "display", group: "devices", title: "Display", icon: "monitor", about: "Screens, size, place and scale, the night light" },
        { id: "sound", group: "devices", title: "Sound", icon: "volume-2", about: "Outputs, inputs and their volume" },
        { id: "input", group: "devices", title: "Input", icon: "mouse", about: "Keyboard layouts, mouse and touchpad" },
        { id: "power", group: "system", title: "Power", icon: "zap", about: "When the screen dims and locks, and the lid" },
        { id: "hotkeys", group: "system", title: "Hotkeys", icon: "keyboard", about: "Every key, and keys of your own" },
        { id: "versions", group: "system", title: "Versions", icon: "history", about: "Installed versions, what changed, going back" },
        { id: "about", group: "system", title: "About", icon: "info", about: "This machine and the distribution" }
    ]
    /// The widest the pages get: lines stay short enough to read and a switch stays near its words
    readonly property int measure: 720


    /// A page on the first page: its symbol, its name and a line about it
    component PageLink: T.ItemDelegate {
        id: link
        required property var page

        // The hand over what can be pressed, as on every clickable part of the shell
        HoverHandler { cursorShape: Qt.PointingHandCursor }

        implicitHeight: Theme.control + 2 * Theme.space3
        padding: Theme.space3
        hoverEnabled: true
        focusPolicy: Qt.StrongFocus

        contentItem: Row {
            spacing: Theme.space3
            Icon {
                name: link.page.icon
                color: link.hovered || link.visualFocus ? Theme.text : Theme.textMuted
                hovered: link.hovered
                anchors.verticalCenter: parent.verticalCenter
            }
            Column {
                width: parent.width - Theme.icon - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                Label { width: parent.width; textStyle: "heading"; color: Theme.text; text: link.page.title; elide: Text.ElideRight }
                Label { width: parent.width; textStyle: "caption"; color: Theme.textMuted; text: link.page.about; elide: Text.ElideRight }
            }
        }

        background: Rectangle {
            radius: Theme.radiusMd
            color: link.down ? Theme.surfaceSunken : link.hovered ? Theme.surfaceRaised : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
            FocusRing { target: link }
        }
    }

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

    // The answer to the tour's question at login (Tour.qml keeps it): it asks unless done or never
    FileView {
        id: tourFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/strix/tour"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.tourAnswer = text().trim()
        onLoadFailed: root.tourAnswer = ""
    }
    property string tourAnswer: ""

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
                    // A gap parts the groups
                    Repeater {
                        model: root.pages
                        Item {
                            id: navItem
                            required property var modelData
                            required property int index
                            readonly property int gap: index > 0 && root.pages[index - 1].group !== modelData.group ? Theme.space4 : 0
                            width: parent.width
                            height: gap + Theme.control
                            ListRow {
                                y: navItem.gap
                                width: parent.width
                                text: navItem.modelData.title
                                iconName: navItem.modelData.icon
                                selected: root.page === navItem.modelData.id
                                onClicked: root.page = navItem.modelData.id
                            }
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
                    x: (parent.width - width) / 2
                    y: Theme.space5
                    width: Math.min(parent.width - 2 * Theme.space5, root.measure)
                    spacing: Theme.space4

                    // ------------------------------------------------ the first page
                    // The text stands on the line of the symbols; the ground of a page under the
                    // pointer reaches out to the left of it
                    Column {
                        visible: root.page === "home"
                        width: parent.width
                        spacing: Theme.space5

                        Column {
                            x: Theme.space3
                            width: parent.width - Theme.space3
                            Label { textStyle: "title"; color: Theme.text; text: "Settings" }
                            Label {
                                width: parent.width
                                textStyle: "caption"
                                color: Theme.textMuted
                                text: root.version + ". Search finds every single setting by its name."
                            }
                        }

                        Repeater {
                            model: root.groups
                            Column {
                                id: group
                                required property var modelData
                                width: parent.width
                                spacing: Theme.space1
                                Label { x: Theme.space3; textStyle: "aside"; color: Theme.textMuted; text: group.modelData.title }
                                Grid {
                                    id: links
                                    width: parent.width
                                    columns: 2
                                    columnSpacing: Theme.space3
                                    Repeater {
                                        model: root.pages.filter(p => p.group === group.modelData.id)
                                        PageLink {
                                            required property var modelData
                                            width: (links.width - links.columnSpacing) / 2
                                            page: modelData
                                            onClicked: root.page = modelData.id
                                        }
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
                        SettingRow {
                            width: parent.width
                            title: "Tour"
                            text: "The search, the keys, the Store and Settings, opened one after the other and explained"
                            Button {
                                text: "Start the tour"
                                onClicked: {
                                    root.open = false
                                    Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "tour", "start"])
                                }
                            }
                        }
                        SettingRow {
                            width: parent.width
                            title: "Offer the tour at login"
                            text: "Asks once after the next login whether to show it"
                            Switch {
                                checked: root.tourAnswer !== "done" && root.tourAnswer !== "never"
                                onToggled: {
                                    root.tourAnswer = checked ? "later" : "never"
                                    tourFile.setText(root.tourAnswer + "\n")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
