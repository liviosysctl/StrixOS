// The tour of the proof of concept. At a login it asks whether to show the desktop: start it, not
// now (asked again at the next login) or never. It is live: each step opens the real thing (the
// search, the cheat sheet, the Store, Settings) and explains it in a bubble beside it; the next
// step closes it again. Every step can end the tour. In Settings (About) the question at login is
// turned on and off, and the tour started again.
// The answer is kept in $XDG_STATE_HOME/strix/tour: later, done or never; without the file it
// asks. The user service strix-welcome calls `qs -c strix ipc call tour offer` after the login,
// `tour start` starts it at once.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Strix

Scope {
    id: root

    /// The parts of the shell the tour opens (shell.qml)
    property var search: null
    property var cheatsheet: null
    property var store: null
    property var settings: null

    /// The bubble's window: the panels the tour opens keep their focus grab while it is clicked
    readonly property var window: bubble
    property bool asking: false
    /// The step shown, -1 while there is no tour
    property int step: -1
    readonly property bool running: step >= 0
    readonly property var current: running ? steps[step] : null

    /// The answer from the file, "" when there is none; known once the file was read
    property string answer: ""
    property bool known: false
    property bool offerWhenKnown: false

    readonly property var steps: [
        {
            title: "The bar",
            text: "Up here: the search, the clock with the month under it, the load of the machine and what is playing. The workspaces stand in the middle. On the right the network, the sound and the battery, each opening its page in Settings, then the notifications and the power.",
            keys: "",
            place: "top-left",
            open: ""
        },
        {
            title: "The search",
            text: "Everything starts here: apps, settings, files and commands, found as you type. Enter opens what is chosen. What the search does not find goes to the web, in Zen.",
            keys: "Super Space",
            place: "right",
            open: "search"
        },
        {
            title: "Windows and workspaces",
            text: "Super Return opens a terminal, Super E your files. Apps open side by side and share the screen: Super W closes one, Super F lets it fill the screen, Super T lets it float. There are nine workspaces, Super 1 to 9.",
            keys: "Super Return",
            place: "center",
            open: ""
        },
        {
            title: "Every key",
            text: "All the keys of the system on one sheet. Typing filters it, Esc closes it. Your own keys are made in Settings, under Hotkeys.",
            keys: "Super K",
            place: "bottom-right",
            open: "cheatsheet"
        },
        {
            title: "The Store",
            text: "Apps from nixpkgs, installed and removed with one click. Suggestions and categories to look around, the search finds every one. What the system brings along is marked as built in.",
            keys: "",
            place: "right",
            open: "store"
        },
        {
            title: "Settings",
            text: "Network, Bluetooth, sound, the screens, the keyboard, power, your hotkeys and the versions of the system. The search finds every single setting by its name.",
            keys: "",
            place: "right",
            open: "settings"
        },
        {
            title: "That is the tour",
            text: "The search and Super K are all you need to remember. The tour waits in Settings, under About, if you want to see it again.",
            keys: "Super Space",
            place: "center",
            open: ""
        }
    ]

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/strix/tour"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.learn(text().trim())
        onLoadFailed: root.learn("")
    }

    function learn(answer) {
        root.answer = answer
        root.known = true
        if (root.offerWhenKnown) {
            root.offerWhenKnown = false
            root.offer()
        }
    }

    function keep(answer) {
        root.answer = answer
        file.setText(answer + "\n")
    }

    /// The question at login, unless it was answered with done or never
    function offer() {
        if (!root.known) {
            root.offerWhenKnown = true
            return
        }
        if (root.running || root.answer === "done" || root.answer === "never") return
        root.asking = true
    }

    function start() {
        root.asking = false
        root.go(0)
    }

    /// Not now, never, or the end of the tour
    function stop(answer) {
        root.asking = false
        if (root.running) root.close(root.current.open)
        root.step = -1
        if (answer) root.keep(answer)
    }

    function go(index) {
        if (root.running) root.close(root.current.open)
        root.step = index
        root.reveal(root.current.open)
    }

    function reveal(part) {
        if (part === "search" && root.search) root.search.show(null)
        else if (part === "cheatsheet" && root.cheatsheet && !root.cheatsheet.open) root.cheatsheet.toggle()
        else if (part === "store" && root.store) root.store.show("")
        else if (part === "settings" && root.settings) root.settings.show("home", "")
        else return
        // A layer that opens later lies above the bubble: it is put up again, on top
        root.raise()
    }

    function close(part) {
        const target = { search: root.search, cheatsheet: root.cheatsheet, store: root.store, settings: root.settings }[part]
        if (target) target.open = false
    }

    property bool lowered: false
    function raise() {
        root.lowered = true
        raising.restart()
    }
    Timer { id: raising; interval: 120; onTriggered: root.lowered = false }

    IpcHandler {
        target: "tour"
        function offer(): void { root.offer() }
        function start(): void { root.start() }
        function stop(): void { root.stop(root.running ? "done" : "") }
        function isOpen(): bool { return root.asking || root.running }
        function answer(): string { return root.answer }
    }

    PanelWindow {
        id: bubble
        visible: (root.asking || root.running) && !root.lowered
        WlrLayershell.namespace: "strix-tour"
        WlrLayershell.layer: WlrLayer.Overlay
        // The tour never takes the keyboard: what it opened keeps it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        // Only the bubble takes the pointer; the rest of the screen goes on working
        mask: Region { item: card }

        Surface {
            id: card
            elevation: "pop"
            width: root.asking ? 420 : 360
            height: body.implicitHeight + 2 * Theme.space4

            readonly property string place: root.asking ? "center" : root.current ? root.current.place : "center"
            readonly property int margin: Theme.space5
            x: place === "top-left" ? Theme.space2
                : place === "right" || place === "bottom-right" ? parent.width - width - margin
                : (parent.width - width) / 2
            y: place === "top-left" ? Theme.barHeight + Theme.space2
                : place === "bottom-right" ? parent.height - height - margin
                : (parent.height - height) / 2

            Column {
                id: body
                x: Theme.space4
                y: Theme.space4
                width: parent.width - 2 * Theme.space4
                spacing: Theme.space2

                // ------------------------------------------------ the question at login
                Column {
                    visible: root.asking
                    width: parent.width
                    spacing: Theme.space2
                    Label { textStyle: "title"; color: Theme.text; text: "Welcome to Strix" }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        textStyle: "body"
                        color: Theme.textMuted
                        text: "A short tour shows the desktop: the search, the keys, the Store and Settings. It opens each of them for real and takes about a minute."
                    }
                    Row {
                        topPadding: Theme.space2
                        spacing: Theme.space2
                        Button { variant: "primary"; text: "Start the tour"; onClicked: root.start() }
                        Button { text: "Not now"; onClicked: root.stop("later") }
                        Button { variant: "quiet"; text: "Never"; onClicked: root.stop("never") }
                    }
                }

                // ------------------------------------------------ a step
                Column {
                    visible: root.running
                    width: parent.width
                    spacing: Theme.space2
                    Label {
                        textStyle: "micro"
                        color: Theme.textFaint
                        font.capitalization: Font.AllUppercase
                        text: "Tour, " + (root.step + 1) + " of " + root.steps.length
                    }
                    Label { textStyle: "subtitle"; color: Theme.text; text: root.current ? root.current.title : "" }
                    Label {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        textStyle: "body"
                        color: Theme.textMuted
                        text: root.current ? root.current.text : ""
                    }
                    KeyCaps { visible: keys !== ""; keys: root.current ? root.current.keys : "" }
                    Item {
                        width: parent.width
                        height: Theme.control + Theme.space2
                        Button {
                            anchors.bottom: parent.bottom
                            variant: "quiet"
                            text: "End the tour"
                            visible: root.step < root.steps.length - 1
                            onClicked: root.stop("done")
                        }
                        Row {
                            anchors { right: parent.right; bottom: parent.bottom }
                            spacing: Theme.space2
                            Button { visible: root.step > 0; text: "Back"; onClicked: root.go(root.step - 1) }
                            Button {
                                variant: "primary"
                                text: root.step < root.steps.length - 1 ? "Next" : "Done"
                                onClicked: root.step < root.steps.length - 1 ? root.go(root.step + 1) : root.stop("done")
                            }
                        }
                    }
                }
            }
        }
    }
}
