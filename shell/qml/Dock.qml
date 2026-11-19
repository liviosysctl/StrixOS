// The dock (EdgeDock in StrixUI): part of the bottom edge. At rest a thin tab with a short line in
// the accent; when the pointer reaches it, it rises and shows its symbols, and sinks back a moment
// after the pointer left. A click on a symbol lets its panel grow upward out of that symbol; a
// second click, Escape or a click elsewhere folds it back, and while a panel is open the dock
// stays out.
// Symbols: Settings, the date (Today, System and About), what is playing, Wi-Fi, Bluetooth, sound
// and About. "Check" in About runs the update and shows its progress in place.
// ipc: dock open <panel> (main, media, wifi, bluetooth, sound), dock close.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Strix

Scope {
    id: root

    /// The top bar: it already knows the load, the player and the volume
    required property var bar

    /// The open panel: "", "main", "media", "wifi", "bluetooth" or "sound"
    property string panel: ""
    /// The screen whose dock shows it
    property string screenName: ""
    /// The tab of the main panel: 0 Today, 1 System, 2 About
    property int tab: 0

    function toggle(name, screen, tab) {
        if (root.panel === name && root.screenName === screen && (tab === undefined || tab === root.tab)) {
            root.panel = ""
            return
        }
        if (tab !== undefined) root.tab = tab
        root.screenName = screen
        root.panel = name
    }

    function settings(page) {
        root.panel = ""
        Quickshell.execDetached(["strix-settings", page])
    }

    IpcHandler {
        target: "dock"
        function open(panel: string): void {
            const screen = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name
                : Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
            root.screenName = screen
            root.panel = ["main", "media", "wifi", "bluetooth", "sound"].indexOf(panel) >= 0 ? panel : "main"
        }
        function close(): void { root.panel = "" }
        function isOpen(): bool { return root.panel !== "" }
    }

    readonly property var player: root.bar.player
    onPlayerChanged: if (!root.player && root.panel === "media") root.panel = ""
    // MPRIS sends the position only on a seek: ask for it every second while the player is open
    Timer {
        interval: 1000
        repeat: true
        running: root.panel === "media" && !!root.player && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property var weekdays: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    readonly property var months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    /// How much of the day is over, 0 to 1
    readonly property real dayPart: (clock.date.getHours() * 60 + clock.date.getMinutes()) / 1440

    // ---------------------------------------------------------------- System: the disk
    property real diskUsed: 0
    property real diskSize: 0
    Process {
        id: df
        command: ["df", "-B1", "--output=used,size", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n").pop().trim().split(/\s+/).map(Number)
                if (f.length === 2 && f[1] > 0) { root.diskUsed = f[0]; root.diskSize = f[1] }
            }
        }
    }
    readonly property bool watchingSystem: root.panel === "main" && root.tab === 1
    onWatchingSystemChanged: if (watchingSystem) df.running = true
    function gib(bytes) { return Math.round(bytes / 1073741824) + " GiB" }

    // ---------------------------------------------------------------- About: version and update
    property string distro: ""
    property string version: ""
    FileView {
        id: release
        path: "/etc/os-release"
        printErrors: false
        onLoaded: {
            const name = /^NAME="?([^"\n]*)"?/m.exec(text())
            const v = /^IMAGE_VERSION="?([^"\n]*)"?/m.exec(text())
            root.distro = name ? name[1] : ""
            root.version = v ? v[1] : ""
        }
    }

    /// "idle", "running", "current" (nothing new), "updated", "cancelled" or "failed"
    property string updateState: "idle"
    property string updateLine: ""
    Process {
        id: update
        // polkit asks for the password; the tool itself is the one of `sudo strix-update`
        command: ["pkexec", "/run/current-system/sw/bin/strix-update"]
        stdout: SplitParser { onRead: line => { if (line.trim() !== "") root.updateLine = line.trim() } }
        stderr: SplitParser { onRead: line => { if (line.trim() !== "") root.updateLine = line.trim() } }
        onExited: code => {
            // pkexec: 126 the dialog was dismissed, 127 the password was wrong or not allowed
            root.updateState = code === 126 || code === 127 ? "cancelled"
                : code !== 0 ? "failed"
                : /already up to date/i.test(root.updateLine) ? "current" : "updated"
            release.reload()
        }
    }
    function check() {
        if (update.running) return
        root.updateLine = ""
        root.updateState = "running"
        update.running = true
    }
    readonly property string updateTitle: ({
        idle: root.distro + " " + root.version,
        running: "Updating",
        current: "You are up to date",
        updated: "Updated",
        cancelled: "Not updated",
        failed: "Update failed"
    })[root.updateState]
    readonly property string updateText: ({
        idle: "Check fetches the newest release",
        running: root.updateLine || "Asking for the newest release",
        current: "Checked just now",
        updated: "Restart to use the new version",
        cancelled: "The password was not given",
        failed: root.updateLine || "The previous version stays active"
    })[root.updateState]

    // ---------------------------------------------------------------- one dock per screen
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property bool here: root.screenName === modelData.name
            readonly property string open: here ? root.panel : ""
            /// What the panel shows; stays while it folds back
            property string showing: "main"
            onOpenChanged: if (open !== "") showing = open

            // Out while the pointer is on it or a panel is open, and a moment longer
            readonly property bool wanted: edgeHover.hovered || panelHover.hovered || open !== ""
            property bool out: false
            onWantedChanged: {
                if (wanted) { sink.stop(); out = true }
                else sink.restart()
            }
            Timer { id: sink; interval: 350; onTriggered: win.out = false }

            WlrLayershell.namespace: "strix-dock"
            WlrLayershell.layer: WlrLayer.Top
            // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
            WlrLayershell.keyboardFocus: win.open !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors.bottom: true
            implicitWidth: 520
            implicitHeight: Theme.dockHeight + Theme.space2 + 320
            color: "transparent"
            // Only the dock and its panel take the pointer; the rest of this window lets it through
            mask: Region {
                x: edge.x
                y: edge.y
                width: edge.width
                height: edge.height
                Region {
                    x: panelBox.x
                    y: panelBox.y
                    width: presence.present ? panelBox.width : 0
                    height: presence.present ? panelBox.height : 0
                }
            }

            HyprlandFocusGrab {
                windows: [win]
                active: win.open !== ""
                onCleared: if (win.here) root.panel = ""
            }

            Shortcut { sequence: "Escape"; enabled: win.open !== ""; onActivated: root.panel = "" }

            Presence { id: presence; open: win.open !== ""; duration: Theme.durSlow }

            // The strip the pointer has to reach: the tab at rest, the whole dock and the gap up to
            // its panel once it is out. The dock is its child, so its symbols keep the hover.
            Item {
                id: edge
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: (win.out ? dock.openWidth : dock.restWidth) + 2 * Theme.space3
                height: win.out ? Theme.dockHeight + Theme.space2 : Theme.dockRest + 1
                HoverHandler { id: edgeHover }

                EdgeDock {
                    id: dock
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    out: win.out

                    IconButton {
                        small: true
                        iconName: "settings"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.settings("")
                    }
                    Separator {}
                    MeterGroup {
                        id: today
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.toggle("main", win.modelData.name, 0)
                        Row {
                            spacing: Theme.space2
                            anchors.verticalCenter: parent.verticalCenter
                            Icon {
                                name: "calendar"
                                size: 12
                                hovered: today.hovered
                                color: win.open === "main" && root.tab !== 2 ? Theme.accentText : today.hovered ? Theme.text : Theme.textMuted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Label {
                                textStyle: "label"
                                color: win.open === "main" && root.tab !== 2 ? Theme.accentText : Theme.text
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.weekdays[clock.date.getDay()].slice(0, 3) + " " + clock.date.getDate() + " " + root.months[clock.date.getMonth()].slice(0, 3)
                            }
                        }
                    }
                    Separator {}
                    IconButton {
                        id: mediaButton
                        visible: !!root.player
                        small: true
                        iconName: "music"
                        checked: win.open === "media"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.toggle("media", win.modelData.name)
                    }
                    IconButton {
                        id: wifiButton
                        small: true
                        iconName: "wifi"
                        checked: win.open === "wifi"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.toggle("wifi", win.modelData.name)
                    }
                    IconButton {
                        id: bluetoothButton
                        small: true
                        iconName: "bluetooth"
                        checked: win.open === "bluetooth"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.toggle("bluetooth", win.modelData.name)
                    }
                    IconButton {
                        id: soundButton
                        small: true
                        iconName: root.bar.muted ? "x" : "volume-2"
                        checked: win.open === "sound"
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.toggle("sound", win.modelData.name)
                    }
                    Separator {}
                    IconButton {
                        id: aboutButton
                        small: true
                        iconName: "info"
                        checked: win.open === "main" && root.tab === 2
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: root.toggle("main", win.modelData.name, 2)
                    }
                }
            }

            component Separator: Item {
                width: Theme.space2 + 1
                height: 12
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Rectangle { anchors.centerIn: parent; width: Theme.lineHair; height: parent.height; color: Theme.border }
            }

            // ------------------------------------------------------------ the panel
            Item {
                id: panelBox

                /// The symbol the panel grows out of
                readonly property Item source: ({ media: mediaButton, wifi: wifiButton, bluetooth: bluetoothButton, sound: soundButton })[win.showing]
                    || (root.tab === 2 ? aboutButton : today)
                /// The middle of that symbol in the window, where it stands once the dock is out
                readonly property real sourceX: (win.width - dock.openWidth) / 2 + 6 + source.x + source.width / 2
                readonly property Item body: ({ media: mediaPanel, wifi: wifiPanel, bluetooth: bluetoothPanel, sound: soundPanel })[win.showing] || mainPanel

                visible: presence.present
                width: body.width
                height: body.height
                // The main panel sits over the middle of the dock, a small one over its symbol
                x: win.showing === "main" ? Math.round((win.width - width) / 2)
                    : Math.round(Math.max(0, Math.min(win.width - width, sourceX - width / 2)))
                y: win.height - Theme.dockHeight - Theme.space2 - height
                opacity: presence.shown
                transform: Scale {
                    origin.x: panelBox.sourceX - panelBox.x
                    origin.y: panelBox.height + Theme.space2
                    xScale: 0.6 + 0.4 * presence.shown
                    yScale: 0.6 + 0.4 * presence.shown
                }
                HoverHandler { id: panelHover }

                // -------------------------------------------------------- Today, System, About
                Surface {
                    id: mainPanel
                    visible: win.showing === "main"
                    elevation: "panel"
                    width: 196 + Theme.space5 + 196 + 2 * Theme.space4
                    height: tabs.implicitHeight + 2 * Theme.space4

                    Column {
                        id: tabs
                        x: Theme.space4
                        y: Theme.space4
                        width: parent.width - 2 * Theme.space4
                        spacing: Theme.space3

                        Segmented {
                            id: sections
                            anchors.horizontalCenter: parent.horizontalCenter
                            model: [{ text: "Today", icon: "calendar" }, { text: "System", icon: "gauge" }, { text: "About", icon: "info" }]
                            onActivated: index => root.tab = index
                        }
                        // The symbols of the dock choose the tab too
                        Binding { target: sections; property: "currentIndex"; value: root.tab }

                        Item {
                            width: parent.width
                            height: month.height

                            component Tab: Item {
                                property bool current: false
                                anchors.fill: parent
                                opacity: current ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                            }

                            Tab {
                                current: root.tab === 0
                                Column {
                                    width: 196
                                    spacing: Theme.space2
                                    Plate { text: root.weekdays[clock.date.getDay()] }
                                    Label { textStyle: "title-lg"; color: Theme.text; text: clock.date.getDate() + " " + root.months[clock.date.getMonth()] }
                                    Rule { width: parent.width }
                                    Label { textStyle: "clock"; font.pixelSize: 40; lineHeight: 44; color: Theme.text; text: Qt.formatDateTime(clock.date, "HH:mm") }
                                    ProgressBar {
                                        width: parent.width
                                        label: "Day"
                                        valueText: Math.round(root.dayPart * 100) + "%"
                                        value: root.dayPart
                                    }
                                }
                                Calendar {
                                    id: month
                                    anchors.right: parent.right
                                    today: clock.date
                                }
                            }

                            Tab {
                                current: root.tab === 1
                                Column {
                                    width: parent.width
                                    spacing: Theme.space3
                                    topPadding: Theme.space2
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: Theme.space6
                                        Ring { label: "CPU"; value: root.watchingSystem ? root.bar.cpu : 0 }
                                        Ring { label: "MEM"; value: root.watchingSystem ? root.bar.memory : 0 }
                                        Ring { visible: root.bar.hasBattery; label: root.bar.charging ? "AC" : "BAT"; value: root.watchingSystem ? root.bar.charge : 0 }
                                    }
                                    ProgressBar {
                                        width: parent.width
                                        label: "Disk /"
                                        valueText: root.diskSize > 0 ? root.gib(root.diskUsed) + " of " + root.gib(root.diskSize) : ""
                                        value: root.diskSize > 0 ? root.diskUsed / root.diskSize : 0
                                    }
                                    Button {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        small: true
                                        variant: "quiet"
                                        iconName: "gauge"
                                        text: "System monitor"
                                        onClicked: { root.panel = ""; Quickshell.execDetached(["strix-monitor"]) }
                                    }
                                }
                            }

                            Tab {
                                current: root.tab === 2
                                Column {
                                    width: parent.width
                                    spacing: Theme.space3
                                    topPadding: Theme.space3
                                    Row {
                                        spacing: Theme.space3
                                        Label { id: mark; textStyle: "emblem"; lineHeight: 40; color: Theme.text; text: root.distro }
                                        Label { textStyle: "caption"; color: Theme.textMuted; text: root.version; anchors.baseline: mark.baseline }
                                    }
                                    Label { textStyle: "motto"; color: Theme.textMuted; text: "nocte vigilat" }
                                    Rule { width: parent.width }
                                    Row {
                                        width: parent.width
                                        spacing: Theme.space3
                                        Icon {
                                            name: root.updateState === "running" ? "refresh-cw" : root.updateState === "failed" ? "triangle-alert"
                                                : root.updateState === "idle" || root.updateState === "cancelled" ? "download" : "check"
                                            size: 16
                                            color: root.updateState === "failed" ? Theme.error : Theme.accentText
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Column {
                                            width: parent.width - 16 - checkButton.width - 2 * parent.spacing
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 2
                                            Label { width: parent.width; textStyle: "label"; color: Theme.text; elide: Text.ElideRight; text: root.updateTitle }
                                            Label { width: parent.width; textStyle: "caption"; color: Theme.textMuted; elide: Text.ElideRight; text: root.updateText }
                                            ProgressBar {
                                                visible: root.updateState === "running"
                                                width: parent.width
                                                indeterminate: true
                                            }
                                        }
                                        Button {
                                            id: checkButton
                                            small: true
                                            text: "Check"
                                            loading: root.updateState === "running"
                                            enabled: root.updateState !== "running"
                                            anchors.verticalCenter: parent.verticalCenter
                                            onClicked: root.check()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // -------------------------------------------------------- what is playing
                MediaPlayer {
                    id: mediaPanel
                    visible: win.showing === "media"
                    width: implicitWidth
                    height: implicitHeight
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

                // -------------------------------------------------------- the small panels
                // The same quick panels as under the symbols of the bar
                WifiPanel {
                    id: wifiPanel
                    visible: win.showing === "wifi"
                    active: win.open === "wifi"
                    onSettings: page => root.settings(page)
                }
                BluetoothPanel {
                    id: bluetoothPanel
                    visible: win.showing === "bluetooth"
                    onSettings: page => root.settings(page)
                }
                SoundPanel {
                    id: soundPanel
                    visible: win.showing === "sound"
                    onSettings: page => root.settings(page)
                }
            }
        }
    }
}
