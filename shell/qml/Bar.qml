// The top bar (TopBar in StrixUI): no band of its own, its buttons on the wallpaper, those that
// belong together on one plate of smoked glass (ChipGroup). None needs a hint.
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

    /// A share as a figure of two places: a figure space in front of a single digit keeps the
    /// button as wide as it was
    function figure(share) {
        const percent = Math.round(share * 100)
        return (percent < 10 ? "\u2007" : "") + percent + "%"
    }
    /// A text cut to `most` signs, so one long name does not push the others out of the bar
    function short(text, most) {
        return text.length > most ? text.slice(0, most - 1) + "\u2026" : text
    }

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
            id: bar
            required property var modelData
            screen: modelData
            visible: root.shown

            WlrLayershell.namespace: "strix-bar"
            anchors { top: true; left: true; right: true }
            implicitHeight: Theme.barHeight
            exclusiveZone: Theme.barHeight
            color: "transparent"

            // Every part of the bar is a button on smoked glass, as high as every control, two steps
            // from the edge of the screen. Buttons that belong together share one plate, parted by
            // hair lines (ChipGroup): fewer plates, and every plate draws a shadow
            Row {
                anchors { left: parent.left; leftMargin: Theme.space2; bottom: parent.bottom }
                spacing: Theme.space1

                ChipGroup {
                    Chip {
                        plate: false
                        iconName: "search"
                        onClicked: Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "search", "toggle"])
                    }
                    Chip {
                        id: clockButton
                        plate: false
                        open: bar.calendarHere
                        text: Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                        onClicked: root.calendarOn = bar.calendarHere ? "" : bar.modelData.name
                    }
                    // CPU and memory are one button: the system monitor (btop, strix-monitor)
                    Chip {
                        id: load
                        plate: false
                        onClicked: Quickshell.execDetached(["strix-monitor"])
                        Icon { name: "cpu"; color: load.symbolInk; hovered: load.hovered; anchors.verticalCenter: parent.verticalCenter }
                        Label { textStyle: "value"; text: root.figure(root.cpu); anchors.verticalCenter: parent.verticalCenter }
                        Icon { name: "memory-stick"; color: load.symbolInk; hovered: load.hovered; anchors.verticalCenter: parent.verticalCenter }
                        Label { textStyle: "value"; text: root.figure(root.memory); anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                // What is playing: the symbol pauses and plays, the title opens the player
                ChipGroup {
                    visible: !!root.player
                    Chip {
                        plate: false
                        iconName: root.player && root.player.isPlaying ? "pause" : "play"
                        enabled: !!root.player && root.player.canTogglePlaying
                        onClicked: root.player.togglePlaying()
                    }
                    Chip {
                        id: playing
                        plate: false
                        open: bar.mediaHere
                        text: root.short(!root.player ? "" : [root.player.trackTitle, root.player.trackArtist].filter(t => t).join("  ") || root.player.identity, 36)
                        onClicked: root.mediaOn = bar.mediaHere ? "" : bar.modelData.name
                    }
                }
            }

            // The media player under the title, folded back by a click anywhere else
            readonly property bool mediaHere: !!root.player && root.mediaOn === bar.modelData.name
            HyprlandFocusGrab {
                windows: [bar, mediaWindow]
                active: bar.mediaHere
                onCleared: if (bar.mediaHere) root.mediaOn = ""
            }
            PopupWindow {
                id: mediaWindow
                visible: root.shown && bar.mediaHere
                anchor.window: bar
                anchor.rect.x: playing.mapToItem(null, 0, 0).x
                anchor.rect.y: bar.height
                implicitWidth: media.implicitWidth
                implicitHeight: media.implicitHeight + Theme.space2
                color: "transparent"

                MediaPlayer {
                    id: media
                    y: Theme.space2
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

            // The calendar under the clock, folded back the same way
            readonly property bool calendarHere: root.calendarOn === bar.modelData.name
            HyprlandFocusGrab {
                windows: [bar, calendarWindow]
                active: bar.calendarHere
                onCleared: if (bar.calendarHere) root.calendarOn = ""
            }
            PopupWindow {
                id: calendarWindow
                visible: root.shown && bar.calendarHere
                anchor.window: bar
                anchor.rect.x: clockButton.mapToItem(null, 0, 0).x
                anchor.rect.y: bar.height
                implicitWidth: month.width + 2 * Theme.space3
                implicitHeight: month.height + 2 * Theme.space3 + Theme.space2
                color: "transparent"

                Surface {
                    y: Theme.space2
                    width: parent.width
                    height: parent.height - Theme.space2
                    elevation: "panel"
                    // The month stands one step and a half inside, its arrows near the corner
                    inset: Theme.space3
                    Calendar {
                        id: month
                        x: Theme.space3
                        y: Theme.space3
                        today: clock.date
                    }
                }
            }

            Workspaces {
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                count: Math.max(5, ...Hyprland.workspaces.values.map(w => w.id > 0 ? w.id : 0))
                current: (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1) - 1
                used: Hyprland.workspaces.values.filter(w => w.id > 0).map(w => w.id - 1)
                onActivated: index => Hyprland.dispatch("hl.dsp.focus({ workspace = " + (index + 1) + " })")
            }

            Row {
                anchors { right: parent.right; rightMargin: Theme.space2; bottom: parent.bottom }
                spacing: Theme.space1

                // The state of the machine
                ChipGroup {
                    Chip {
                        plate: false
                        iconName: "wifi"
                        text: root.short(root.network, 20)
                        faint: root.network === "Offline"
                        onClicked: root.settings("network")
                    }
                    Chip {
                        plate: false
                        iconName: root.muted ? "volume-x" : "volume-2"
                        text: root.muted ? "" : Math.round(root.volume * 100) + "%"
                        faint: root.muted
                        onClicked: root.settings("sound")
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
                    Chip {
                        plate: false
                        visible: root.hasBattery
                        iconName: root.charging ? "battery-charging" : "battery-medium"
                        text: Math.round(root.charge * 100) + "%"
                        onClicked: root.settings("power")
                    }
                }
                // The messages and the way out
                ChipGroup {
                    Chip {
                        plate: false
                        iconName: "bell"
                        text: Notifs.count > 0 ? String(Notifs.count) : ""
                        onClicked: Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "notifications", "toggle"])
                    }
                    Chip {
                        plate: false
                        iconName: "power"
                        onClicked: Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "search", "open", "menu:system"])
                    }
                }
            }
        }
    }
}
