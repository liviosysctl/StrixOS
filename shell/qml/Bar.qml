// The top bar (TopBar in StrixUI): no surface of its own, small text and symbols straight on the
// wallpaper. Everything in it is a button that answers the pointer, and none needs a hint.
// Left: search, the clock (a click shows the month under it), CPU and memory (the system
// monitor). What is playing is in the dock.
// Middle: the workspaces of Hyprland. Right: the network, Bluetooth, the volume (scrolling turns
// it), the battery when there is one, the bell with its count and power. Network, Bluetooth,
// volume, battery and power drop a quick panel under their symbol (WifiPanel, BluetoothPanel,
// SoundPanel, PowerPanel, SessionPanel) with what is needed most and the way to Settings; a
// click elsewhere, Escape or the same symbol again folds it back.
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

    IpcHandler {
        target: "bar"
        function toggle(): void { root.shown = !root.shown }
        function open(panel: string): void {
            const screen = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name
                : Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
            root.drop = ["wifi", "bluetooth", "sound", "power", "session"].indexOf(panel) >= 0 || (panel === "update" && root.updateReady) ? panel : "session"
            root.dropOn = screen
        }
        function close(): void { root.drop = "" }
        function isOpen(): string { return root.drop }
    }

    /// The quick panel under a symbol: "", "update", "wifi", "bluetooth", "sound", "power" or "session"
    property string drop: ""
    /// The screen whose bar shows it
    property string dropOn: ""
    function toggleDrop(name, screen) {
        if (root.drop === name && root.dropOn === screen) { root.drop = ""; return }
        root.calendarOn = ""
        root.dropOn = screen
        root.drop = name
    }
    onShownChanged: if (!shown) root.drop = ""

    // The screen whose bar shows the month, "" when it is closed
    property string calendarOn: ""

    function settings(page) {
        root.drop = ""
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
    onUpdateReadyChanged: if (!updateReady && root.drop === "update") root.drop = ""

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
                    onClicked: { root.drop = ""; root.calendarOn = root.calendarOn === bar.modelData.name ? "" : bar.modelData.name }
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

            }

            // The calendar under the clock. A click anywhere else or Escape folds it back, like a
            // quick panel
            HyprlandFocusGrab {
                windows: [bar, calendarWindow]
                active: root.calendarOn === bar.modelData.name
                onCleared: if (root.calendarOn === bar.modelData.name) root.calendarOn = ""
            }
            PopupWindow {
                id: calendarWindow
                visible: root.shown && calendarPresence.present
                anchor.window: bar
                anchor.rect.x: clockButton.mapToItem(null, 0, 0).x
                anchor.rect.y: bar.height
                implicitWidth: month.width + 2 * Theme.space4
                implicitHeight: month.height + 2 * Theme.space4
                color: "transparent"

                Presence { id: calendarPresence; open: root.calendarOn === bar.modelData.name }

                Surface {
                    anchors.fill: parent
                    elevation: "panel"
                    opacity: calendarPresence.shown
                    transform: Translate { y: -6 * (1 - calendarPresence.shown) }
                    focus: true
                    Keys.onEscapePressed: root.calendarOn = ""
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
                anchors { right: parent.right; rightMargin: Theme.space4; verticalCenter: parent.verticalCenter }
                spacing: Theme.space3

                Label {
                    visible: root.layout !== ""
                    textStyle: "micro"
                    color: Theme.textMuted
                    anchors.verticalCenter: parent.verticalCenter
                    font.capitalization: Font.AllUppercase
                    text: root.layout.slice(0, 2)
                }
                // A newer version is there: the mark drops what changed and installs it
                MeterGroup {
                    id: upd
                    visible: root.updateReady
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.toggleDrop("update", bar.modelData.name)
                    Icon {
                        name: "download"
                        size: 14
                        hovered: upd.hovered
                        color: upd.hovered ? Theme.text : Theme.accentText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                MeterGroup {
                    id: net
                    anchors.verticalCenter: parent.verticalCenter
                    gap: Theme.space2
                    onClicked: root.toggleDrop("wifi", bar.modelData.name)
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
                    id: bt
                    visible: root.adapter !== null
                    anchors.verticalCenter: parent.verticalCenter
                    gap: Theme.space1
                    onClicked: root.toggleDrop("bluetooth", bar.modelData.name)
                    Icon {
                        name: "bluetooth"
                        size: 14
                        hovered: bt.hovered
                        color: !(root.adapter && root.adapter.enabled) ? Theme.textFaint : bt.hovered ? Theme.text : Theme.textMuted
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        visible: root.btConnected > 0
                        textStyle: "micro"
                        color: bt.hovered ? Theme.text : Theme.textMuted
                        anchors.verticalCenter: parent.verticalCenter
                        text: String(root.btConnected)
                    }
                }
                MeterGroup {
                    id: vol
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.toggleDrop("sound", bar.modelData.name)
                    Meter {
                        label: "VOL"
                        value: root.muted ? 0 : root.volume
                        valueText: root.muted ? "off" : Math.round(root.volume * 100) + "%"
                    }
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
                MeterGroup {
                    id: bat
                    visible: root.hasBattery
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.toggleDrop("power", bar.modelData.name)
                    Meter {
                        label: root.charging ? "AC" : "BAT"
                        value: root.charge
                        valueText: Math.round(root.charge * 100) + "%"
                    }
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
                MeterGroup {
                    id: rec
                    visible: root.recording
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: Quickshell.execDetached(["strix-capture", "stop"])
                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
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
                        textStyle: "micro"
                        color: rec.hovered ? Theme.text : Theme.error
                        anchors.verticalCenter: parent.verticalCenter
                        font.features: { "tnum": 1 }
                        text: rec.hovered ? "Stop"
                            : "REC " + Math.floor(root.recordingSeconds / 60) + ":" + ("0" + root.recordingSeconds % 60).slice(-2)
                    }
                }
                // An app listens to the microphone: the mark says so, a click shows the sound panel
                IconButton {
                    small: true
                    iconName: "mic"
                    checked: true
                    visible: root.listening
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.toggleDrop("sound", bar.modelData.name)
                }
                Tray {
                    window: bar
                    anchors.verticalCenter: parent.verticalCenter
                    giveWay: root.drop !== "" || root.calendarOn !== ""
                    onOpenChanged: if (open) { root.drop = ""; root.calendarOn = "" }
                }
                IconButton {
                    small: true
                    iconName: "coffee"
                    checked: root.awake
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.stayAwake(!root.awake)
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
                    id: powerButton
                    small: true
                    iconName: "power"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: root.toggleDrop("session", bar.modelData.name)
                }
            }

            // ---------------------------------------------------------------- the quick panels
            readonly property string dropHere: root.dropOn === bar.modelData.name ? root.drop : ""
            /// What the popup shows; stays while it folds back
            property string dropShowing: "wifi"
            onDropHereChanged: if (dropHere !== "") dropShowing = dropHere

            HyprlandFocusGrab {
                windows: [bar, dropWindow]
                active: bar.dropHere !== ""
                onCleared: if (root.dropOn === bar.modelData.name) root.drop = ""
            }

            PopupWindow {
                id: dropWindow
                readonly property Item source: ({ update: upd, wifi: net, bluetooth: bt, sound: vol, power: bat, session: powerButton })[bar.dropShowing] || powerButton
                readonly property Item body: ({ update: updateDrop, wifi: wifiDrop, bluetooth: btDrop, sound: soundDrop, power: powerDrop, session: sessionDrop })[bar.dropShowing] || sessionDrop

                visible: root.shown && dropPresence.present
                anchor.window: bar
                // Under its symbol, its right edge at the symbol's right edge, inside the screen
                anchor.rect.x: Math.max(Theme.space2, Math.min(bar.width - width - Theme.space2,
                    source.mapToItem(null, source.width, 0).x - width + Theme.space2))
                anchor.rect.y: bar.height
                implicitWidth: body.width
                implicitHeight: body.height + Theme.space2
                color: "transparent"

                Presence { id: dropPresence; open: bar.dropHere !== "" }

                Item {
                    anchors.fill: parent
                    opacity: dropPresence.shown
                    focus: true
                    Keys.onEscapePressed: root.drop = ""
                    transform: Translate { y: -6 * (1 - dropPresence.shown) }

                    UpdatePanel {
                        id: updateDrop
                        y: Theme.space2
                        visible: bar.dropShowing === "update"
                        update: root.update
                        onDone: root.drop = ""
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
                        onDone: root.drop = ""
                        onSettings: page => root.settings(page)
                    }
                }
            }
        }
    }
}
