// The top bar (TopBar in StrixUI): no surface of its own, small text and symbols straight on the
// wallpaper. Everything in it is a button that answers the pointer, and none needs a hint.
// Left: search, the clock (a click shows the month under it), CPU and memory (the system
// monitor). While the clock of the desktop is in view (no window on the workspace), the bar leaves
// the time to it and keeps only the symbol of the calendar. What is playing is in the dock.
// Middle: the workspaces of Hyprland. Right: the network, Bluetooth, the volume (scrolling turns
// it), the battery when there is one, the bell with its count and power. Network, Bluetooth,
// volume, battery and power drop a quick panel under their symbol (WifiPanel, BluetoothPanel,
// SoundPanel, PowerPanel, SessionPanel) with what is needed most and the way to Settings. Which
// one is open, and what folds it back, is in Popups.
// Super Shift Space hides it (ipc: bar toggle, bar open <panel>, bar close).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Wayland
import Strix

Scope {
    id: root

    property bool shown: true
    /// The window of the messages (Notifications): the bell opens it
    required property var messages

    IpcHandler {
        target: "bar"
        function toggle(): void { root.shown = !root.shown }
        function open(panel: string): void {
            Popups.show(["wifi", "bluetooth", "sound", "power", "session"].indexOf(panel) >= 0 || (panel === "update" && root.updateReady) ? panel : "session", Popups.here())
        }
        function close(): void { Popups.close() }
        function isOpen(): string { return root.drop }
    }

    /// The quick panel under a symbol: "", "update", "wifi", "bluetooth", "sound", "power" or "session"
    readonly property string drop: ["update", "wifi", "bluetooth", "sound", "power", "session"].indexOf(Popups.current) >= 0 ? Popups.current : ""
    // Hidden, the bar takes what hangs from it along
    onShownChanged: if (!shown && Popups.current !== "media") Popups.close()

    /// A share as a figure of two places: a figure space in front of a single digit keeps the
    /// button as wide as it was
    function figure(share) {
        const percent = Math.round(share * 100)
        return (percent < 10 ? "\u2007" : "") + percent + "%"
    }

    function settings(page) {
        Popups.close()
        Quickshell.execDetached(["strix-settings", page])
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

    // Bluetooth, when the machine has it
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property int btConnected: root.adapter ? root.adapter.devices.values.filter(d => d.connected).length : 0

    // The battery, on a laptop
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(root.battery && root.battery.ready && root.battery.isLaptopBattery)
    readonly property real charge: root.hasBattery ? (root.battery.percentage > 1 ? root.battery.percentage / 100 : root.battery.percentage) : 0
    readonly property bool charging: root.hasBattery && (root.battery.state === UPowerDeviceState.Charging
        || root.battery.state === UPowerDeviceState.FullyCharged || root.battery.state === UPowerDeviceState.PendingCharge)

    // A screen recording runs (strix-capture record): the bar shows a red mark that stops it
    property bool recording: false
    property real recordingSince: 0
    property int recordingSeconds: 0
    Timer {
        interval: 1000
        repeat: true
        running: root.recording
        onTriggered: root.recordingSeconds = Math.floor((Date.now() - root.recordingSince) / 1000)
    }
    Process {
        id: recorder
        command: ["pgrep", "-x", "wf-recorder"]
        onExited: code => {
            const now = code === 0
            if (now && !root.recording) { root.recordingSince = Date.now(); root.recordingSeconds = 0 }
            root.recording = now
        }
    }

    // The apps that record from the microphone right now (the streams linked to the default source)
    PwNodeLinkTracker { id: microphone; node: Pipewire.defaultAudioSource }
    readonly property bool listening: microphone.linkGroups.some(g => g.target && g.target.isStream)

    // Staying awake (strix-idle awake): nothing dims, locks or sleeps by itself. The cup of the bar
    // switches it and steams for as long. Read at the start and whenever the power panel opens:
    // it is also switched from a terminal
    property bool awake: false
    Process {
        id: readAwake
        command: ["strix-idle", "awake", "state"]
        running: true
        stdout: StdioCollector { onStreamFinished: root.awake = text.trim() === "on" }
    }
    function stayAwake(on) {
        root.awake = on
        Quickshell.execDetached(["strix-idle", "awake", on ? "on" : "off"])
    }
    onDropChanged: if (drop === "power") readAwake.running = true

    // CPU from /proc/stat, memory from /proc/meminfo, every two seconds
    property real cpu: 0
    property real memory: 0
    property var lastCpu: null

    // A newer version of the distribution (strix-update-check, every hour): a mark in the bar
    property var update: null
    property string updateText: ""
    FileView {
        id: updateFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/strix/update.json"
        printErrors: false
        onLoaded: {
            if (text() === root.updateText) return
            root.updateText = text()
            try { root.update = JSON.parse(root.updateText) } catch (e) { root.update = null }
        }
    }
    readonly property bool updateReady: !!(root.update && root.update.available)
    onUpdateReadyChanged: if (!updateReady && root.drop === "update") Popups.close()

    // The layout of the keyboard, once it was switched (Alt Shift with several layouts in
    // Settings › Input): the bar names it
    property string layout: ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activelayout") root.layout = event.data.split(",").pop()
        }
    }

    FileView { id: stat; path: "/proc/stat" }
    FileView { id: meminfo; path: "/proc/meminfo" }
    Timer {
        interval: 2000
        // Also while the bar is hidden: the recording and the update are looked after here too
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            recorder.running = true
            updateFile.reload()
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

            // Everything that is seen. The keys the bar gets while something hangs from it go to
            // Popups from here, whichever button has the focus
            Item {
                anchors.fill: parent
                focus: true
                Keys.onPressed: event => Popups.key(event)

                // The picture between the buttons is the desktop: a click there folds back what
                // is open
                MouseArea {
                    anchors.fill: parent
                    onPressed: Popups.close()
                }

                // Every part of the bar is a button on its own plate of smoked glass, as high as every
                // control, a step from its neighbour and two from the edge of the screen
                Row {
                    anchors { left: parent.left; leftMargin: Theme.space2; bottom: parent.bottom }
                    spacing: Theme.space1

                    Chip {
                        iconName: "search"
                        onClicked: { Popups.close(); Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "search", "toggle"]) }
                    }
                    Chip {
                        id: clockButton
                        open: bar.calendarHere
                        iconName: bar.clockOnDesktop ? "calendar" : ""
                        text: bar.clockOnDesktop ? "" : Qt.formatDateTime(clock.date, "ddd d MMM  HH:mm")
                        onClicked: Popups.toggle("calendar", bar.modelData.name)
                        Behavior on implicitWidth { NumberAnimation { duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    }
                    // CPU and memory are one button: the system monitor (btop, strix-monitor)
                    Chip {
                        id: load
                        onClicked: { Popups.close(); Quickshell.execDetached(["strix-monitor"]) }
                        Icon { name: "cpu"; color: load.symbolInk; hovered: load.hovered; anchors.verticalCenter: parent.verticalCenter }
                        Label { textStyle: "value"; text: root.figure(root.cpu); anchors.verticalCenter: parent.verticalCenter }
                        Icon { name: "memory-stick"; color: load.symbolInk; hovered: load.hovered; anchors.verticalCenter: parent.verticalCenter }
                        Label { textStyle: "value"; text: root.figure(root.memory); anchors.verticalCenter: parent.verticalCenter }
                    }
                }

                Workspaces {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    count: Math.max(5, ...Hyprland.workspaces.values.map(w => w.id > 0 ? w.id : 0))
                    current: (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1) - 1
                    used: Hyprland.workspaces.values.filter(w => w.id > 0).map(w => w.id - 1)
                    onActivated: index => Hyprland.dispatch("hl.dsp.focus({ workspace = " + (index + 1) + " })")
                    // The wheel goes to the workspace before or after
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse
                        onWheel: event => {
                            const to = parent.current + (event.angleDelta.y > 0 ? -1 : 1)
                            if (event.angleDelta.y !== 0 && to >= 0 && to < parent.count) parent.activated(to)
                        }
                    }
                }

                Row {
                    anchors { right: parent.right; rightMargin: Theme.space2; bottom: parent.bottom }
                    spacing: Theme.space1

                    // The keyboard layout, when there is more than one to tell apart
                    Chip {
                        visible: root.layout !== ""
                        text: root.layout.slice(0, 2).toUpperCase()
                        onClicked: root.settings("input")
                    }
                    // A newer version is there: the mark drops what changed and installs it
                    Chip {
                        id: upd
                        visible: root.updateReady
                        iconName: "download"
                        on: true
                        open: bar.dropHere === "update"
                        onClicked: Popups.toggle("update", bar.modelData.name)
                    }
                    Chip {
                        id: net
                        iconName: "wifi"
                        text: root.network.length > 20 ? root.network.slice(0, 19) + "…" : root.network
                        faint: root.network === "Offline"
                        open: bar.dropHere === "wifi"
                        onClicked: Popups.toggle("wifi", bar.modelData.name)
                    }
                    Chip {
                        id: bt
                        visible: root.adapter !== null
                        iconName: "bluetooth"
                        text: root.btConnected > 0 ? String(root.btConnected) : ""
                        faint: !(root.adapter && root.adapter.enabled)
                        open: bar.dropHere === "bluetooth"
                        onClicked: Popups.toggle("bluetooth", bar.modelData.name)
                    }
                    Chip {
                        id: vol
                        iconName: root.muted ? "volume-x" : "volume-2"
                        text: root.muted ? "" : Math.round(root.volume * 100) + "%"
                        faint: root.muted
                        open: bar.dropHere === "sound"
                        onClicked: Popups.toggle("sound", bar.modelData.name)
                        // The middle button mutes, scrolling turns the volume in steps of 5 %
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.sink.audio.muted
                        }
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
                        id: bat
                        visible: root.hasBattery
                        iconName: root.charging ? "battery-charging" : "battery-medium"
                        text: Math.round(root.charge * 100) + "%"
                        open: bar.dropHere === "power"
                        onClicked: Popups.toggle("power", bar.modelData.name)
                        // Scrolling turns the brightness of the screen, with its mark on the screen
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: event => {
                                if (event.angleDelta.y !== 0)
                                    Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "osd", "brightness", event.angleDelta.y > 0 ? "5%+" : "5%-"])
                            }
                        }
                    }
                    // While a recording runs: a pulsing dot and the time; a click stops it
                    Chip {
                        id: rec
                        visible: root.recording
                        onClicked: { Popups.close(); Quickshell.execDetached(["strix-capture", "stop"]) }
                        Rectangle {
                            width: Theme.space2
                            height: Theme.space2
                            radius: width / 2
                            color: Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                            SequentialAnimation on opacity {
                                running: root.recording
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                        Label {
                            textStyle: "value"
                            color: rec.hovered ? Theme.text : Theme.error
                            anchors.verticalCenter: parent.verticalCenter
                            text: rec.hovered ? "Stop"
                                : Math.floor(root.recordingSeconds / 60) + ":" + ("0" + root.recordingSeconds % 60).slice(-2)
                        }
                    }
                    // An app listens to the microphone: the mark says so, a click shows the sound panel
                    Chip {
                        visible: root.listening
                        iconName: "mic"
                        on: true
                        onClicked: Popups.toggle("sound", bar.modelData.name)
                    }
                    Tray {
                        window: bar
                        screenName: bar.modelData.name
                    }
                    Chip {
                        iconName: "coffee"
                        on: root.awake
                        onClicked: { Popups.close(); root.stayAwake(!root.awake) }
                    }
                    Chip {
                        iconName: "bell"
                        text: Notifs.count > 0 ? String(Notifs.count) : ""
                        open: bar.messagesHere
                        onClicked: Popups.toggle("notifications", bar.modelData.name)
                    }
                    Chip {
                        id: powerButton
                        iconName: "power"
                        open: bar.dropHere === "session"
                        onClicked: Popups.toggle("session", bar.modelData.name)
                    }
                }
            }

            /// The clock of the desktop shows the time and the date on this screen: it is switched on
            /// and no window stands on the workspace (as DesktopClock.bare)
            readonly property bool clockOnDesktop: {
                if (!Desktop.clock) return false
                const monitor = Hyprland.monitorFor(bar.modelData)
                const workspace = monitor ? monitor.activeWorkspace : null
                return !workspace || workspace.toplevels.values.length === 0
            }

            // The calendar under the clock, folded back like a quick panel
            readonly property bool calendarHere: Popups.shows("calendar", bar.modelData.name)
            HyprlandFocusGrab {
                windows: [bar, calendarWindow]
                active: bar.calendarHere
                onCleared: if (bar.calendarHere) Popups.close()
            }
            PopupWindow {
                id: calendarWindow
                visible: root.shown && calendarPresence.present
                anchor.window: bar
                anchor.rect.x: clockButton.mapToItem(null, 0, 0).x
                anchor.rect.y: bar.height
                implicitWidth: month.width + 2 * Theme.space3
                implicitHeight: month.height + 2 * Theme.space3 + Theme.space2
                color: "transparent"

                Presence { id: calendarPresence; open: bar.calendarHere }

                Surface {
                    y: Theme.space2
                    width: parent.width
                    height: parent.height - Theme.space2
                    elevation: "panel"
                    // The month stands one step and a half inside, its arrows near the corner
                    inset: Theme.space3
                    opacity: calendarPresence.shown
                    transform: Translate { y: -Theme.space2 * (1 - calendarPresence.shown) }
                    focus: true
                    Keys.onPressed: event => Popups.key(event)
                    Calendar {
                        id: month
                        x: Theme.space3
                        y: Theme.space3
                        today: clock.date
                    }
                }
            }

            // ---------------------------------------------------------------- the quick panels
            readonly property string dropHere: Popups.screen === bar.modelData.name ? root.drop : ""
            /// What the popup shows; stays while it folds back
            property string dropShowing: "wifi"
            onDropHereChanged: if (dropHere !== "") dropShowing = dropHere

            HyprlandFocusGrab {
                windows: [bar, dropWindow]
                active: bar.dropHere !== ""
                onCleared: if (bar.dropHere !== "") Popups.close()
            }

            // The messages are a window of their own (Notifications). While the bell has them
            // open, a click outside them and the bar folds them back like a quick panel
            readonly property bool messagesHere: Popups.shows("notifications", bar.modelData.name)
            HyprlandFocusGrab {
                windows: [bar, root.messages]
                active: bar.messagesHere
                onCleared: if (bar.messagesHere) Popups.close()
            }

            PopupWindow {
                id: dropWindow
                readonly property Item source: ({ update: upd, wifi: net, bluetooth: bt, sound: vol, power: bat, session: powerButton })[bar.dropShowing] || powerButton
                readonly property Item body: ({ update: updateDrop, wifi: wifiDrop, bluetooth: btDrop, sound: soundDrop, power: powerDrop, session: sessionDrop })[bar.dropShowing] || sessionDrop

                visible: root.shown && dropPresence.present
                anchor.window: bar
                // Under its button, its right edge at the button's right edge, inside the screen
                anchor.rect.x: Math.max(Theme.space2, Math.min(bar.width - width - Theme.space2,
                    source.mapToItem(null, source.width, 0).x - width))
                anchor.rect.y: bar.height
                implicitWidth: body.width
                implicitHeight: body.height + Theme.space2
                color: "transparent"

                Presence { id: dropPresence; open: bar.dropHere !== "" }

                Item {
                    anchors.fill: parent
                    opacity: dropPresence.shown
                    focus: true
                    Keys.onPressed: event => Popups.key(event)
                    transform: Translate { y: -Theme.space2 * (1 - dropPresence.shown) }

                    UpdatePanel {
                        id: updateDrop
                        y: Theme.space2
                        visible: bar.dropShowing === "update"
                        update: root.update
                        onDone: Popups.close()
                    }
                    WifiPanel {
                        id: wifiDrop
                        y: Theme.space2
                        visible: bar.dropShowing === "wifi"
                        active: bar.dropHere === "wifi"
                        onSettings: page => root.settings(page)
                    }
                    BluetoothPanel {
                        id: btDrop
                        y: Theme.space2
                        visible: bar.dropShowing === "bluetooth"
                        onSettings: page => root.settings(page)
                    }
                    SoundPanel {
                        id: soundDrop
                        y: Theme.space2
                        visible: bar.dropShowing === "sound"
                        onSettings: page => root.settings(page)
                    }
                    PowerPanel {
                        id: powerDrop
                        y: Theme.space2
                        visible: bar.dropShowing === "power"
                        active: bar.dropHere === "power"
                        awake: root.awake
                        onStayAwake: on => root.stayAwake(on)
                        onSettings: page => root.settings(page)
                    }
                    SessionPanel {
                        id: sessionDrop
                        y: Theme.space2
                        visible: bar.dropShowing === "session"
                        onDone: Popups.close()
                        onSettings: page => root.settings(page)
                    }
                }
            }
        }
    }
}
