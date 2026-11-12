// The cheat sheet (Super K, Cheatsheet in StrixUI): every key of the system in groups, read from
// the search service, which reads the same menu.toml the Hyprland bindings are made from.
// Typing filters by action or by keys; Esc clears and a second Esc closes.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Strix
import Strix.Shell

Scope {
    id: root

    property bool open: false
    property var rows: []
    property string filter: ""

    readonly property var groups: {
        const words = root.filter.toLowerCase().split(/\s+/).filter(w => w)
        const out = []
        for (const r of root.rows) {
            const hay = (r.title + " " + r.keys + " " + r.group + " " + r.target).toLowerCase()
            if (!words.every(w => hay.indexOf(w) >= 0)) continue
            let g = out.find(x => x.name === r.group)
            if (!g) { g = { name: r.group, rows: [] }; out.push(g) }
            g.rows.push(r)
        }
        return out
    }

    Backend { id: search; service: "search" }

    IpcHandler {
        target: "cheatsheet"
        function toggle(): void {
            root.open = !root.open
            if (root.open) search.call("hotkeys", {}, r => root.rows = r || [])
        }
        function isOpen(): bool { return root.open }
        function count(): int { return root.rows.length }
    }

    onOpenChanged: if (!open) field.text = ""

    HyprlandFocusGrab {
        windows: [overlay]
        active: root.open
        onCleared: root.open = false
    }

    PanelWindow {
        id: overlay
        visible: root.open
        WlrLayershell.namespace: "strix-cheatsheet"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.scrim

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Surface {
            elevation: "panel"
            width: Math.min(parent.width - Theme.space8 * 2, 1080)
            height: Math.min(parent.height - Theme.space8 * 2, body.implicitHeight + Theme.space5 * 2)
            anchors.centerIn: parent

            MouseArea { anchors.fill: parent }

            Column {
                id: body
                anchors { fill: parent; margins: Theme.space5 }
                spacing: Theme.space4

                Row {
                    width: parent.width
                    spacing: Theme.space3
                    Label { textStyle: "title"; text: "Keys"; anchors.verticalCenter: parent.verticalCenter }
                    SearchField {
                        id: field
                        width: 280
                        placeholderText: "Filter"
                        onTextChanged: root.filter = text
                        Timer {
                            interval: 100
                            repeat: true
                            running: root.open && !field.field.activeFocus
                            onTriggered: field.field.forceActiveFocus()
                        }
                    }
                }

                Flow {
                    width: parent.width
                    spacing: Theme.space5
                    Repeater {
                        model: root.groups
                        Column {
                            required property var modelData
                            width: (body.width - Theme.space5 * 2) / 3
                            spacing: Theme.space1
                            Label { textStyle: "aside"; color: Theme.accentText; text: modelData.name }
                            Repeater {
                                model: modelData.rows
                                HotkeyRow {
                                    required property var modelData
                                    width: parent.width
                                    action: modelData.title
                                    target: modelData.scope === "picker" ? "In the theme picker" : modelData.target
                                    keys: modelData.keys
                                }
                            }
                        }
                    }
                }
            }
        }

        Shortcut {
            sequence: "Escape"
            enabled: root.open
            onActivated: {
                if (field.text !== "") field.text = ""
                else root.open = false
            }
        }
    }
}
