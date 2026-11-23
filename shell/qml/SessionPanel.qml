// The power symbol's quick panel: lock, sleep, log out, restart and shut down, the same actions
// as the System group of Search (shell/menu.toml). Shutting down is the last row, in the error
// color, so it is never the one hit by accident.
import QtQuick
import Quickshell
import Strix

QuickPanel {
    id: root

    /// One of the rows ran: the panel closes
    signal done()

    function run(command) {
        root.done()
        Quickshell.execDetached(command)
    }

    title: "Session"
    width: 220

    ListRow { width: parent.width; iconName: "lock"; text: "Lock"; detail: "Super Esc"; onClicked: root.run(["loginctl", "lock-session"]) }
    ListRow { width: parent.width; iconName: "moon"; text: "Suspend"; onClicked: root.run(["systemctl", "suspend"]) }
    ListRow { width: parent.width; iconName: "log-out"; text: "Log out"; onClicked: root.run(["hyprctl", "dispatch", "hl.dsp.exit()"]) }
    ListRow { width: parent.width; iconName: "rotate-cw"; text: "Restart"; onClicked: root.run(["systemctl", "reboot"]) }
    ListRow {
        id: off
        width: parent.width
        iconName: "power"
        text: "Shut down"
        onClicked: root.run(["systemctl", "poweroff"])
        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusMd
            color: Theme.error
            opacity: off.hovered ? 0.14 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durFast } }
        }
    }
}
