// The lock screen (LockScreen in StrixUI, left layout). Every lock shows another god than the
// desktop and the lock before; after unlocking the desktop's theme comes back from ThemeFile.
// Locked by `loginctl lock-session` (Super Escape, hypridle) through ipc: lock lock.
// The password goes to PAM, service strix-lock.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Strix

Scope {
    id: root

    /// ThemeFile of the shell, read again after unlocking
    property var themeFile
    property string lastGod: ""
    property string password: ""
    property string error: ""
    property int tries: 0
    property bool busy: false
    /// Seconds until the next try after three wrong ones
    property int wait: 0
    /// The compositor shows the lock and the password field takes keys
    property bool fieldReady: false

    function lock() {
        if (sessionLock.locked) return
        const choices = Theme.order.filter(g => g !== Theme.current && g !== root.lastGod)
        const god = choices[Math.floor(Math.random() * choices.length)]
        root.lastGod = god
        Theme.preview(god)
        root.error = ""
        root.tries = 0
        root.password = ""
        sessionLock.locked = true
    }

    function tryUnlock(text) {
        if (root.busy || root.wait > 0 || text === "") return
        root.password = text
        root.busy = true
        root.error = ""
        pam.start()
    }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock() }
        function locked(): bool { return sessionLock.locked }
        function ready(): bool { return sessionLock.secure && root.fieldReady }
        function error(): string { return root.error }
    }

    PamContext {
        id: pam
        config: "strix-lock"
        onPamMessage: {
            if (responseRequired) respond(root.password)
        }
        onCompleted: result => {
            root.busy = false
            root.password = ""
            if (result === PamResult.Success) {
                sessionLock.locked = false
                if (root.themeFile) root.themeFile.reload()
                return
            }
            root.tries += 1
            if (root.tries >= 3) {
                root.wait = 30
                root.error = "Too many tries"
            } else {
                root.error = "Wrong password"
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.wait > 0
        onTriggered: {
            root.wait -= 1
            if (root.wait === 0) {
                root.tries = 0
                root.error = ""
            }
        }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            color: Theme.background

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
                    text: (hour < 5 ? "good night" : hour < 12 ? "good morning" : hour < 18 ? "good afternoon" : "good evening")
                        + ", " + (Quickshell.env("USER") || "")
                }

                Item { width: 1; height: Theme.space4 }

                TextField {
                    id: field
                    width: parent.width
                    shape: "line"
                    echoMode: TextInput.Password
                    placeholderText: root.wait > 0 ? "Try again in " + root.wait + " s" : "Password"
                    enabled: !root.busy && root.wait === 0
                    error: root.error
                    // The surface gets the keyboard only once it is shown, and a disabled field
                    // loses focus while PAM checks: take it back whenever it is missing
                    Timer {
                        interval: 150
                        repeat: true
                        running: sessionLock.locked && field.enabled && !field.field.activeFocus
                        onTriggered: field.field.forceActiveFocus()
                    }
                    Binding { target: root; property: "fieldReady"; value: field.field.activeFocus && field.enabled }
                    onAccepted: {
                        root.tryUnlock(field.text)
                        field.text = ""
                    }
                    Connections {
                        target: root
                        function onErrorChanged() { if (root.error !== "") field.shake() }
                    }
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
                spacing: Theme.space2
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
}
