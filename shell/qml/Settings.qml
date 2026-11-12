// Settings (12-desktop, step 12): a window with the pages Themes, Network, Bluetooth, Sound,
// Display, Power, Hotkeys and About; each page but Themes and About is its own file.
// Opened by strix-settings [PAGE [ROW]] (ipc: settings open), from Search or the system menu.
//
// Themes: the machine's theme and Keep (the session's theme service, Backend "theme"), and the
// theme repositories (strix-theme repos). Changes to repositories need root and a rebuild: they
// run in Ghostty with sudo, where the progress stays readable, and the list is read again after.
// Hotkeys: every key, from the search service (Backend "search", hotkeys), changed one by one.
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
    property string page: "themes"
    property string row: ""
    property var themeState: null
    property var repos: []
    property string version: ""
    readonly property var pages: [
        { id: "themes", title: "Themes", icon: "palette" },
        { id: "network", title: "Network", icon: "wifi" },
        { id: "bluetooth", title: "Bluetooth", icon: "bluetooth" },
        { id: "sound", title: "Sound", icon: "volume-2" },
        { id: "display", title: "Display", icon: "monitor" },
        { id: "power", title: "Power", icon: "zap" },
        { id: "hotkeys", title: "Hotkeys", icon: "keyboard" },
        { id: "about", title: "About", icon: "info" }
    ]

    function show(page, row) {
        root.page = root.pages.some(p => p.id === page) ? page : "themes"
        root.row = row || ""
        root.open = true
        root.refresh()
    }

    function refresh() {
        themes.call("state", {}, s => root.themeState = s)
        reposList.running = true
    }

    /// A command that needs root, in a terminal that stays open; the list is read again after
    function asRoot(script) {
        terminal.command = ["ghostty", "--wait-after-command=true", "-e", "sh", "-c", script]
        terminal.running = true
    }

    function quoted(text) {
        return "'" + text.replace(/'/g, "'\\''") + "'"
    }

    Backend {
        id: themes
        service: "theme"
        onEvent: (name, data) => { if (name === "changed") root.themeState = data }
    }

    Process {
        id: reposList
        command: ["strix-theme", "repos", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.repos = JSON.parse(text) } catch (e) { root.repos = [] }
            }
        }
    }

    Process {
        id: terminal
        onExited: reposList.running = true
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

    FloatingWindow {
        visible: root.open
        title: "Settings"
        implicitWidth: 920
        implicitHeight: 620
        color: Theme.background
        onVisibleChanged: if (!visible) root.open = false

        Row {
            anchors.fill: parent

            // The pages
            Rectangle {
                width: 220
                height: parent.height
                color: Theme.surface
                Column {
                    anchors { fill: parent; margins: Theme.space4 }
                    spacing: Theme.space1
                    Label { textStyle: "title"; color: Theme.text; text: "Settings"; bottomPadding: Theme.space3 }
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
                contentHeight: content.implicitHeight + Theme.space6 * 2
                clip: true

                Column {
                    id: content
                    x: Theme.space6
                    y: Theme.space6
                    width: parent.width - Theme.space6 * 2
                    spacing: Theme.space4

                    // ------------------------------------------------ Themes
                    Column {
                        visible: root.page === "themes"
                        width: parent.width
                        spacing: Theme.space2

                        Label { textStyle: "title"; color: Theme.text; text: "Themes" }

                        SettingRow {
                            width: parent.width
                            title: "Theme"
                            text: root.themeState
                                ? "The machine starts with " + (root.themeState.system || "").split(":")[0]
                                  + "; this session shows " + root.themeState.theme
                                : "The theme service of the session is not running"
                            Button {
                                text: "Choose a theme"
                                onClicked: { root.open = false; if (root.picker) root.picker.show() }
                            }
                        }

                        SettingRow {
                            width: parent.width
                            title: "Keep this theme"
                            text: "No change to another god every 10 minutes"
                            Switch {
                                checked: !!(root.themeState && root.themeState.keep)
                                enabled: root.themeState !== null
                                onToggled: themes.call("keep", { keep: checked }, s => root.themeState = s)
                            }
                        }

                        Item { width: 1; height: Theme.space4 }
                        Label { textStyle: "subtitle"; color: Theme.text; text: "Theme repositories" }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            textStyle: "caption"
                            color: Theme.textMuted
                            text: "Themes from outside, in Git repositories with the layout of strix-theme-template. Every update fetches them; a commit that fails the check is not taken."
                        }

                        Label {
                            visible: root.repos.length === 0
                            textStyle: "body"
                            color: Theme.textFaint
                            text: "No theme repository is connected."
                        }

                        Repeater {
                            model: root.repos
                            Card {
                                required property var modelData
                                width: content.width
                                title: modelData.name || modelData.url
                                text: modelData.url + "\n" + "commit " + (modelData.rev || "-").slice(0, 7)
                                      + " · " + (modelData.themes || []).join(", ")
                                Column {
                                    width: parent.width
                                    spacing: Theme.space2
                                    Label {
                                        visible: !!modelData.problem
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        textStyle: "caption"
                                        color: Theme.error
                                        text: modelData.problem || ""
                                    }
                                    Row {
                                        spacing: Theme.space2
                                        Button {
                                            small: true
                                            text: "Update now"
                                            onClicked: root.asRoot("sudo strix-update --themes " + root.quoted(modelData.name || modelData.url))
                                        }
                                        Button {
                                            small: true
                                            variant: "danger"
                                            text: "Remove"
                                            onClicked: root.asRoot("sudo strix-theme repos remove " + root.quoted(modelData.url)
                                                + " && sudo strix-rebuild switch")
                                        }
                                    }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.space2
                            TextField {
                                id: address
                                width: parent.width - connect.width - Theme.space2
                                placeholderText: "owner/strix-theme-name or an https:// address"
                                onAccepted: connect.clicked()
                            }
                            Button {
                                id: connect
                                text: "Connect"
                                variant: "primary"
                                enabled: address.text.trim() !== ""
                                onClicked: {
                                    root.asRoot("sudo strix-theme repos add " + root.quoted(address.text.trim())
                                        + " && sudo strix-rebuild switch")
                                    address.text = ""
                                }
                            }
                        }
                    }

                    SettingsNetwork { visible: root.page === "network"; active: root.open && visible; width: parent.width }
                    SettingsBluetooth { visible: root.page === "bluetooth"; active: root.open && visible; width: parent.width }
                    SettingsSound { visible: root.page === "sound"; width: parent.width }
                    SettingsDisplay { visible: root.page === "display"; width: parent.width }
                    SettingsPower { visible: root.page === "power"; width: parent.width }
                    SettingsHotkeys { visible: root.page === "hotkeys"; active: root.open && visible; width: parent.width }

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
