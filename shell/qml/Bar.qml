// The top bar (TopBar in StrixUI): no surface of its own, small text and symbols straight on the
// wallpaper. Left: search and the clock, then CPU and memory. Middle: the workspaces of Hyprland.
// Right: the bell with its count and power. Super Shift Space hides it (ipc: bar toggle).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Strix

Scope {
    id: root

    property bool shown: true

    IpcHandler {
        target: "bar"
        function toggle(): void { root.shown = !root.shown }
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // CPU from /proc/stat, memory from /proc/meminfo, every two seconds
    property real cpu: 0
    property real memory: 0
    property var lastCpu: null

    FileView { id: stat; path: "/proc/stat" }
    FileView { id: meminfo; path: "/proc/meminfo" }
    Timer {
        interval: 2000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            stat.reload()
            meminfo.reload()
            const line = stat.text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
            const idle = line[3] + (line[4] || 0)
            const total = line.reduce((a, b) => a + b, 0)
            if (root.lastCpu) {
                const dt = total - root.lastCpu.total
                root.cpu = dt > 0 ? 1 - (idle - root.lastCpu.idle) / dt : 0
            }
            root.lastCpu = { idle: idle, total: total }
            const m = {}
            for (const l of meminfo.text().split("\n")) {
                const p = l.split(/:\s+/)
                if (p.length === 2) m[p[0]] = parseInt(p[1])
            }
            if (m.MemTotal) root.memory = 1 - (m.MemAvailable || 0) / m.MemTotal
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            visible: root.shown

            WlrLayershell.namespace: "strix-bar"
            anchors { top: true; left: true; right: true }
            implicitHeight: Theme.barHeight
            exclusiveZone: Theme.barHeight
            color: "transparent"

            Row {
                anchors { left: parent.left; leftMargin: Theme.space4; verticalCenter: parent.verticalCenter }
                spacing: Theme.space4

                IconButton {
                    small: true
                    iconName: "search"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "search", "toggle"])
                }
                Label {
                    textStyle: "label"
                    color: Theme.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                }
                Meter { label: "CPU"; value: root.cpu; valueText: Math.round(root.cpu * 100) + "%"; anchors.verticalCenter: parent.verticalCenter }
                Meter { label: "MEM"; value: root.memory; valueText: Math.round(root.memory * 100) + "%"; anchors.verticalCenter: parent.verticalCenter }
            }

            Workspaces {
                anchors.centerIn: parent
                count: Math.max(5, ...Hyprland.workspaces.values.map(w => w.id > 0 ? w.id : 0))
                current: (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1) - 1
                used: Hyprland.workspaces.values.filter(w => w.id > 0).map(w => w.id - 1)
                onActivated: index => Hyprland.dispatch("hl.dsp.focus({ workspace = " + (index + 1) + " })")
            }

            Row {
                anchors { right: parent.right; rightMargin: Theme.space4; verticalCenter: parent.verticalCenter }
                spacing: Theme.space3

                Row {
                    spacing: Theme.space1
                    anchors.verticalCenter: parent.verticalCenter
                    IconButton {
                        small: true
                        iconName: "bell"
                        onClicked: Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "notifications", "toggle"])
                    }
                    Label {
                        textStyle: "micro"
                        color: Theme.textMuted
                        anchors.verticalCenter: parent.verticalCenter
                        visible: text !== "0"
                        text: String(Notifs.count)
                    }
                }
                IconButton {
                    small: true
                    iconName: "power"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "search", "open", "menu:system"])
                }
            }
        }
    }
}
