// The lock screen (LockScreen in StrixUI, left layout). Every lock shows another god than the
// desktop and the lock before; after unlocking the desktop's theme comes back from ThemeFile.
// Locked by `loginctl lock-session` (Super Escape, hypridle) through ipc: lock lock.
// What plays can be paused or skipped from the corner without unlocking.
// The password goes to PAM, service strix-lock.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
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
    /// Unlocked: the lock fades away before the session shows again
    property bool leaving: false
    /// Locked: what lies below changes without motion meanwhile
    readonly property bool active: sessionLock.locked

    function unlocked() {
        root.leaving = false
        // The desktop's theme back while the lock still covers it, so the wallpaper changes unseen
        if (root.themeFile) root.themeFile.reload()
        sessionLock.locked = false
    }

    function lock() {
        if (sessionLock.locked) return
        const choices = Theme.order.filter(g => g !== Theme.current && g !== root.lastGod)
        const god = choices[Math.floor(Math.random() * choices.length)]
        root.lastGod = god
        Theme.preview(god)
        root.error = ""
        root.tries = 0
        root.password = ""
        root.leaving = false
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
                root.leaving = true
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

    /// What plays, or played last: it can be paused or skipped without unlocking
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null

    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            id: surface
            color: Theme.background

            // Unlocking: everything grows a little and fades, then the session comes back
            Item {
                id: scene
                anchors.fill: parent
                opacity: root.leaving ? 0 : 1
                scale: root.leaving ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeIn } }
                Behavior on opacity {
                    SequentialAnimation {
                        NumberAnimation { duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeIn }
                        ScriptAction { script: if (root.leaving) root.unlocked() }
                    }
                }

                // The wallpaper settles from a little closer while the lock appears
                Wallpaper {
                    anchors.fill: parent
                    dim: true
                    NumberAnimation on scale { from: 1.04; to: 1; duration: Theme.durReveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                }

                Column {
                    anchors { left: parent.left; leftMargin: Theme.space8 * 2; verticalCenter: parent.verticalCenter }
                    spacing: Theme.space3
                    width: 320

                    // The owl of the god shown, which blinks now and then and at a wrong password
                    Owl {
                        id: owl
                        dir: Quickshell.env("STRIX_LOGOS") || ""
                        width: 128
                        height: 128
                        Entrance { delay: 0 }
                        // A wrong password: it shuts its eyes while the field shakes
                        Connections {
                            target: root
                            function onTriesChanged() { if (root.tries > 0) owl.blink() }
                        }
                    }
                    Timer {
                        // The first blink once everything has arrived, then every 6 to 12 seconds
                        interval: Theme.durReveal + 400
                        repeat: true
                        running: sessionLock.locked && !root.leaving
                        onRunningChanged: if (running) interval = Theme.durReveal + 400
                        onTriggered: {
                            owl.blink()
                            interval = 6000 + Math.random() * 6000
                        }
                    }
                    Item { width: 1; height: Theme.space2 }

                    // The hour and the minute roll when they change; everything arrives one after the other
                    Ticker { textStyle: "clock"; color: Theme.text; text: Qt.formatDateTime(clock.date, "HH"); Entrance { delay: 0 } }
                    Ticker { textStyle: "clock"; color: Theme.textMuted; text: Qt.formatDateTime(clock.date, "mm"); Entrance { delay: Theme.stagger * 2 } }
                    Label { textStyle: "subtitle"; color: Theme.text; text: Qt.formatDateTime(clock.date, "dddd, d MMMM"); Entrance { delay: Theme.stagger * 4 } }
                    Label {
                        Entrance { delay: Theme.stagger * 5 }
                        textStyle: "aside"
                        color: Theme.textMuted
                        font.letterSpacing: 1.6
                        readonly property int hour: clock.date.getHours()
                        text: (hour < 5 ? "good night" : hour < 12 ? "good morning" : hour < 18 ? "good afternoon" : "good evening")
                            + (Quickshell.env("USER") ? ", " + Quickshell.env("USER") : "")
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

                    Entrance { target: field; delay: Theme.stagger * 7 }

                    Row {
                        Entrance { delay: Theme.stagger * 8 }
                        spacing: Theme.space2
                        IconButton { iconName: "moon"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
                        IconButton { iconName: "rotate-cw"; onClicked: Quickshell.execDetached(["systemctl", "reboot"]) }
                        IconButton { iconName: "power"; danger: true; onClicked: Quickshell.execDetached(["systemctl", "poweroff"]) }
                    }
                }

                Column {
                    anchors { right: parent.right; bottom: parent.bottom; margins: Theme.space8 }
                    spacing: Theme.space2

                    // The music, quietly in the corner: title, artist and the three controls
                    Column {
                        visible: !!root.player
                        anchors.right: parent.right
                        spacing: Theme.space1
                        Entrance { delay: Theme.stagger * 6 }
                        Label {
                            anchors.right: parent.right
                            width: Math.min(implicitWidth, 320)
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                            textStyle: "aside"
                            color: Theme.text
                            text: root.player ? root.player.trackTitle || root.player.identity : ""
                        }
                        Label {
                            anchors.right: parent.right
                            width: Math.min(implicitWidth, 320)
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                            visible: text !== ""
                            textStyle: "caption"
                            color: Theme.textMuted
                            text: root.player ? root.player.trackArtist || "" : ""
                        }
                        Row {
                            anchors.right: parent.right
                            spacing: Theme.space1
                            IconButton {
                                iconName: "skip-back"
                                enabled: !!root.player && root.player.canGoPrevious
                                onClicked: root.player.previous()
                            }
                            IconButton {
                                iconName: root.player && root.player.isPlaying ? "pause" : "play"
                                enabled: !!root.player && root.player.canTogglePlaying
                                onClicked: root.player.togglePlaying()
                            }
                            IconButton {
                                iconName: "skip-forward"
                                enabled: !!root.player && root.player.canGoNext
                                onClicked: root.player.next()
                            }
                        }
                        Item { width: 1; height: Theme.space4 }
                    }

                    Wordmark { anchors.right: parent.right }
                }
            }
        }
    }
}
