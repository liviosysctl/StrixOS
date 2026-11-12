// The login of Strix (12-desktop, step 11): greetd runs it as the user greeter, in cage, before
// anyone is logged in. It looks like the lock screen (LockScreen in StrixUI, left layout) in the
// machine's theme, asks for the name and the password, and starts the same Hyprland session
// through UWSM that tuigreet started before.
//
//   cage -s -- qs -c strix-greeter
//
// Enter in the name goes to the password, Enter in the password logs in. The last name is kept
// in GREETER_STATE (a folder of the greeter user).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import Strix
import Strix.Shell

ShellRoot {
    id: root

    property string error: ""
    property bool busy: false
    property string password: ""
    /// A field of the window takes keys
    property bool fieldReady: false
    readonly property string stateDir: Quickshell.env("GREETER_STATE") || ""
    readonly property var session: (Quickshell.env("GREETER_SESSION") || "uwsm start -e -D Hyprland hyprland.desktop").split(" ")

    function login() {
        if (root.busy || user.text === "") return
        root.error = ""
        root.busy = true
        root.password = pass.text
        pass.text = ""
        Greetd.createSession(user.text)
    }

    ThemeFile {}

    // The name of the last login
    FileView {
        id: last
        path: root.stateDir !== "" ? root.stateDir + "/last-user" : ""
        printErrors: false
        onLoaded: if (user.text === "") user.text = text().trim()
    }

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            if (responseRequired) {
                Greetd.respond(root.password)
                root.password = ""
            } else if (error) {
                root.error = message
            }
        }
        function onAuthFailure(message) {
            root.busy = false
            root.error = "Wrong name or password"
            pass.shake()
        }
        function onError(error) {
            // After a wrong password Quickshell ends the session itself and greetd answers that
            // with an error of its own: keep the message about the password
            root.busy = false
            if (root.error === "") root.error = error
        }
        function onReadyToLaunch() {
            if (root.stateDir !== "") last.setText(user.text + "\n")
            Greetd.launch(root.session, [], true)
        }
    }

    IpcHandler {
        target: "greeter"
        function state(): string { return GreetdState.toString(Greetd.state) }
        function error(): string { return root.error }
        function ready(): bool { return root.fieldReady }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    FloatingWindow {
        id: window
        color: Theme.background
        title: "Strix"

        Wallpaper { anchors.fill: parent; dim: true }

        Column {
            anchors { left: parent.left; leftMargin: Theme.space8 * 2; verticalCenter: parent.verticalCenter }
            spacing: Theme.space3
            width: 320

            Label { textStyle: "clock"; color: Theme.text; text: Qt.formatDateTime(clock.date, "HH") }
            Label { textStyle: "clock"; color: Theme.textMuted; text: Qt.formatDateTime(clock.date, "mm") }
            Label { textStyle: "subtitle"; color: Theme.text; text: Qt.formatDateTime(clock.date, "dddd, d MMMM") }
            Label {
                textStyle: "aside"
                color: Theme.textMuted
                font.letterSpacing: 1.6
                readonly property int hour: clock.date.getHours()
                text: hour < 5 ? "good night" : hour < 12 ? "good morning" : hour < 18 ? "good afternoon" : "good evening"
            }

            Item { width: 1; height: Theme.space4 }

            TextField {
                id: user
                width: parent.width
                shape: "line"
                placeholderText: "Name"
                enabled: !root.busy
                onAccepted: pass.field.forceActiveFocus()
            }

            TextField {
                id: pass
                width: parent.width
                shape: "line"
                echoMode: TextInput.Password
                placeholderText: root.busy ? "Logging in" : "Password"
                enabled: !root.busy
                error: root.error
                onAccepted: root.login()
            }

            Binding { target: root; property: "fieldReady"; value: user.field.activeFocus || pass.field.activeFocus }

            // The window gets the keyboard only once it is shown: the name first, or the
            // password when the name is already there
            Timer {
                interval: 150
                repeat: true
                running: !root.busy && !user.field.activeFocus && !pass.field.activeFocus
                onTriggered: (user.text === "" ? user : pass).field.forceActiveFocus()
            }

            Row {
                spacing: Theme.space2
                IconButton { iconName: "moon"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
                IconButton { iconName: "rotate-cw"; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
                IconButton { iconName: "power"; danger: true; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
            }
        }

        Column {
            anchors { right: parent.right; bottom: parent.bottom; margins: Theme.space8 }
            Wordmark { anchors.right: parent.right }
        }

        Plate {
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: Theme.space6 }
            width: Math.min(parent.width / 2, 560)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Theme.about.plate || ""
        }
    }
}
