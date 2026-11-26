// The clock on the picture, beside the god (Settings › Themes: Clock on the desktop): the time
// large in the serif of the titles, the date under it and, while something plays on a screen
// without windows, its title over the bars of the sound. It sits on the right, where the plates
// of the gods are dark and empty.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Strix

Item {
    id: root

    required property var screen

    /// No window on the workspace of this screen: only then do the bars move, so the picture
    /// under translucent windows stays still and their blur stays cheap
    readonly property bool bare: {
        const monitor = Hyprland.monitorFor(root.screen)
        const workspace = monitor ? monitor.activeWorkspace : null
        return !workspace || workspace.toplevels.values.length === 0
    }
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || null

    visible: Desktop.clock

    SystemClock { id: clock; precision: SystemClock.Minutes }

    Column {
        anchors { right: parent.right; rightMargin: Theme.space8 * 2; verticalCenter: parent.verticalCenter; verticalCenterOffset: parent.height * 0.08 }
        spacing: Theme.space1

        Label {
            anchors.right: parent.right
            textStyle: "display"
            color: Theme.text
            opacity: 0.92
            text: Qt.formatDateTime(clock.date, "HH:mm")
        }
        Label {
            anchors.right: parent.right
            textStyle: "subtitle"
            color: Theme.textMuted
            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
        }

        // What is playing: it comes and goes with the music
        Item {
            id: playing
            anchors.right: parent.right
            width: 280
            property real shown: root.player ? 1 : 0
            height: (Theme.space5 + bars.height + Theme.space2 + track.implicitHeight) * shown
            opacity: shown
            clip: true
            Behavior on shown { NumberAnimation { duration: Theme.durSlow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

            Visualizer {
                id: bars
                y: Theme.space5
                width: parent.width
                height: 40
                values: root.bare ? Spectrum.values : []
            }
            Column {
                id: track
                anchors { right: parent.right; top: bars.bottom; topMargin: Theme.space2 }
                width: parent.width
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    textStyle: "aside"
                    color: Theme.text
                    text: root.player ? root.player.trackTitle || root.player.identity : ""
                }
                Label {
                    width: parent.width
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    textStyle: "caption"
                    color: Theme.textMuted
                    text: root.player ? root.player.trackArtist || "" : ""
                }
            }
        }
    }
}
