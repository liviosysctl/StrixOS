// The tray of the bar: one button for every app that keeps running without a window (a chat, a
// sync, a password manager), there only while there is one. A click drops a small panel with the
// apps; a click on an app shows what it offers: opening it, and its own menu, drawn in the look
// of the shell. The middle button on an app is its second action. The panel is one of Popups,
// which folds it back.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Strix

Chip {
    id: root

    /// The window of the bar, which the panel hangs from, and the name of its screen
    required property var window
    required property string screenName

    /// The app whose menu is shown, and the way into its submenus (the last one is shown)
    property var item: null
    property var path: []
    readonly property var shownMenu: path.length > 0 ? path[path.length - 1] : (item && item.hasMenu ? item.menu : null)

    open: Popups.shows("tray", root.screenName)
    // Opened again, it starts with the apps
    onOpenChanged: if (!open) {
        root.item = null
        root.path = []
    }
    function close() { if (root.open) Popups.close() }
    function name(trayItem) {
        return trayItem.tooltipTitle || trayItem.title || trayItem.id
    }

    iconName: "inbox"
    visible: SystemTray.items.values.length > 0
    onVisibleChanged: if (!visible) root.close()
    onClicked: Popups.toggle("tray", root.screenName)

    HyprlandFocusGrab {
        windows: [root.window, panel]
        active: root.open
        onCleared: root.close()
    }

    PopupWindow {
        id: panel

        visible: presence.present
        anchor.window: root.window
        // Its right edge at the right edge of the button, inside the screen
        anchor.rect.x: Math.max(Theme.space2, Math.min(root.window.width - width - Theme.space2,
            root.mapToItem(null, root.width, 0).x - width))
        anchor.rect.y: root.window.height
        implicitWidth: 280
        implicitHeight: rows.implicitHeight + 3 * Theme.space2
        color: "transparent"

        Presence { id: presence; open: root.open }
        QsMenuOpener { id: opener; menu: root.shownMenu }

        Surface {
            y: Theme.space2
            width: parent.width
            height: parent.height - Theme.space2
            elevation: "panel"
            inset: Theme.space2
            opacity: presence.shown
            transform: Translate { y: -Theme.space2 * (1 - presence.shown) }
            focus: true
            Keys.onPressed: event => Popups.key(event)

            Column {
                id: rows
                x: Theme.space2
                y: Theme.space2
                width: parent.width - 2 * Theme.space2

                // ------------------------------------------------ the apps
                Repeater {
                    model: root.item ? [] : SystemTray.items.values

                    ListRow {
                        id: app
                        required property var modelData

                        width: rows.width
                        leftPadding: Theme.space2 + Theme.icon + Theme.space2
                        text: root.name(modelData)
                        detail: "›"
                        onClicked: root.item = modelData

                        IconImage {
                            x: Theme.space2
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: Theme.icon
                            source: app.modelData.icon
                        }
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: app.modelData.secondaryActivate()
                        }
                    }
                }

                // ------------------------------------------------ one app: opening it, and its menu
                ListRow {
                    visible: root.item !== null
                    width: parent.width
                    iconName: "chevron-left"
                    text: root.path.length > 0 ? "Back" : (root.item ? root.name(root.item) : "")
                    onClicked: {
                        if (root.path.length > 0) root.path = root.path.slice(0, -1)
                        else root.item = null
                    }
                }
                ListRow {
                    visible: root.item !== null && root.path.length === 0 && !root.item.onlyMenu
                    width: parent.width
                    iconName: "app-window"
                    text: "Open"
                    onClicked: {
                        root.item.activate()
                        root.close()
                    }
                }

                Repeater {
                    model: root.item ? opener.children : []

                    Item {
                        id: entry
                        required property var modelData

                        width: rows.width
                        height: modelData.isSeparator ? Theme.space2 + Theme.lineHair : row.implicitHeight

                        Rectangle {
                            visible: entry.modelData.isSeparator
                            anchors.verticalCenter: parent.verticalCenter
                            x: Theme.space2
                            width: parent.width - 2 * Theme.space2
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
