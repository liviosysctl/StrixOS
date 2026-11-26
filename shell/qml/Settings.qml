// Settings (12-desktop, step 12): a window with a first page that lists every page in three groups
// (Personal: Themes, Hotkeys, Default apps, Account; Devices: Network, Bluetooth, Display, Sound,
// Input, Printers; System: Power, Date and time, Storage, Versions, About); each page but About is
// its own file. The pages stand in a column of a readable width in the middle of the window.
// Opened by strix-settings [PAGE [ROW]] (ipc: settings open), from Search or the system menu.
// What needs root runs in Ghostty with sudo (asRoot), where the progress stays readable.
import QtQuick
import QtQuick.Templates as T
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
    /// The groups of the pages, in the order of the first page and the list at the side
    readonly property var groups: [
        { id: "personal", title: "Personal" },
        { id: "devices", title: "Devices" },
        { id: "system", title: "System" }
    ]
    readonly property var pages: [
        { id: "themes", group: "personal", title: "Themes", icon: "palette", about: "The god of the session, the terminal, the clock" },
        { id: "hotkeys", group: "personal", title: "Hotkeys", icon: "keyboard", about: "Every key, and keys of your own" },
        { id: "apps", group: "personal", title: "Default apps", icon: "layout-grid", about: "Which app opens links, text, pictures, music" },
        { id: "account", group: "personal", title: "Account", icon: "shield", about: "Your password, your name for Git, your SSH key" },
        { id: "network", group: "devices", title: "Network", icon: "wifi", about: "Wi-Fi and wired networks" },
        { id: "bluetooth", group: "devices", title: "Bluetooth", icon: "bluetooth", about: "Devices to pair and connect" },
        { id: "display", group: "devices", title: "Display", icon: "monitor", about: "Screens, size, place and scale, the night light" },
        { id: "sound", group: "devices", title: "Sound", icon: "volume-2", about: "Outputs, inputs and their volume" },
        { id: "input", group: "devices", title: "Input", icon: "mouse", about: "Keyboard layouts, mouse and touchpad" },
        { id: "printers", group: "devices", title: "Printers", icon: "file", about: "Printers on this machine and the network" },
        { id: "power", group: "system", title: "Power", icon: "zap", about: "When the screen dims and locks, and the lid" },
        { id: "time", group: "system", title: "Date and time", icon: "clock", about: "The time zone and the clock of the internet" },
        { id: "storage", group: "system", title: "Storage", icon: "hard-drive", about: "What the disk holds, the trash, home snapshots" },
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
                        // The selection glides from page to page; a gap parts the groups
                        Item {
                            width: parent.width
                            height: nav.height
                            // Where the row of the page is, below the gap that may open its group.
                            // count: the rows are made after this binding is first read
                            Item {
                                id: spot
                                readonly property Item at: navRows.count > 0 ? navRows.itemAt(root.pages.findIndex(p => p.id === root.page)) : null
                                x: at ? at.x : 0
                                y: at ? at.y + at.gap : 0
                                width: at ? at.width : 0
                                height: Theme.control
                                visible: !!at
                            }
                            Glide { target: spot }
                            Column {
                                id: nav
                                width: parent.width
                                spacing: Theme.space1
                                Repeater {
                                    id: navRows
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
                                            glide: true
                                            onClicked: root.page = navItem.modelData.id
                                        }
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
                        x: (parent.width - width) / 2
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
