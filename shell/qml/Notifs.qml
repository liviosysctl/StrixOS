// The notification server and its state, shared by the bar (the count) and the popups.
// Do not disturb keeps messages in the list but shows no popup, except critical ones.
pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    /// Every message not dismissed yet, newest last
    readonly property var list: server.trackedNotifications.values
    readonly property int count: list.length
    property bool quiet: false
    /// The panel with every message (Super N)
    property bool open: false

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: false
        imageSupported: false
        onNotification: n => n.tracked = true
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { root.open = !root.open }
        function quiet(): void { root.quiet = !root.quiet }
        function clear(): void { for (const n of root.list.slice()) n.dismiss() }
    }
}
