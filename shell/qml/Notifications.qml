// Messages top right under the bar (Notification in StrixUI). A popup shows each new message for
// its time; Super N opens all of them, with the ones sent away earlier in this session under
// them. Critical ones stay until dismissed, also when quiet.
// A click on a message sends it away. A new one slides in from the edge of the screen and the
// others make room; the ones already there stay where they are.
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
    // Up to the edge of the screen, so a message that slides in or out is not cut off before it
    margins.top: Theme.barHeight + Theme.space2
    implicitWidth: 360 + Theme.space3
    implicitHeight: Math.max(1, column.implicitHeight)
    color: "transparent"
    visible: shown.length > 0 || Notifs.open
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
        width: 360
        spacing: Theme.space2

        move: Transition {
            NumberAnimation { property: "y"; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
        }

        Repeater {
            // Only what is new is made: a message that is already shown keeps its place
            model: ScriptModel { values: win.shown }
            Notification {
                id: note
                required property var modelData
                width: column.width

                // It arrives from the edge of the screen and leaves the same way
                property real away: 1
                opacity: 1 - away
                transform: Translate { x: note.away * (Theme.space3 + 24) }
                NumberAnimation on away {
                    to: 0
                    duration: Theme.durSlow
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.easeOut
                }

                /// Slide out to the right, then let `done` remove the message
                function leave(done) {
                    if (out.running) return
                    out.done = done
                    out.restart()
                }
                SequentialAnimation {
                    id: out
                    property var done
                    NumberAnimation { target: note; property: "away"; to: 1; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeIn }
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

        // The panel also lists what came earlier and is gone from the screen since
        Surface {
            visible: Notifs.open
            width: column.width
            height: earlier.implicitHeight + 2 * Theme.space2
            elevation: "panel"

            Column {
                id: earlier
                y: Theme.space2
                width: parent.width

                Item {
                    width: parent.width
                    height: Theme.controlMd
                    Label {
                        x: 20
                        anchors.verticalCenter: parent.verticalCenter
                        textStyle: "label"
                        color: Theme.text
                        text: Notifs.earlier.length > 0 ? "Earlier" : Notifs.count > 0 ? "Nothing earlier" : "No messages"
                    }
                    Button {
                        visible: Notifs.earlier.length > 0 || Notifs.count > 0
                        anchors { right: parent.right; rightMargin: Theme.space2; verticalCenter: parent.verticalCenter }
                        small: true
                        variant: "quiet"
                        text: "Clear all"
                        onClicked: {
                            for (const n of Notifs.list.slice()) n.dismiss()
                            Notifs.history = []
                        }
                    }
                }
                Repeater {
                    model: Notifs.earlier.slice(0, 8)
                    ListRow {
                        required property var modelData
                        width: earlier.width
                        text: modelData.summary
                        detail: modelData.app + " · " + Qt.formatTime(new Date(modelData.at), "HH:mm")
                    }
                }
            }
        }
    }
}
