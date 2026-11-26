// The window switcher (Alt Tab): the open windows, the one used last first. Alt Tab goes on to
// the next one, Alt Shift Tab back, and letting go of Alt goes to the window that is marked.
// The arrows move too, Enter goes there, Escape leaves everything as it was.
// ipc: switcher next, switcher previous.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Strix

Scope {
    id: root

    property bool open: false
    property int selected: 0
    /// The windows in the order they were last used, the one with the focus first
    property var order: []
    /// What is listed while the switcher is open: it must not reorder under the hand
    property var shown: []

    // Every window that gets the focus moves to the front of the order
    Connections {
        target: ToplevelManager
        function onActiveToplevelChanged() {
            const active = ToplevelManager.activeToplevel
            if (active) root.order = [active].concat(root.order.filter(w => w !== active))
        }
    }

    function windows() {
        const all = ToplevelManager.toplevels.values
        const known = root.order.filter(w => all.indexOf(w) >= 0)
        return known.concat(all.filter(w => known.indexOf(w) < 0))
    }

    function step(by) {
        if (!root.open) {
            root.shown = root.windows()
            if (root.shown.length === 0) return
            // The first step goes to the window used before this one
            root.selected = root.shown.length > 1 ? (by > 0 ? 1 : root.shown.length - 1) : 0
            root.open = true
            return
        }
        root.selected = (root.selected + by + root.shown.length) % root.shown.length
    }

    function go() {
        const window = root.shown[root.selected]
        root.open = false
        if (window) window.activate()
    }

    IpcHandler {
        target: "switcher"
        function next(): void { root.step(1) }
        function previous(): void { root.step(-1) }
    }

    Presence { id: presence; open: root.open; duration: Theme.durFast }

    HyprlandFocusGrab {
        windows: [win]
        active: root.open
        onCleared: root.open = false
    }

    PanelWindow {
        id: win

        visible: presence.present
        WlrLayershell.namespace: "strix-switcher"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab. The keys must arrive here while
        // Alt is held: that is how letting go of it is noticed
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Surface {
            anchors.centerIn: parent
            width: Math.min(parent.width - 2 * Theme.space6, 520)
            height: rows.implicitHeight + 2 * Theme.space2
            elevation: "panel"
            inset: Theme.space2
            opacity: presence.shown
            scale: 0.98 + 0.02 * presence.shown

            focus: true
            Keys.onReleased: event => {
                if (event.key === Qt.Key_Alt || event.key === Qt.Key_Meta) root.go()
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.key === Qt.Key_Right) root.step(1)
                else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up || event.key === Qt.Key_Left) root.step(-1)
                else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.go()
                else if (event.key === Qt.Key_Escape) root.open = false
                else return
                event.accepted = true
            }

            Column {
                id: rows
                x: Theme.space2
                y: Theme.space2
                width: parent.width - 2 * Theme.space2

                Repeater {
                    model: root.shown

                    ListRow {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property var entry: DesktopEntries.heuristicLookup(modelData.appId)

                        width: rows.width
                        selected: index === root.selected
                        leftPadding: Theme.space2 + Theme.icon + Theme.space2
                        text: modelData.title || (entry ? entry.name : modelData.appId)
                        detail: entry ? entry.name : modelData.appId
                        onClicked: { root.selected = index; root.go() }

                        // The symbol of the app, or a window where the app has none
                        readonly property string symbol: Quickshell.iconPath(entry && entry.icon ? entry.icon : modelData.appId, true)
                        IconImage {
                            visible: row.symbol !== ""
                            x: Theme.space2
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: Theme.icon
                            source: row.symbol
                        }
                        Icon {
                            visible: row.symbol === ""
                            x: Theme.space2
                            anchors.verticalCenter: parent.verticalCenter
                            name: "app-window"
                            color: row.selected ? Theme.text : Theme.textMuted
                        }
                    }
                }
            }
        }
    }
}
