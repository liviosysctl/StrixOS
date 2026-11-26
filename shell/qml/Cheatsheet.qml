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

    /// The groups in `count` columns, in their order: a column ends once it holds its share of what
    /// is left, a heading weighing about two rows
    function split(groups, count) {
        const weight = g => g.rows.length + 2
        let left = groups.reduce((sum, g) => sum + weight(g), 0)
        const out = []
        let column = []
        let held = 0
        for (const g of groups) {
            const share = left / (count - out.length)
            if (column.length > 0 && out.length < count - 1 && held + weight(g) / 2 > share) {
                out.push(column)
                left -= held
                column = []
                held = 0
            }
            column.push(g)
            held += weight(g)
        }
        if (column.length > 0) out.push(column)
        return out
    }

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

                    // Columns that fill from the top in the order of the sheet: a long group
                    // beside a short one leaves no hole under the short one
                    Row {
                        id: flow
                        width: scroll.width
                        spacing: Theme.space5
                        // Three columns, two where a row would get too narrow for its keys
                        readonly property int columns: width >= 960 ? 3 : 2
                        Repeater {
                            model: root.split(root.groups, flow.columns)
                            Column {
                                id: column
                                required property var modelData
                                width: (flow.width - Theme.space5 * (flow.columns - 1)) / flow.columns
                                spacing: Theme.space5
                                Repeater {
                                    model: column.modelData
                                    Column {
                                        id: group
                                        required property var modelData
                                        width: column.width
                                        spacing: Theme.space1
                                        Label { textStyle: "aside"; color: Theme.accentText; text: group.modelData.name }
                                        Repeater {
                                            model: group.modelData.rows
                                            HotkeyRow {
                                                required property var modelData
                                                width: group.width
                                                action: modelData.title
                                                // The heading says it already: "Window" under Windows
                                                target: modelData.scope === "picker" ? "In the theme picker"
                                                    : group.modelData.name.toLowerCase().startsWith(modelData.target.toLowerCase()) ? ""
                                                    : modelData.target
                                                keys: modelData.keys
                                            }
                                        }
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
