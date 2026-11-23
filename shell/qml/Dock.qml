// The dock (EdgeDock in StrixUI): part of the bottom edge, for what the bar does not have. At rest
// a thin tab with a short line in the accent; when the pointer reaches it, it rises, and sinks
// back a moment after the pointer left.
// Tools, one click instead of a key: a screenshot of a region, one to draw on, the text of a
// region, a recording of a region (red while one runs, a click stops it), the colour picker; the clipboard history and the theme picker;
// the night light, in the accent while it is on.
// Then what is playing, the only place for it: play or pause, and the title, which opens the
// media player above it. A second click, Escape or a click elsewhere folds it back, and while
// it is open the dock stays out.
// ipc: dock open media, dock close.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Strix

Scope {
    id: root

    /// The top bar: it knows whether a recording runs
    required property var bar

    /// The media player is open
    property bool open: false
    /// The screen whose dock shows it
    property string screenName: ""

    function toggle(screen) {
        if (root.open && root.screenName === screen) { root.open = false; return }
        root.screenName = screen
        root.open = true
    }

    /// Runs a tool and folds the player back
    function run(command) {
        root.open = false
        Quickshell.execDetached(command)
    }

    IpcHandler {
        target: "dock"
        function open(panel: string): void {
            if (panel !== "media" || !root.player) return
            root.screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name
                : Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
            root.open = true
        }
        function close(): void { root.open = false }
        function isOpen(): bool { return root.open }
    }

    // ---------------------------------------------------------------- the night light
    // strix-nightlight, read whenever a dock rises: it also changes elsewhere
    property bool night: false
    Process {
        id: readNight
        command: ["strix-nightlight", "state"]
        stdout: StdioCollector { onStreamFinished: root.night = text.trim() === "on" }
    }

    // ---------------------------------------------------------------- what is playing
    // The player that plays, else the last one that did, else the first
    property var lastPlayer: null
    readonly property var player: {
        const players = Mpris.players.values
        return players.find(p => p.isPlaying)
            || (players.includes(root.lastPlayer) ? root.lastPlayer : null)
            || players[0] || null
    }
    onPlayerChanged: {
        if (!root.player) root.open = false
        else if (root.player.isPlaying) root.lastPlayer = root.player
    }
    // MPRIS sends the position only on a seek: ask for it every second while the player is open
    Timer {
        interval: 1000
        repeat: true
        running: root.open && !!root.player && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    // ---------------------------------------------------------------- one dock per screen
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property bool open: root.open && root.screenName === modelData.name

            // Out while the pointer is on it or the player is open, and a moment longer
            readonly property bool wanted: edgeHover.hovered || panelHover.hovered || open
            property bool out: false
            onWantedChanged: {
                if (wanted) { sink.stop(); out = true }
                else sink.restart()
            }
            onOutChanged: if (out) readNight.running = true
            Timer { id: sink; interval: 350; onTriggered: win.out = false }

            WlrLayershell.namespace: "strix-dock"
            WlrLayershell.layer: WlrLayer.Top
            // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
            WlrLayershell.keyboardFocus: win.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors.bottom: true
            implicitWidth: 640
            implicitHeight: Theme.dockHeight + Theme.space2 + 200
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
                active: win.open
                onCleared: if (win.open) root.open = false
            }

            Shortcut { sequence: "Escape"; enabled: win.open; onActivated: root.open = false }

            Presence { id: presence; open: win.open; duration: Theme.durSlow }

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

                    // Capture
                    Tool { iconName: "crop"; onClicked: root.run(["strix-capture", "region"]) }
                    Tool { iconName: "pencil"; onClicked: root.run(["strix-capture", "annotate"]) }
                    Tool { iconName: "type"; onClicked: root.run(["strix-capture", "text"]) }
                    Tool {
                        iconName: "video"
                        checked: root.bar.recording
                        onClicked: root.run(["strix-capture", root.bar.recording ? "stop" : "record"])
                    }
                    Tool { iconName: "pipette"; onClicked: root.run(["strix-capture", "colour"]) }
                    Separator {}
                    // The surfaces of the shell that have only a key
                    Tool { iconName: "clipboard"; onClicked: root.run(["qs", "-c", "strix", "ipc", "call", "clipboard", "toggle"]) }
                    Tool { iconName: "palette"; onClicked: root.run(["qs", "-c", "strix", "ipc", "call", "theme", "picker"]) }
                    Separator {}
                    // Switches
                    Tool {
                        iconName: "moon"
                        checked: root.night
                        onClicked: {
                            root.night = !root.night
                            Quickshell.execDetached(["strix-nightlight", root.night ? "on" : "off"])
                        }
                    }

                    Separator { visible: !!root.player }
                    Tool {
                        visible: !!root.player
                        iconName: root.player && root.player.isPlaying ? "pause" : "play"
                        enabled: !!root.player && root.player.canTogglePlaying
                        onClicked: root.player.togglePlaying()
                    }
                    MeterGroup {
                        id: mediaButton
                        visible: !!root.player
                        anchors.verticalCenter: parent.verticalCenter
                        gap: Theme.space2
                        onClicked: root.toggle(win.modelData.name)
                        // The middle button plays or pauses, the wheel goes to the next or the last title
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: if (root.player && root.player.canTogglePlaying) root.player.togglePlaying()
                        }
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse
                            onWheel: event => {
                                if (!root.player) return
                                if (event.angleDelta.y < 0 && root.player.canGoNext) root.player.next()
                                else if (event.angleDelta.y > 0 && root.player.canGoPrevious) root.player.previous()
                            }
                        }
                        Icon {
                            name: "music"
                            size: 12
                            hovered: mediaButton.hovered
                            color: win.open ? Theme.accentText : mediaButton.hovered ? Theme.text : Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            textStyle: "micro"
                            color: win.open || mediaButton.hovered ? Theme.text : Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 200)
                            text: !root.player ? "" : [root.player.trackTitle, root.player.trackArtist].filter(t => t).join("  ") || root.player.identity
                        }
                    }
                }
            }

            component Tool: IconButton {
                small: true
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            }

            component Separator: Item {
                width: Theme.space2 + 1
                height: 12
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Rectangle { anchors.centerIn: parent; width: Theme.lineHair; height: parent.height; color: Theme.border }
            }

            // ------------------------------------------------------------ the media player
            Item {
                id: panelBox

                /// The middle of the title in the window, where it stands once the dock is out
                readonly property real sourceX: (win.width - dock.openWidth) / 2 + 6 + mediaButton.x + mediaButton.width / 2

                visible: presence.present
                width: mediaPanel.width
                height: mediaPanel.height
                x: Math.round(Math.max(0, Math.min(win.width - width, sourceX - width / 2)))
                y: win.height - Theme.dockHeight - Theme.space2 - height
                opacity: presence.shown
                // It grows out of the title
                transform: Scale {
                    origin.x: panelBox.sourceX - panelBox.x
                    origin.y: panelBox.height + Theme.space2
                    xScale: 0.6 + 0.4 * presence.shown
                    yScale: 0.6 + 0.4 * presence.shown
                }
                HoverHandler { id: panelHover }

                MediaPlayer {
                    id: mediaPanel
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
            }
        }
    }
}
