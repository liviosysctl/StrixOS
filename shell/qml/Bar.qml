// The top bar (TopBar in StrixUI): no surface of its own, small text and symbols straight on the
// wallpaper. Everything in it is a button that answers the pointer, and none needs a hint.
// Left: search, the clock (a click shows the month under it), CPU and memory (the system
// monitor), then what is playing (a click on the title opens the media player under it).
// Middle: the workspaces of Hyprland. Right: the network, the volume (scrolling turns it) and the
// battery when there is one, each opening its page in Settings, the bell with its count and power.
// Super Shift Space hides it (ipc: bar toggle).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland
import Strix

Scope {
    id: root

    property bool shown: true

    IpcHandler {
        target: "bar"
        function toggle(): void { root.shown = !root.shown }
    }

    // What is playing: the player that plays, else the last one that did, else the first
    property var lastPlayer: null
    readonly property var player: {
        const players = Mpris.players.values
        return players.find(p => p.isPlaying)
            || (players.includes(root.lastPlayer) ? root.lastPlayer : null)
            || players[0] || null
    }
    // The screen whose bar shows the media player, "" when it is closed
    property string mediaOn: ""
    // The screen whose bar shows the month, "" when it is closed
    property string calendarOn: ""

    function settings(page) {
        Quickshell.execDetached(["strix-settings", page])
    }
    onPlayerChanged: {
        if (!root.player) root.mediaOn = ""
        else if (root.player.isPlaying) root.lastPlayer = root.player
    }
    // MPRIS sends the position only on a seek: ask for it every second while the player is open
    Timer {
        interval: 1000
        repeat: true
        running: root.mediaOn !== "" && !!root.player && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // The network: the Wi-Fi it is connected to, else a cable, else offline
    readonly property string network: {
        const devices = Networking.devices.values
        const wifi = devices.find(d => d.type === DeviceType.Wifi && d.connected)
        if (wifi) {
            const net = wifi.networks.values.find(n => n.connected)
            return net ? net.name : "Wi-Fi"
        }
        if (devices.some(d => d.type === DeviceType.Wired && d.connected)) return "Wired"
        return "Offline"
    }

    // The volume of the default output
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: root.sink ? [root.sink] : [] }
    readonly property real volume: root.sink && root.sink.audio ? root.sink.audio.volume : 0
    readonly property bool muted: !!(root.sink && root.sink.audio && root.sink.audio.muted)

    // The battery, on a laptop
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(root.battery && root.battery.ready && root.battery.isLaptopBattery)
    readonly property real charge: root.hasBattery ? (root.battery.percentage > 1 ? root.battery.percentage / 100 : root.battery.percentage) : 0
    readonly property bool charging: root.hasBattery && (root.battery.state === UPowerDeviceState.Charging
        || root.battery.state === UPowerDeviceState.FullyCharged || root.battery.state === UPowerDeviceState.PendingCharge)

    // CPU from /proc/stat, memory from /proc/meminfo, every two seconds
    property real cpu: 0
    property real memory: 0
    property var lastCpu: null

    FileView { id: stat; path: "/proc/stat" }
    FileView { id: meminfo; path: "/proc/meminfo" }
    Timer {
        interval: 2000
        // The dock shows the same figures, also while the bar is hidden
        running: true
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
            id: bar
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
                MeterGroup {
                    id: clockButton
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.calendarOn = root.calendarOn === bar.modelData.name ? "" : bar.modelData.name
                    Label {
                        textStyle: "label"
                        color: Theme.text
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                    }
                }
                // CPU and memory are one button: the system monitor (btop, strix-monitor)
                MeterGroup {
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: Quickshell.execDetached(["strix-monitor"])
                    Meter { label: "CPU"; value: root.cpu }
                    Meter { label: "MEM"; value: root.memory }
                }

                Row {
                    id: playing
                    visible: !!root.player
                    spacing: Theme.space1
                    anchors.verticalCenter: parent.verticalCenter
                    IconButton {
                        small: true
                        iconName: root.player && root.player.isPlaying ? "pause" : "play"
                        enabled: !!root.player && root.player.canTogglePlaying
                        onClicked: root.player.togglePlaying()
                    }
                    Label {
                        textStyle: "micro"
                        color: Theme.textMuted
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 220)
                        text: !root.player ? "" : [root.player.trackTitle, root.player.trackArtist].filter(t => t).join("  ") || root.player.identity
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.mediaOn = root.mediaOn === bar.modelData.name ? "" : bar.modelData.name
                        }
                    }
                }
            }

            PopupWindow {
                visible: root.shown && !!root.player && root.mediaOn === bar.modelData.name
                anchor.window: bar
                anchor.rect.x: Theme.space4
                anchor.rect.y: bar.height
                implicitWidth: media.implicitWidth
                implicitHeight: media.implicitHeight
                color: "transparent"

                MediaPlayer {
                    id: media
                    anchors.fill: parent
                    title: root.player ? root.player.trackTitle : ""
                    artist: root.player ? root.player.trackArtist : ""
                    cover: root.player ? root.player.trackArtUrl : ""
                    playing: !!root.player && root.player.isPlaying
                    position: root.player && root.player.positionSupported ? root.player.position : 0
                    length: root.player && root.player.lengthSupported ? root.player.length : 0
                    onPrevious: if (root.player.canGoPrevious) root.player.previous()
                    onToggle: if (root.player.canTogglePlaying) root.player.togglePlaying()
                    onNext: if (root.player.canGoNext) root.player.next()
                }
            }

            PopupWindow {
                visible: root.shown && root.calendarOn === bar.modelData.name
                anchor.window: bar
                anchor.rect.x: clockButton.mapToItem(null, 0, 0).x
                anchor.rect.y: bar.height
                implicitWidth: month.width + 2 * Theme.space4
                implicitHeight: month.height + 2 * Theme.space4
                color: "transparent"

                Surface {
                    anchors.fill: parent
                    elevation: "panel"
                    Calendar {
                        id: month
                        x: Theme.space4
                        y: Theme.space4
                        today: clock.date
                    }
                }
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

                MeterGroup {
                    id: net
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.settings("network")
                    Icon {
                        name: "wifi"
                        size: 14
                        hovered: net.hovered
                        color: net.hovered ? Theme.text : Theme.textMuted
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        textStyle: "micro"
                        color: root.network === "Offline" ? Theme.textFaint : net.hovered ? Theme.text : Theme.textMuted
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.network
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 140)
                    }
                }
                MeterGroup {
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.settings("sound")
                    Meter {
                        label: "VOL"
                        value: root.muted ? 0 : root.volume
                        valueText: root.muted ? "off" : Math.round(root.volume * 100) + "%"
                    }
                    // Scrolling turns the volume in steps of 5 %
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            if (!root.sink || !root.sink.audio) return
                            const step = event.angleDelta.y > 0 ? 0.05 : event.angleDelta.y < 0 ? -0.05 : 0
                            root.sink.audio.muted = false
                            root.sink.audio.volume = Math.max(0, Math.min(1, root.sink.audio.volume + step))
                        }
                    }
                }
                MeterGroup {
                    visible: root.hasBattery
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.settings("power")
                    Meter {
                        label: root.charging ? "AC" : "BAT"
                        value: root.charge
                        valueText: Math.round(root.charge * 100) + "%"
                    }
                }
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
