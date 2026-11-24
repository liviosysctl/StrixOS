// The Store (main, the school proof of concept): find an app in nixpkgs, install or remove it with
// one click. The service strix-store (Backend "store") searches the package index and runs
// strix-apps, which writes apps.json and rebuilds; its output streams into the window. Proprietary
// apps are shown and marked; installing one asks first (Q7), and the service refuses it otherwise.
// strix-shell next to Install opens the package in a shell in Ghostty, as nix-shell -p does: to try
// it, nothing is installed.
// Opened from Search (Apps › Store) or with `qs -c strix ipc call store open`.
import QtQuick
import Quickshell
import Quickshell.Io
import Strix
import Strix.Shell

Scope {
    id: root

    property bool open: false
    property var results: []
    property bool ready: true
    property int count: 0
    property int selected: 0
    /// The running or last job: action, attr, running, ok, lines
    property var job: null
    property var lines: []
    property string error: ""

    function show(text) {
        root.error = ""
        root.open = true
        input.text = text || ""
        root.refresh()
        store.call("job", {}, j => { if (j) { root.job = j; root.lines = j.lines || [] } })
    }

    function refresh() {
        store.call("search", { text: input.text, limit: 60 }, r => {
            root.results = (r && r.results) || []
            root.ready = !!(r && r.ready)
            root.count = (r && r.count) || 0
            root.selected = 0
        })
    }

    // The package waiting for an answer to the question about proprietary software, and whether
    // it is for a shell instead of an install
    property var asking: null
    property bool askingShell: false

    function act(pkg) {
        if (!pkg || (root.job && root.job.running)) return
        if (!pkg.installed && pkg.unfree) {
            root.asking = pkg
            root.askingShell = false
            proprietary.open()
            return
        }
        root.run(pkg, false)
    }

    /// The package in a shell in a new terminal, nothing installed
    function shell(pkg, agreed) {
        if (!pkg) return
        if (pkg.unfree && !agreed) {
            root.asking = pkg
            root.askingShell = true
            proprietary.open()
            return
        }
        const args = ["strix-shell"].concat(pkg.unfree ? ["--proprietary"] : []).concat([pkg.attr])
        Quickshell.execDetached(["uwsm", "app", "--", "ghostty", "-e"].concat(args))
    }

    function run(pkg, agreed) {
        root.error = ""
        root.lines = []
        const action = pkg.installed ? "remove" : "install"
        const params = { attr: pkg.attr }
        if (agreed) params.proprietary = true
        store.call(action, params, () => {
            root.job = { action: action, attr: pkg.attr, running: true, lines: [] }
        })
    }

    Backend {
        id: store
        service: "store"
        onEvent: (name, data) => {
            if (name === "progress") {
                root.lines = root.lines.concat([data.line]).slice(-200)
            } else if (name === "done") {
                root.job = Object.assign({}, data, { running: false })
                if (!data.ok) root.error = (data.action === "install" ? "Installing " : "Removing ") + data.attr + " failed"
                root.refresh()
            }
        }
        onFailed: (method, message) => root.error = message
    }

    IpcHandler {
        target: "store"
        function open(): void { root.show("") }
        function find(text: string): void { root.show(text) }
        function close(): void { root.open = false }
        function isOpen(): bool { return root.open }
        function busy(): bool { return !!(root.job && root.job.running) }
    }

    FloatingWindow {
        visible: root.open
        title: "Store"
        implicitWidth: 860
        implicitHeight: 640
        // Smoked glass: the compositor blurs what lies behind the window
        color: Theme.smoke(Theme.surface)
        onVisibleChanged: if (!visible) root.open = false

        Column {
            anchors { fill: parent; margins: Theme.space5 }
            spacing: Theme.space3

            Row {
                width: parent.width
                spacing: Theme.space3
                Label { textStyle: "title"; color: Theme.text; text: "Store"; anchors.verticalCenter: parent.verticalCenter }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    textStyle: "caption"
                    color: Theme.textFaint
                    text: root.ready ? root.count.toLocaleString(Qt.locale(), "f", 0) + " apps in nixpkgs" : ""
                }
            }

            SearchField {
                id: input
                width: parent.width
                placeholderText: "Find an app"
                onTextChanged: searchLater.restart()
                onAccepted: root.act(root.results[root.selected])
                Timer { id: searchLater; interval: 150; onTriggered: root.refresh() }
            }

            Label {
                visible: !root.ready
                width: parent.width
                wrapMode: Text.WordWrap
                textStyle: "body"
                color: Theme.textMuted
                text: "The list of apps is still being fetched. It comes once after the installation and after each update."
            }
            Label {
                visible: root.ready && input.text === "" && root.results.length === 0
                textStyle: "body"
                color: Theme.textFaint
                text: "Nothing installed from the Store yet. Type to find an app."
            }
            Label {
                visible: root.ready && input.text === "" && root.results.length > 0
                textStyle: "micro"
                color: Theme.textFaint
                font.capitalization: Font.AllUppercase
                text: "Installed from the Store"
            }

            ListView {
                id: list
                width: parent.width
                height: parent.height - y - (log.visible ? log.height + Theme.space3 : 0)
                clip: true
                spacing: Theme.space1
                model: root.results
                currentIndex: root.selected
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: list.width
                    // Two lines of text, and room for a control beside them
                    height: Theme.control + Theme.space5

                    // The chosen row: a lighter plate and the stroke of the accent, as in every list
                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusMd
                        color: index === root.selected ? Theme.surfaceRaised : "transparent"
                        Rectangle {
                            visible: index === root.selected
                            anchors.verticalCenter: parent.verticalCenter
                            width: Theme.lineBold
                            height: Theme.icon
                            radius: width / 2
                            color: Theme.accent
                        }
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.selected = index }

                    Column {
                        anchors { left: parent.left; leftMargin: Theme.space3; right: shellButton.left; rightMargin: Theme.space3; verticalCenter: parent.verticalCenter }
                        Row {
                            spacing: Theme.space2
                            Label { textStyle: "label"; color: Theme.text; text: modelData.pname }
                            Label { textStyle: "caption"; color: Theme.textFaint; text: modelData.version }
                            Badge { visible: modelData.installed; text: "Installed"; kind: "accent" }
                            Badge { visible: !!modelData.unfree; text: "Proprietary" }
                        }
                        Label {
                            width: parent.width
                            elide: Text.ElideRight
                            textStyle: "caption"
                            color: Theme.textMuted
                            text: modelData.description || modelData.attr
                        }
                    }

                    Button {
                        id: shellButton
                        anchors { right: button.left; rightMargin: Theme.space2; verticalCenter: parent.verticalCenter }
                        text: "strix-shell"
                        onClicked: root.shell(modelData, false)
                    }

                    Button {
                        id: button
                        anchors { right: parent.right; rightMargin: Theme.space2; verticalCenter: parent.verticalCenter }
                        variant: modelData.installed ? "danger" : "primary"
                        text: modelData.installed ? "Remove" : "Install"
                        loading: !!(root.job && root.job.running && root.job.attr === modelData.attr)
                        enabled: !(root.job && root.job.running)
                        onClicked: root.act(modelData)
                    }
                }
            }

            // What strix-apps says while it rebuilds, in a well in the glass of the window
            Rectangle {
                id: log
                visible: root.job !== null
                width: parent.width
                height: 150
                radius: Theme.radiusMd
                color: Theme.alpha(Theme.text, 0.04)
                border.color: Theme.glassEdge

                Column {
                    anchors { fill: parent; margins: Theme.space3 }
                    spacing: Theme.space1
                    Row {
                        spacing: Theme.space2
                        Label {
                            textStyle: "label"
                            color: root.error !== "" ? Theme.error : Theme.text
                            text: root.error !== "" ? root.error
                                : !root.job ? ""
                                : root.job.running ? (root.job.action === "install" ? "Installing " : "Removing ") + root.job.attr + "..."
                                : (root.job.action === "install" ? "Installed " : "Removed ") + root.job.attr
                        }
                    }
                    ProgressBar {
                        visible: !!(root.job && root.job.running)
                        width: parent.width
                        indeterminate: true
                    }
                    ListView {
                        id: output
                        width: parent.width
                        height: parent.height - y
                        clip: true
                        model: root.lines
                        onCountChanged: positionViewAtEnd()
                        delegate: Label {
                            required property string modelData
                            width: output.width
                            elide: Text.ElideRight
                            textStyle: "code"
                            color: Theme.textMuted
                            text: modelData
                        }
                    }
                }
            }
        }

        Dialog {
            id: proprietary
            title: root.asking ? (root.askingShell ? "Open " : "Install ") + root.asking.pname + "?" : ""
            text: root.askingShell
                ? "This app is not open source: its code is not public, and its licence may limit what you can do with it. The shell only fetches it, nothing is installed."
                : "This app is not open source: its code is not public, and its licence may limit what you can do with it. It installs like any other app and can be removed again."
            acceptText: root.askingShell ? "Open anyway" : "Install anyway"
            onAccepted: {
                if (root.asking) {
                    if (root.askingShell) root.shell(root.asking, true)
                    else root.run(root.asking, true)
                }
                root.asking = null
            }
            onRejected: root.asking = null
        }

        Shortcut { sequence: "Down"; enabled: root.open && !proprietary.visible; onActivated: root.selected = Math.min(root.selected + 1, root.results.length - 1) }
        Shortcut { sequence: "Up"; enabled: root.open && !proprietary.visible; onActivated: root.selected = Math.max(root.selected - 1, 0) }
        Shortcut { sequence: "Escape"; enabled: root.open && !proprietary.visible; onActivated: { if (input.text !== "") input.text = ""; else root.open = false } }
    }
}
