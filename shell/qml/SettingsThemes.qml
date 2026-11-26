// Settings › Themes: the god of the machine and of this session, whether it changes every ten
// minutes, the effect of the terminal and the clock of the desktop, and the theme repositories.
// The theme service of the session (Backend "theme") answers for the first ones; repositories
// change the machine (strix-theme repos): they run in a terminal with sudo, where the progress
// stays readable, and the list is read again after.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix
import Strix.Shell

Column {
    id: page

    /// The window of Settings
    property var settings
    /// The theme picker of the shell
    property var picker
    property bool active: false
    property var themeState: null
    property var repos: []
    /// Theme repositories change the machine: only an administrator (wheel) connects, updates,
    /// removes them or lets them into the change of gods
    property bool admin: false

    /// A command that needs root, for the terminal of Settings
    signal run(string script)

    spacing: Theme.space2

    function refresh() {
        themes.call("state", {}, s => page.themeState = s)
        reposList.running = true
        groups.running = true
    }
    onActiveChanged: if (active) refresh()
    // A repository changed in the terminal: read the list again
    Connections {
        target: page.settings
        ignoreUnknownSignals: true
        function onRanAsRoot() { reposList.running = true }
    }

    function quoted(text) {
        return "'" + text.replace(/'/g, "'\\''") + "'"
    }

    Backend {
        id: themes
        service: "theme"
        onEvent: (name, data) => { if (name === "changed") page.themeState = data }
    }

    Process {
        id: reposList
        command: ["strix-theme", "repos", "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.repos = JSON.parse(text) } catch (e) { page.repos = [] }
            }
        }
    }

    Process {
        id: groups
        command: ["id", "-nG"]
        stdout: StdioCollector {
            onStreamFinished: page.admin = text.trim().split(/\s+/).indexOf("wheel") >= 0
        }
    }

    Label { textStyle: "title"; color: Theme.text; text: "Themes" }

    SettingRow {
        width: parent.width
        title: "Theme"
        text: page.themeState
            ? "The machine starts with " + (page.themeState.system || "").split(":")[0]
              + "; this session shows " + page.themeState.theme
            : "The theme service of the session is not running"
        Button {
            text: "Choose a theme"
            onClicked: { page.settings.open = false; if (page.picker) page.picker.show() }
        }
    }

    SettingRow {
        width: parent.width
        title: "Keep this theme"
        text: "No change to another god every 10 minutes"
        Switch {
            checked: !!(page.themeState && page.themeState.keep)
            enabled: page.themeState !== null
            onToggled: themes.call("keep", { keep: checked }, s => page.themeState = s)
        }
    }

    SettingRow {
        width: parent.width
        title: "Effect of the terminal"
        text: "Fine lines in the accent behind the text, with a slow light passing over them. It moves only in the terminal that has the focus."
        Switch {
            checked: !!(page.themeState && page.themeState.effect)
            enabled: page.themeState !== null
            onToggled: themes.call("effect", { effect: checked }, s => page.themeState = s)
        }
    }

    SettingRow {
        width: parent.width
        title: "Clock on the desktop"
        text: "Time and date beside the god, and what plays with its sound as bars"
        Switch {
            checked: Desktop.clock
            onToggled: Desktop.setClock(checked)
        }
    }

    Item { width: 1; height: Theme.space4 }
    Label { textStyle: "subtitle"; color: Theme.text; text: "Theme repositories" }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.textMuted
        text: "Themes from outside, in Git repositories with the layout of strix-theme-template. Every update fetches them; a commit that fails the check is not taken. They stay out of the change of gods until it is turned on for their repository."
              + (page.admin ? "" : " Only an administrator can change them.")
    }

    Label {
        visible: page.repos.length === 0
        textStyle: "body"
        color: Theme.textFaint
        text: "No theme repository is connected."
    }

    Repeater {
        model: page.repos
        Card {
            required property var modelData
            width: page.width
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
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        textStyle: "caption"
                        color: Theme.textMuted
                        text: "In the change of gods"
                    }
                    Switch {
                        checked: !!modelData.cycle
                        enabled: page.admin
                        onToggled: page.run("sudo strix-theme repos cycle " + page.quoted(modelData.url)
                            + (checked ? " on" : " off"))
                    }
                }
                Row {
                    visible: page.admin
                    spacing: Theme.space2
                    Button {
                        text: "Update now"
                        onClicked: page.run("sudo strix-update --themes " + page.quoted(modelData.name || modelData.url))
                    }
                    Button {
                        variant: "danger"
                        text: "Remove"
                        onClicked: page.run("sudo strix-theme repos remove " + page.quoted(modelData.url)
                            + " && sudo strix-rebuild switch")
                    }
                }
            }
        }
    }

    Row {
        visible: page.admin
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
                page.run("sudo strix-theme repos add " + page.quoted(address.text.trim())
                    + " && sudo strix-rebuild switch")
                address.text = ""
            }
        }
    }
}
