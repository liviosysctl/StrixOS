// The overview (Super O): every workspace of the screen with the focus as a small plate of the
// god, the windows on it where they stand, each with a picture of what it shows. A click on a
// workspace goes there, a click on a window goes to it, a window dragged onto another workspace
// moves there. The arrows choose a workspace, Enter goes, 1 to 0 go at once, Esc closes.
// There is always one empty workspace more to drag a window onto.
// Built only while open: the pictures of the windows are taken once when it opens.
// ipc: overview toggle.
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
    /// The workspace marked with the arrows
    property int selected: 1
    /// The workspace a dragged window is over, 0 when none
    property int dragOver: 0

    readonly property var monitor: Hyprland.focusedMonitor
    /// The workspaces on that screen, 1 to the last used one and one more, at most 10
    readonly property int count: {
        const used = Hyprland.workspaces.values
            .filter(w => w.id > 0 && w.monitor === root.monitor && w.toplevels.values.length > 0)
            .map(w => w.id)
        const active = root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : 1
        return Math.min(10, Math.max(active, ...used, 0) + 1)
    }

    function show() {
        Hyprland.refreshToplevels()
        Hyprland.refreshWorkspaces()
        root.selected = root.monitor && root.monitor.activeWorkspace ? Math.max(1, root.monitor.activeWorkspace.id) : 1
        root.open = true
    }

    function go(id) {
        root.open = false
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
    }

    function moveWindow(window, id) {
        if (!window || !window.workspace || window.workspace.id === id) return
        Hyprland.dispatch("hl.dsp.window.move({ workspace = " + id + ", window = \"address:0x" + window.address + "\", follow = false })")
        Hyprland.refreshToplevels()
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { if (root.open) root.open = false; else root.show() }
        function isOpen(): bool { return root.open }
    }

    Presence { id: presence; open: root.open; duration: Theme.durBase }

    HyprlandFocusGrab {
        windows: loader.item ? [loader.item] : []
        active: root.open && !!loader.item
        onCleared: root.open = false
    }

    LazyLoader {
        id: loader
        active: presence.present

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => root.monitor && s.name === root.monitor.name) || Quickshell.screens[0]
            WlrLayershell.namespace: "strix-overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: Theme.alpha(Theme.scrim, Theme.scrim.a * presence.shown)

            /// The screen in the coordinates Hyprland gives the windows
            readonly property real screenX: root.monitor ? root.monitor.x : 0
            readonly property real screenY: root.monitor ? root.monitor.y : 0
            readonly property real screenW: root.monitor ? root.monitor.width / root.monitor.scale : width
            readonly property real screenH: root.monitor ? root.monitor.height / root.monitor.scale : height
            readonly property int columns: Math.min(root.count, 5)
            readonly property real cardW: Math.min(width * 0.2, (width - 2 * Theme.space7 - (columns - 1) * Theme.space4) / columns)
            readonly property real cardH: cardW * screenH / screenW

            MouseArea { anchors.fill: parent; onClicked: root.open = false }

            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) root.open = false
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_Tab) root.selected = root.selected % root.count + 1
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_Backtab) root.selected = (root.selected + root.count - 2) % root.count + 1
                    else if (event.key === Qt.Key_Down) root.selected = Math.min(root.count, root.selected + win.columns)
                    else if (event.key === Qt.Key_Up) root.selected = Math.max(1, root.selected - win.columns)
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.go(root.selected)
                    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) root.go(event.key - Qt.Key_0)
                    else if (event.key === Qt.Key_0) root.go(10)
                    else return
                    event.accepted = true
                }
            }

            Grid {
                id: grid
                anchors.centerIn: parent
                columns: win.columns
                spacing: Theme.space4
                opacity: presence.shown
                scale: 0.96 + 0.04 * presence.shown

                Repeater {
                    model: root.count

                    Item {
                        id: card
                        required property int index
                        readonly property int number: index + 1
                        readonly property var workspace: Hyprland.workspaces.values.find(w => w.id === card.number) || null
                        readonly property bool current: !!root.monitor && !!root.monitor.activeWorkspace && root.monitor.activeWorkspace.id === card.number
                        readonly property bool marked: root.selected === card.number

                        width: win.cardW
                        height: win.cardH + Theme.space5

                        // The plate: the god's picture, dim, as the desktop of this workspace
                        Rectangle {
                            id: plate
                            width: parent.width
                            height: win.cardH
                            radius: Theme.radiusMd
                            color: Theme.background
                            border.width: Theme.lineHair
                            border.color: root.dragOver === card.number ? Theme.accent : hover.hovered || card.marked ? Theme.borderStrong : Theme.border
                            clip: true
                            Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

                            Image {
                                anchors.fill: parent
                                anchors.margins: Theme.lineHair
                                source: Theme.wallpaper()
                                sourceSize.width: win.cardW * 2
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: 0.45
                            }

                            Repeater {
                                model: card.workspace ? card.workspace.toplevels.values : []

                                Rectangle {
                                    id: tile
                                    required property var modelData
                                    readonly property var at: modelData.lastIpcObject && modelData.lastIpcObject.at ? modelData.lastIpcObject.at : [win.screenX, win.screenY]
                                    readonly property var size: modelData.lastIpcObject && modelData.lastIpcObject.size ? modelData.lastIpcObject.size : [win.screenW / 2, win.screenH / 2]
                                    readonly property real ratio: win.cardW / win.screenW
                                    readonly property var entry: DesktopEntries.heuristicLookup(modelData.lastIpcObject ? modelData.lastIpcObject.class || "" : "")
                                    readonly property string symbol: Quickshell.iconPath(entry && entry.icon ? entry.icon : "", true)

                                    x: (at[0] - win.screenX) * ratio
                                    y: (at[1] - win.screenY) * ratio
                                    width: Math.max(Theme.space4, size[0] * ratio)
                                    height: Math.max(Theme.space4, size[1] * ratio)
                                    z: dragger.active ? 10 : 1
                                    radius: Theme.radiusSm
                                    color: Theme.surfaceRaised
                                    border.width: Theme.lineHair
                                    border.color: tileHover.hovered ? Theme.accent : Theme.border
                                    clip: true
                                    Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

                                    // What the window shows, taken once
                                    ScreencopyView {
                                        anchors.fill: parent
                                        anchors.margins: Theme.lineHair
                                        captureSource: tile.modelData.wayland
                                        live: false
                                    }
                                    IconImage {
                                        anchors.centerIn: parent
                                        visible: tile.symbol !== ""
                                        implicitSize: Math.min(Theme.space6, tile.height * 0.5)
                                        source: tile.symbol
                                    }

                                    HoverHandler { id: tileHover; cursorShape: dragger.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            root.open = false
                                            if (tile.modelData.wayland) tile.modelData.wayland.activate()
                                        }
                                    }
                                    // Dragged onto another workspace it moves there; let go elsewhere, it goes back
                                    DragHandler {
                                        id: dragger
                                        target: null
                                        /// The workspace under the pointer, 0 when none
                                        function over() {
                                            const p = tile.mapToItem(grid, centroid.position.x, centroid.position.y)
                                            const target = grid.childAt(p.x, p.y)
                                            return target && target.number ? target.number : 0
                                        }
                                        onActiveChanged: {
                                            if (active) return
                                            if (root.dragOver > 0) root.moveWindow(tile.modelData, root.dragOver)
                                            root.dragOver = 0
                                            ghost.visible = false
                                        }
                                        onCentroidChanged: if (active) {
                                            const p = tile.mapToItem(win.contentItem, centroid.position.x, centroid.position.y)
                                            ghost.x = p.x - ghost.width / 2
                                            ghost.y = p.y - ghost.height / 2
                                            ghost.source = tile.symbol
                                            ghost.visible = true
                                            root.dragOver = over()
                                        }
                                    }
                                }
                            }

                            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.go(card.number) }
                        }

                        // The number, and the accent stroke under the workspace that is shown
                        Label {
                            anchors { left: parent.left; top: plate.bottom; topMargin: Theme.space1 }
                            textStyle: "caption"
                            color: card.current || card.marked ? Theme.text : Theme.textMuted
                            text: card.number
                        }
                        Rectangle {
                            anchors { right: parent.right; top: plate.bottom; topMargin: Theme.space2 }
                            width: card.current ? Theme.space5 : 0
                            height: Theme.lineBold
                            radius: height / 2
                            color: Theme.accent
                            Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                        }
                    }
                }
            }

            // The symbol of a window that is being dragged, under the pointer
            IconImage {
                id: ghost
                visible: false
                implicitSize: Theme.space6
                opacity: 0.9
                z: 100
            }
        }
    }
}
