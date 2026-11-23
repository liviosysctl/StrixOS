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
    /// The panel with every message (Super N, the bell of the bar): one of Popups
    readonly property bool open: Popups.current === "notifications"
    /// The last forty messages that came, newest first, also the ones sent away since: the
    /// panel lists those under "Earlier". Kept until the session ends.
    property var history: []
    readonly property var earlier: history.filter(h => !list.some(n => n.id === h.id))

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: false
        imageSupported: false
        onNotification: n => {
            n.tracked = true
            root.history = [{ id: n.id, app: n.appName, summary: n.summary, body: n.body, at: Date.now() }]
                .concat(root.history).slice(0, 40)
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void { Popups.toggle("notifications", Popups.here()) }
        function quiet(): void { root.quiet = !root.quiet }
        function clear(): void {
            for (const n of root.list.slice()) n.dismiss()
            root.history = []
        }
    }
}
