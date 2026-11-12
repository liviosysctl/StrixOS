// The Store (main, the school proof of concept): find an app in nixpkgs, install or remove it with
// one click. The service strix-store (Backend "store") searches the package index and runs
// strix-apps, which writes apps.json and rebuilds; its output streams into the window.
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

    function act(pkg) {
        if (!pkg || (root.job && root.job.running)) return
        root.error = ""
        root.lines = []
        const action = pkg.installed ? "remove" : "install"
        store.call(action, { attr: pkg.attr }, () => {
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
        color: Theme.background
        onVisibleChanged: if (!visible) root.open = false

        Column {
            anchors { fill: parent; margins: Theme.space6 }
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
                    height: 56

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusSm
                        color: index === root.selected ? Theme.surfaceRaised : "transparent"
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.selected = index }

                    Column {
                        anchors { left: parent.left; leftMargin: Theme.space3; right: button.left; rightMargin: Theme.space3; verticalCenter: parent.verticalCenter }
                        Row {
                            spacing: Theme.space2
                            Label { textStyle: "label"; color: Theme.text; text: modelData.pname }
                            Label { textStyle: "caption"; color: Theme.textFaint; text: modelData.version }
                            Badge { visible: modelData.installed; text: "Installed"; kind: "accent" }
                            Badge { visible: !!modelData.unfree; text: "Unfree" }
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
                        id: button
                        anchors { right: parent.right; rightMargin: Theme.space3; verticalCenter: parent.verticalCenter }
                        small: true
                        variant: modelData.installed ? "danger" : "primary"
                        text: modelData.installed ? "Remove" : "Install"
                        loading: !!(root.job && root.job.running && root.job.attr === modelData.attr)
                        enabled: !(root.job && root.job.running)
                        onClicked: root.act(modelData)
                    }
                }
            }

            // What strix-apps says while it rebuilds
            Surface {
                id: log
                visible: root.job !== null
                width: parent.width
                height: 150

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
                        delegate: Text {
                            required property string modelData
                            width: output.width
                            elide: Text.ElideRight
                            font.family: "JetBrains Mono"
                            font.pixelSize: 11
                            color: Theme.textMuted
                            text: modelData
                        }
                    }
                }
            }
        }

        Shortcut { sequence: "Down"; enabled: root.open; onActivated: root.selected = Math.min(root.selected + 1, root.results.length - 1) }
        Shortcut { sequence: "Up"; enabled: root.open; onActivated: root.selected = Math.max(root.selected - 1, 0) }
        Shortcut { sequence: "Escape"; enabled: root.open; onActivated: { if (input.text !== "") input.text = ""; else root.open = false } }
    }
}
