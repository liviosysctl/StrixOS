// Settings › Account: the login of this person. The password changes in a terminal with passwd,
// which asks for the old one first and changes the keyring with it. The name and email of Git
// are the global ones (git config --global). The SSH key is ~/.ssh/id_ed25519: copied as it is,
// or made in a terminal, where ssh-keygen asks for its passphrase; the agent keeps it after the
// first use.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix

Column {
    id: page

    property bool active: false
    property bool admin: false
    property string gitName: ""
    property string gitEmail: ""
    property string saved: ""

    /// A command for the terminal of Settings
    signal run(string script)

    readonly property string user: Quickshell.env("USER") || ""
    readonly property string keyFile: Quickshell.env("HOME") + "/.ssh/id_ed25519.pub"

    spacing: Theme.space2

    function refresh() {
        groups.running = true
        readName.running = true
        readEmail.running = true
        key.reload()
    }
    onActiveChanged: if (active) refresh()

    Process {
        id: groups
        command: ["id", "-nG"]
        stdout: StdioCollector { onStreamFinished: page.admin = text.trim().split(/\s+/).indexOf("wheel") >= 0 }
    }
    Process {
        id: readName
        command: ["git", "config", "--global", "user.name"]
        stdout: StdioCollector { onStreamFinished: { page.gitName = text.trim(); name.text = page.gitName } }
    }
    Process {
        id: readEmail
        command: ["git", "config", "--global", "user.email"]
        stdout: StdioCollector { onStreamFinished: { page.gitEmail = text.trim(); email.text = page.gitEmail } }
    }
    property string publicKey: ""
    FileView {
        id: key
        path: page.keyFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: page.publicKey = text().trim()
        onLoadFailed: page.publicKey = ""
    }

    Label { textStyle: "title"; color: Theme.text; text: "Account" }

    SettingRow {
        width: parent.width
        title: page.user
        text: page.admin ? "Administrator: may change the machine with your password" : "May not change the machine"
    }

    SettingRow {
        width: parent.width
        title: "Password"
        text: "The password of the login, the lock screen and the keyring; the old one is asked first"
        Button { text: "Change"; onClicked: page.run("passwd") }
    }

    Item { width: 1; height: Theme.space4 }
    Label { textStyle: "subtitle"; color: Theme.text; text: "Git" }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.textMuted
        text: "The name and the email every commit of yours carries."
    }
    Row {
        width: parent.width
        spacing: Theme.space2
        TextField {
            id: name
            width: (parent.width - save.width - 2 * Theme.space2) / 2
            placeholderText: "Name"
            onAccepted: save.clicked()
        }
        TextField {
            id: email
            width: (parent.width - save.width - 2 * Theme.space2) / 2
            placeholderText: "Email"
            onAccepted: save.clicked()
        }
        Button {
            id: save
            text: page.saved !== "" ? page.saved : "Save"
            variant: "primary"
            enabled: name.text.trim() !== page.gitName || email.text.trim() !== page.gitEmail
            onClicked: {
                if (name.text.trim() !== "") Quickshell.execDetached(["git", "config", "--global", "user.name", name.text.trim()])
                if (email.text.trim() !== "") Quickshell.execDetached(["git", "config", "--global", "user.email", email.text.trim()])
                page.gitName = name.text.trim()
                page.gitEmail = email.text.trim()
                page.saved = "Saved"
                savedTimer.restart()
            }
        }
        Timer { id: savedTimer; interval: 1600; onTriggered: page.saved = "" }
    }

    Item { width: 1; height: Theme.space4 }
    Label { textStyle: "subtitle"; color: Theme.text; text: "SSH key" }
    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.textMuted
        text: page.publicKey !== ""
            ? "Give this line to GitHub or a server to log in without a password."
            : "There is no key yet. One is made in a terminal, which asks for a passphrase to keep it safe."
    }
    Rectangle {
        visible: page.publicKey !== ""
        width: parent.width
        height: keyText.implicitHeight + 2 * Theme.space3
        radius: Theme.radiusMd
        color: Theme.alpha(Theme.text, 0.04)
        border.width: Theme.lineHair
        border.color: Theme.border
        Label {
            id: keyText
            x: Theme.space3
            y: Theme.space3
            width: parent.width - 2 * Theme.space3
            wrapMode: Text.WrapAnywhere
            textStyle: "caption"
            font.family: "IBM Plex Mono"
            color: Theme.textMuted
            text: page.publicKey
        }
    }
    Row {
        spacing: Theme.space2
        Button {
            visible: page.publicKey !== ""
            text: copied.running ? "Copied" : "Copy"
            onClicked: { Quickshell.execDetached(["wl-copy", page.publicKey]); copied.restart() }
            Timer { id: copied; interval: 1600 }
        }
        Button {
            visible: page.publicKey === ""
            text: "Make a key"
            variant: "primary"
            onClicked: page.run("ssh-keygen -t ed25519 -C \"$USER@$(hostname)\" -f ~/.ssh/id_ed25519")
        }
    }
}
