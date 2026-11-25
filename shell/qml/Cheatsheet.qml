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

    onOpenChanged: if (!open) { field.text = ""; scroll.contentY = 0 }

    Presence { id: presence; open: root.open }

    HyprlandFocusGrab {
        windows: [overlay]
        active: root.open
        onCleared: root.open = false
    }

    PanelWindow {
        id: overlay
        visible: presence.present
        WlrLayershell.namespace: "strix-cheatsheet"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.alpha(Theme.scrim, Theme.scrim.a * presence.shown)

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Surface {
            elevation: "panel"
            // Opening: drops 8px into place from 97% while the scrim fades (motion.md)
            opacity: presence.shown
            scale: 0.97 + 0.03 * presence.shown
            transformOrigin: Item.Top
            transform: Translate { y: -Theme.space2 * (1 - presence.shown) }
            width: Math.min(parent.width - Theme.space8 * 2, 1080)
            height: body.implicitHeight + 2 * Theme.space5
            anchors.centerIn: parent

            MouseArea { anchors.fill: parent }

            Column {
                id: body
                x: Theme.space5
                y: Theme.space5
                width: parent.width - 2 * Theme.space5
                spacing: Theme.space4

                Row {
                    id: head
                    width: parent.width
                    spacing: Theme.space3
                    Label { textStyle: "title"; color: Theme.accentText; text: "Keys"; anchors.verticalCenter: parent.verticalCenter }
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

                // The groups scroll when they are taller than the screen (a small or scaled one)
                Flickable {
                    id: scroll
                    width: parent.width
                    height: Math.min(flow.implicitHeight,
                        overlay.height - Theme.space8 * 2 - Theme.space5 * 2 - head.height - body.spacing)
                    contentHeight: flow.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Flow {
                        id: flow
                        width: scroll.width
                        spacing: Theme.space5
                        // Three columns, two where a row would get too narrow for its keys
                        readonly property int columns: width >= 960 ? 3 : 2
                        Repeater {
                            model: root.groups
                            Column {
                                required property var modelData
                                width: (flow.width - Theme.space5 * (flow.columns - 1)) / flow.columns
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
        }

        // Up, Down and the page keys scroll; typing still goes to the filter
        Shortcut { sequence: "Down"; enabled: root.open; onActivated: scroll.contentY = Math.min(scroll.contentY + 72, Math.max(0, scroll.contentHeight - scroll.height)) }
        Shortcut { sequence: "Up"; enabled: root.open; onActivated: scroll.contentY = Math.max(0, scroll.contentY - 72) }
        Shortcut { sequence: "PgDown"; enabled: root.open; onActivated: scroll.contentY = Math.min(scroll.contentY + scroll.height, Math.max(0, scroll.contentHeight - scroll.height)) }
        Shortcut { sequence: "PgUp"; enabled: root.open; onActivated: scroll.contentY = Math.max(0, scroll.contentY - scroll.height) }

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
