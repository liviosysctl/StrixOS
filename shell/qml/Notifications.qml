// Messages top right under the bar (Notification in StrixUI). A popup shows each new message for
// its time; Super N opens all of them. Critical ones stay until dismissed, also when quiet.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Strix

PanelWindow {
    id: win

    // what is shown: everything when the panel is open, else the fresh ones
    property var fresh: []
    readonly property var shown: Notifs.open ? Notifs.list : fresh

    WlrLayershell.namespace: "strix-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; right: true }
    margins { top: Theme.barHeight + Theme.space2; right: Theme.space3 }
    implicitWidth: 360
    implicitHeight: Math.max(1, column.implicitHeight)
    color: "transparent"
    visible: shown.length > 0
    mask: Region { item: column }

    Connections {
        target: Notifs
        function onListChanged() {
            const known = new Set(win.fresh)
            const last = Notifs.list[Notifs.list.length - 1]
            win.fresh = win.fresh.filter(n => Notifs.list.indexOf(n) >= 0)
            if (last && !known.has(last) && (!Notifs.quiet || last.urgency === NotificationUrgency.Critical))
                win.fresh = win.fresh.concat([last])
        }
    }

    Column {
        id: column
        width: parent.width
        spacing: Theme.space2

        // A new message slides in from the right edge; the others make room smoothly
        add: Transition {
            ParallelAnimation {
                NumberAnimation { property: "x"; from: 32; to: 0; duration: Theme.durSlow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
            }
        }
        move: Transition {
            NumberAnimation { property: "y"; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }

        Repeater {
            model: win.shown
            Notification {
                id: note
                required property var modelData
                width: column.width

                /// Slide out to the right, then let `done` remove the message
                function leave(done) {
                    if (out.running) return
                    out.done = done
                    out.restart()
                }
                SequentialAnimation {
                    id: out
                    property var done
                    ParallelAnimation {
                        NumberAnimation { target: note; property: "x"; to: 32; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeIn }
                        NumberAnimation { target: note; property: "opacity"; to: 0; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeIn }
                    }
                    ScriptAction { script: out.done() }
                }
                iconName: modelData.urgency === NotificationUrgency.Critical ? "triangle-alert" : "bell"
                title: modelData.summary
                body: modelData.body
                time: modelData.appName
                urgency: modelData.urgency === NotificationUrgency.Critical ? "critical" : "normal"
                actions: modelData.actions.map(a => a.text)
                onAction: index => modelData.actions[index].invoke()
                // the panel keeps them; a popup leaves after its time, a critical one never
                Timer {
                    running: !Notifs.open && modelData.urgency !== NotificationUrgency.Critical
                    interval: modelData.expireTimeout > 0 ? modelData.expireTimeout * 1000 : 6000
                    onTriggered: note.leave(() => win.fresh = win.fresh.filter(n => n !== modelData))
                }
                onDismissed: {
                    if (Notifs.open || modelData.urgency === NotificationUrgency.Critical) note.leave(() => modelData.dismiss())
                    else note.leave(() => win.fresh = win.fresh.filter(n => n !== modelData))
                }
            }
        }
    }
}
