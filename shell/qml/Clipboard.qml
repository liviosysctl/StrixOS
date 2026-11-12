// The clipboard history (Super V): what was copied, newest first, from cliphist. Type to filter,
// Up and Down choose, Enter copies it again, Delete forgets it, Esc closes.
// The user service strix-clipboard keeps the history (wl-paste --watch cliphist store).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Strix

Scope {
    id: root

    property bool open: false
    /// Lines of `cliphist list`: id, a tab, a preview
    property var entries: []
    property int selected: 0
    property string filter: ""
    readonly property var shown: root.entries.filter(e => root.filter === ""
        || e.text.toLowerCase().indexOf(root.filter) >= 0)

    function show() {
        root.filter = ""
        root.selected = 0
        root.open = true
        list.running = true
    }

    function pick(entry) {
        if (!entry) return
        // cliphist decode wants the whole line, copy it back exactly as it was
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "sh", entry.line])
        root.open = false
    }

    function forget(entry) {
        if (!entry) return
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist delete", "sh", entry.line])
        root.entries = root.entries.filter(e => e.line !== entry.line)
    }

    Process {
        id: list
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l.indexOf("\t") > 0).map(l => ({
                    line: l,
                    text: l.slice(l.indexOf("\t") + 1)
                }))
            }
        }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { if (root.open) root.open = false; else root.show() }
        function clear(): void {
            Quickshell.execDetached(["cliphist", "wipe"])
            root.entries = []
        }
        function isOpen(): bool { return root.open }
        function count(): int { return root.entries.length }
    }

    HyprlandFocusGrab {
        windows: [overlay]
        active: root.open
        onCleared: root.open = false
    }

    PanelWindow {
        id: overlay
        visible: root.open
        WlrLayershell.namespace: "strix-clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.scrim

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Surface {
            elevation: "panel"
            width: 560
            height: column.implicitHeight + Theme.space4 * 2
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.14 }

            MouseArea { anchors.fill: parent }

            Column {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space4 }
                spacing: Theme.space3

                SearchField {
                    id: input
                    width: parent.width
                    placeholderText: "Clipboard"
                    KeyCaps { keys: "Esc" }
                    onTextChanged: { root.filter = text.toLowerCase(); root.selected = 0 }
                    onAccepted: root.pick(root.shown[root.selected])
                    Timer {
                        interval: 100
                        repeat: true
                        running: root.open && !input.field.activeFocus
                        onTriggered: input.field.forceActiveFocus()
                    }
                }

                Label {
                    visible: root.shown.length === 0
                    textStyle: "body"
                    color: Theme.textFaint
                    text: root.entries.length === 0 ? "Nothing copied yet" : "Nothing matches"
                }

                ListView {
                    id: rows
                    width: parent.width
                    height: Math.min(contentHeight, 36 * 10)
                    clip: true
                    model: root.shown
                    currentIndex: root.selected
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        width: rows.width
                        text: modelData.text.replace(/\s+/g, " ")
                        iconName: modelData.text.indexOf("[[ binary data") === 0 ? "image" : "copy"
                        selected: index === root.selected
                        onClicked: root.pick(modelData)
                    }
                }

                Row {
                    spacing: Theme.space4
                    Row { spacing: Theme.space1; KeyCaps { keys: "Enter" } Label { textStyle: "caption"; color: Theme.textFaint; text: "copy" } }
                    Row { spacing: Theme.space1; KeyCaps { keys: "Delete" } Label { textStyle: "caption"; color: Theme.textFaint; text: "forget" } }
                }
            }
        }

        Shortcut { sequence: "Down"; enabled: root.open; onActivated: root.selected = Math.min(root.selected + 1, root.shown.length - 1) }
        Shortcut { sequence: "Up"; enabled: root.open; onActivated: root.selected = Math.max(root.selected - 1, 0) }
        Shortcut { sequence: "Delete"; enabled: root.open; onActivated: root.forget(root.shown[root.selected]) }
        Shortcut {
            sequence: "Escape"
            enabled: root.open
            onActivated: {
                if (input.text !== "") input.text = ""
                else root.open = false
            }
        }
    }
}
