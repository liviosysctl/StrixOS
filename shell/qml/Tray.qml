// The tray of the bar: the symbols of apps that keep running without a window (a chat, a sync, a
// password manager). A click does what the app means by it, the middle button its second action,
// the right button (or a click, where the app only has a menu) opens its menu under the symbol,
// in the look of the shell. A click elsewhere or Escape folds the menu back.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Strix

Row {
    id: root

    /// The window of the bar, which the menu hangs from
    required property var window

    /// The item whose menu is open, and the way into its submenus (the last one is shown)
    property var item: null
    property var path: []
    readonly property var shownMenu: path.length > 0 ? path[path.length - 1] : (item ? item.menu : null)
    /// Where the menu hangs: its right edge at the right edge of the symbol, inside the screen
    property real menuX: 0
    /// Another panel of the bar opened: the menu gives way
    property bool giveWay: false
    onGiveWayChanged: if (giveWay) root.close()

    function open(trayItem, symbol) {
        if (root.item === trayItem) { root.close(); return }
        root.path = []
        root.item = trayItem
        root.menuX = Math.max(Theme.space2, Math.min(root.window.width - menu.implicitWidth - Theme.space2,
            symbol.mapToItem(null, symbol.width, 0).x - menu.implicitWidth + Theme.space2))
    }
    function close() {
        root.item = null
        root.path = []
    }

    spacing: Theme.space1
    visible: SystemTray.items.values.length > 0

    Repeater {
        model: SystemTray.items

        Item {
            id: symbol
            required property var modelData

            width: Theme.controlSm
            height: Theme.controlSm

            Rectangle {
                anchors.fill: parent
                radius: Theme.radiusSm
                color: here.hovered || root.item === symbol.modelData ? Theme.surfaceRaised : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
            }
            IconImage {
                anchors.centerIn: parent
                implicitSize: 14
                source: symbol.modelData.icon
            }

            HoverHandler { id: here; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onTapped: (point, button) => {
                    const item = symbol.modelData
                    if (button === Qt.MiddleButton) item.secondaryActivate()
                    else if (button === Qt.RightButton || item.onlyMenu) { if (item.hasMenu) root.open(item, symbol) }
                    else { root.close(); item.activate() }
                }
            }
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => symbol.modelData.scroll(event.angleDelta.y, false)
            }
        }
    }

    HyprlandFocusGrab {
        windows: [root.window, menu]
        active: root.item !== null
        onCleared: root.close()
    }

    PopupWindow {
        id: menu

        visible: presence.present
        anchor.window: root.window
        anchor.rect.x: root.menuX
        anchor.rect.y: root.window.height
        implicitWidth: 260
        implicitHeight: rows.implicitHeight + 3 * Theme.space2
        color: "transparent"

        // The app sends its menu a moment after it is asked: the window opens once it knows its size
        Presence { id: presence; open: root.item !== null && opener.children.values.length > 0 }
        QsMenuOpener { id: opener; menu: root.shownMenu }

        Surface {
            y: Theme.space2
            width: parent.width
            height: parent.height - Theme.space2
            elevation: "panel"
            opacity: presence.shown
            transform: Translate { y: -6 * (1 - presence.shown) }
            focus: true
            Keys.onEscapePressed: root.close()

            Column {
                id: rows
                y: Theme.space2
                width: parent.width

                // Inside a submenu: the way back
                ListRow {
                    visible: root.path.length > 0
                    width: parent.width
                    iconName: "chevron-left"
                    text: "Back"
                    onClicked: root.path = root.path.slice(0, -1)
                }

                Repeater {
                    model: opener.children

                    Item {
                        id: entry
                        required property var modelData

                        width: rows.width
                        height: modelData.isSeparator ? Theme.space2 + Theme.lineHair : row.implicitHeight

                        Rectangle {
                            visible: entry.modelData.isSeparator
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.space3
                            width: parent.width - 2 * Theme.space3
                            height: Theme.lineHair
                            color: Theme.border
                        }
                        ListRow {
                            id: row
                            visible: !entry.modelData.isSeparator
                            width: parent.width
                            enabled: entry.modelData.enabled
                            text: entry.modelData.text
                            // A box or a dot that is set shows a check; a submenu the way in
                            iconName: entry.modelData.checkState === Qt.Checked ? "check" : ""
                            detail: entry.modelData.hasChildren ? "›" : ""
                            onClicked: {
                                if (entry.modelData.hasChildren) {
                                    root.path = root.path.concat([entry.modelData])
                                } else {
                                    entry.modelData.triggered()
                                    root.close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
