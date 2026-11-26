// Settings (12-desktop, step 12): a window with a first page of cards and the pages Themes,
// Network, Bluetooth, Sound, Display, Input, Power, Hotkeys, Account, Date and time, Default
// apps, Storage, Printers, Versions and About; each page but About is its own file.
// Opened by strix-settings [PAGE [ROW]] (ipc: settings open), from Search or the system menu.
// What needs root runs in Ghostty with sudo (asRoot), where the progress stays readable.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix
import Strix.Shell

Scope {
    id: root

    /// The theme picker of the shell
    property var picker
    property bool open: false
    /// "home" is the first page: every other page with a line about it
    property string page: "home"
    property string row: ""
    /// The theme repositories, as the Themes page read them
    property var repos: []
    property string version: ""
    readonly property var pages: [
        { id: "themes", title: "Themes", icon: "palette", about: "The god of the session, the change every ten minutes, the clock of the desktop" },
        { id: "network", title: "Network", icon: "wifi", about: "Wi-Fi and wired networks" },
        { id: "bluetooth", title: "Bluetooth", icon: "bluetooth", about: "Devices to pair and connect" },
        { id: "sound", title: "Sound", icon: "volume-2", about: "Outputs, inputs and their volume" },
        { id: "display", title: "Display", icon: "monitor", about: "Screens, their size, place and scale, the night light" },
        { id: "input", title: "Input", icon: "mouse", about: "Keyboard layouts, mouse and touchpad" },
        { id: "power", title: "Power", icon: "zap", about: "What happens when nobody is at the machine, and the lid" },
        { id: "hotkeys", title: "Hotkeys", icon: "keyboard", about: "Every key, and keys of your own" },
        { id: "account", title: "Account", icon: "shield", about: "Your password, your name for Git, your SSH key" },
        { id: "time", title: "Date and time", icon: "clock", about: "The time zone and the clock of the internet" },
        { id: "apps", title: "Default apps", icon: "layout-grid", about: "Which app opens links, text, pictures, music" },
        { id: "storage", title: "Storage", icon: "hard-drive", about: "What the disk holds, the trash, snapshots of your home" },
        { id: "printers", title: "Printers", icon: "file", about: "The printers on this machine and the network" },
        { id: "versions", title: "Versions", icon: "history", about: "The versions still installed, what they changed, going back" },
        { id: "about", title: "About", icon: "info", about: "This machine and the distribution" }
    ]

    function show(page, row) {
        root.page = root.pages.some(p => p.id === page) ? page : "home"
        root.row = row || ""
        root.used = true
        root.open = true
    }

    /// A command that needs root, in a terminal that stays open; the list is read again after
    function asRoot(script) {
        terminal.command = ["ghostty", "--wait-after-command=true", "-e", "sh", "-c", script]
        terminal.running = true
    }

    /// The terminal of asRoot ended: the pages read what it changed again
    signal ranAsRoot()

    Process {
        id: terminal
        onExited: root.ranAsRoot()
    }

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
        function repositories(): int { return root.repos.length }
    }

    // The window and its pages are built the first time Settings is opened, not with the shell:
    // most sessions never see them
    property bool used: false
    LazyLoader {
        active: root.used

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
                        // The selection glides from page to page
                        Item {
                            width: parent.width
                            height: nav.height
                            // count: the rows are made after this binding is first read
                            Glide { target: navRows.count > 0 ? navRows.itemAt(root.pages.findIndex(p => p.id === root.page)) : null }
                            Column {
                                id: nav
                                width: parent.width
                                spacing: Theme.space1
                                Repeater {
                                    id: navRows
                                    model: root.pages
                                    ListRow {
                                        required property var modelData
                                        width: parent.width
                                        text: modelData.title
                                        iconName: modelData.icon
                                        selected: root.page === modelData.id
                                        glide: true
                                        onClicked: root.page = modelData.id
                                    }
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
                        x: Theme.space5
                        y: Theme.space5
                        // A new page comes in from the side it lies on in the list
                        transform: Translate { id: pageShift }
                        property int lastIndex: 0
                        Connections {
                            target: root
                            function onPageChanged() {
                                const now = root.pages.findIndex(p => p.id === root.page)
                                pageIn.direction = now >= content.lastIndex ? 1 : -1
                                content.lastIndex = now
                                pageIn.restart()
                            }
                        }
                        ParallelAnimation {
                            id: pageIn
                            property int direction: 1
                            NumberAnimation { target: pageShift; property: "y"; from: pageIn.direction * Theme.space3; to: 0; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                            NumberAnimation { target: content; property: "opacity"; from: 0; to: 1; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                        }
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

                        SettingsThemes {
                            visible: root.page === "themes"
                            active: root.open && visible
                            width: parent.width
                            settings: root
                            picker: root.picker
                            onRun: script => root.asRoot(script)
                            onReposChanged: root.repos = repos
                        }

                        SettingsNetwork { visible: root.page === "network"; active: root.open && visible; width: parent.width }
                        SettingsBluetooth { visible: root.page === "bluetooth"; active: root.open && visible; width: parent.width }
                        SettingsSound { visible: root.page === "sound"; width: parent.width }
                        SettingsDisplay { visible: root.page === "display"; width: parent.width }
                        SettingsInput { visible: root.page === "input"; width: parent.width }
                        SettingsPower { visible: root.page === "power"; active: root.open && visible; width: parent.width }
                        SettingsHotkeys { visible: root.page === "hotkeys"; active: root.open && visible; width: parent.width }
                        SettingsAccount {
                            visible: root.page === "account"
                            active: root.open && visible
                            width: parent.width
                            onRun: script => root.asRoot(script)
                        }
                        SettingsTime {
                            visible: root.page === "time"
                            active: root.open && visible
                            width: parent.width
                            onRun: script => root.asRoot(script)
                        }
                        SettingsApps { visible: root.page === "apps"; active: root.open && visible; width: parent.width }
                        SettingsStorage {
                            visible: root.page === "storage"
                            active: root.open && visible
                            width: parent.width
                            onRun: script => root.asRoot(script)
                        }
                        SettingsPrinters { visible: root.page === "printers"; active: root.open && visible; width: parent.width }

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
                            Row {
                                spacing: Theme.space4
                                // The owl in the colours of the god shown; a click makes it blink
                                Owl {
                                    id: aboutOwl
                                    dir: Quickshell.env("STRIX_LOGOS") || ""
                                    width: 96
                                    height: 96
                                    MouseArea { anchors.fill: parent; onClicked: aboutOwl.blink() }
                                }
                                Wordmark { anchors.verticalCenter: parent.verticalCenter }
                            }
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
}
