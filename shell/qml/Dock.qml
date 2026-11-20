// The dock (EdgeDock in StrixUI): the apps, as part of the bottom edge. At rest a thin tab with a
// short line in the accent; when the pointer reaches it, it rises and shows the pinned apps and
// every app with a window, and sinks back a moment after the pointer left.
// A click starts an app or brings its window to the front (the next one, when it has several);
// the middle button opens another window; the right button opens the small menu of the app: new
// window, pin or unpin, close. A mark under the icon says that an app runs, a wider one in the
// accent that it has the focus. Icons are quiet until the pointer or the focus is on them.
// At its right end: what is playing, the only place for it. A click opens the media player.
// The pins are in ~/.config/strix/dock.json.
// ipc: dock open media, dock close.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets
import Strix

Scope {
    id: root

    /// The open panel: "", "media" or "app" (the menu of an app)
    property string panel: ""
    /// The screen whose dock shows it
    property string screenName: ""
    /// The app whose menu is open
    property string menuApp: ""

    function toggle(name, screen) {
        if (root.panel === name && root.screenName === screen) { root.panel = ""; return }
        root.screenName = screen
        root.panel = name
    }

    IpcHandler {
        target: "dock"
        function open(panel: string): void {
            if (panel !== "media" || !root.player) return
            root.screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name
                : Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
            root.panel = "media"
        }
        function close(): void { root.panel = "" }
        function isOpen(): bool { return root.panel !== "" }
        function apps(): int { return root.apps.length }
    }

    // ---------------------------------------------------------------- the apps
    /// The ids of the pinned apps, as their desktop files are named
    property var pinned: ["zen-beta", "com.mitchellh.ghostty", "org.gnome.Nautilus", "strix-neovim", "io.bassi.Amberol"]
    readonly property string dir: Quickshell.env("HOME") + "/.config/strix"
    FileView {
        id: stored
        path: root.dir + "/dock.json"
        printErrors: false
        onLoaded: {
            try {
                const read = JSON.parse(text())
                if (Array.isArray(read)) root.pinned = read
            } catch (e) {}
        }
    }

    function pin(id) {
        root.pinned = root.pinned.indexOf(id) >= 0 ? root.pinned.filter(p => p !== id) : root.pinned.concat([id])
        Quickshell.execDetached(["mkdir", "-p", root.dir])
        stored.setText(JSON.stringify(root.pinned, null, 2) + "\n")
    }

    /// The pinned apps, then the others that have a window, each with its windows
    readonly property var apps: {
        const windows = ToplevelManager.toplevels.values
        const of = id => windows.filter(w => w.appId === id)
        const list = root.pinned.map(id => ({ id: id, pinned: true, windows: of(id) }))
        for (const w of windows) {
            if (!w.appId || list.some(a => a.id === w.appId)) continue
            list.push({ id: w.appId, pinned: false, windows: of(w.appId) })
        }
        return list
    }

    /// The desktop file of an app. Reading the number of entries makes whoever asks ask again once
    /// the entries are read, which is after the shell has started
    readonly property int entries: DesktopEntries.applications.values.length
    function entry(id) { return root.entries >= 0 ? DesktopEntries.byId(id) || DesktopEntries.heuristicLookup(id) : null }

    function launch(id) {
        const e = root.entry(id)
        // In its own scope of the session, as apps started from Search are
        if (e) Quickshell.execDetached(["uwsm", "app", "--", e.id + ".desktop"])
    }

    /// Starts the app, or brings its window to the front: the next one when one of them has the focus
    function activate(app) {
        if (app.windows.length === 0) { root.launch(app.id); return }
        const at = app.windows.findIndex(w => w.activated)
        app.windows[(at + 1) % app.windows.length].activate()
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
        if (!root.player) { if (root.panel === "media") root.panel = "" }
        else if (root.player.isPlaying) root.lastPlayer = root.player
    }
    // MPRIS sends the position only on a seek: ask for it every second while the player is open
    Timer {
        interval: 1000
        repeat: true
        running: root.panel === "media" && !!root.player && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    // ---------------------------------------------------------------- one dock per screen
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            readonly property int dockHeight: 40
            readonly property bool here: root.screenName === modelData.name
            readonly property string open: here ? root.panel : ""
            /// What the panel shows; stays while it folds back
            property string showing: "media"
            onOpenChanged: if (open !== "") showing = open
            /// The icon the menu of an app grows out of
            property Item menuSource: null

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
            implicitWidth: Math.min(modelData.width, 960)
            implicitHeight: win.dockHeight + Theme.space2 + 240
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
            // its panel once it is out. The dock is its child, so its icons keep the hover.
            Item {
                id: edge
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: (win.out ? dock.openWidth : dock.restWidth) + 2 * Theme.space3
                height: win.out ? win.dockHeight + Theme.space2 : Theme.dockRest + 1
                HoverHandler { id: edgeHover }

                EdgeDock {
                    id: dock
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    openHeight: win.dockHeight
                    out: win.out

                    // By id, so an icon stays when a window of another app opens or closes
                    Repeater {
                        model: ScriptModel { values: root.apps.map(a => a.id) }
                        AppIcon {}
                    }

                    Item {
                        visible: !!root.player
                        width: Theme.space3 + 1
                        height: 16
                        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                        Rectangle { anchors.centerIn: parent; width: Theme.lineHair; height: parent.height; color: Theme.border }
                    }
                    MeterGroup {
                        id: mediaButton
                        visible: !!root.player
                        anchors.verticalCenter: parent.verticalCenter
                        gap: Theme.space2
                        onClicked: root.toggle("media", win.modelData.name)
                        Icon {
                            name: "music"
                            size: 14
                            hovered: mediaButton.hovered
                            color: win.open === "media" || (root.player && root.player.isPlaying) ? Theme.accentText
                                : mediaButton.hovered ? Theme.text : Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label {
                            textStyle: "micro"
                            color: mediaButton.hovered ? Theme.text : Theme.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 180)
                            text: !root.player ? "" : [root.player.trackTitle, root.player.trackArtist].filter(t => t).join("  ") || root.player.identity
                        }
                    }
                }
            }

            // One app of the dock
            component AppIcon: Item {
                id: app
                required property string modelData
                readonly property var its: root.apps.find(a => a.id === modelData) || ({ id: modelData, pinned: false, windows: [] })
                readonly property bool running: its.windows.length > 0
                readonly property bool focused: its.windows.some(w => w.activated)
                readonly property var entry: root.entry(modelData)
                readonly property string picture: Quickshell.iconPath(app.entry ? app.entry.icon : modelData, true)
                readonly property bool lit: hover.hovered || app.focused || (win.open === "app" && root.menuApp === modelData)

                // A pinned app that is not installed (the live session has few) takes no place
                visible: !!app.entry || app.running
                width: 36
                height: win.dockHeight
                // Pressing is quick, letting go a little slower
                scale: press.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: press.pressed ? Theme.durInstant : Theme.durFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }

                Rectangle {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    radius: Theme.radiusSm
                    color: hover.hovered ? Theme.surfaceRaised : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                }
                // The icon of the app: grey and a little dark until the pointer or the focus is on it
                IconImage {
                    visible: app.picture !== ""
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    implicitSize: 22
                    source: app.picture
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        saturation: app.lit ? 0 : -0.85
                        brightness: app.lit ? 0 : -0.12
                        Behavior on saturation { NumberAnimation { duration: Theme.durBase } }
                        Behavior on brightness { NumberAnimation { duration: Theme.durBase } }
                    }
                }
                // An app without an icon of its own
                Icon {
                    visible: app.picture === ""
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -1
                    name: "app-window"
                    size: 18
                    hovered: hover.hovered
                    color: app.lit ? Theme.text : Theme.textMuted
                }
                // Runs: a short mark; has the focus: a wider one in the accent
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 3
                    width: app.focused ? 12 : app.running ? 4 : 0
                    height: 2
                    radius: 1
                    color: app.focused ? Theme.accent : Theme.textMuted
                    Behavior on width { NumberAnimation { duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut } }
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                }

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: press
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onTapped: (point, button) => {
                        if (button === Qt.RightButton) {
                            win.menuSource = app
                            root.menuApp = app.modelData
                            root.screenName = win.modelData.name
                            root.panel = "app"
                        } else {
                            root.panel = ""
                            if (button === Qt.MiddleButton) root.launch(app.modelData)
                            else root.activate(app.its)
                        }
                    }
                }
            }

            // ------------------------------------------------------------ the panel
            Item {
                id: panelBox

                /// The symbol the panel grows out of
                readonly property Item source: win.showing === "app" && win.menuSource ? win.menuSource : mediaButton
                /// The middle of that symbol in the window, where it stands once the dock is out
                readonly property real sourceX: (win.width - dock.openWidth) / 2 + 6 + source.x + source.width / 2
                readonly property Item body: win.showing === "app" ? appMenu : mediaPanel

                visible: presence.present
                width: body.width
                height: body.height
                x: Math.round(Math.max(0, Math.min(win.width - width, sourceX - width / 2)))
                y: win.height - win.dockHeight - Theme.space2 - height
                opacity: presence.shown
                transform: Scale {
                    origin.x: panelBox.sourceX - panelBox.x
                    origin.y: panelBox.height + Theme.space2
                    xScale: 0.6 + 0.4 * presence.shown
                    yScale: 0.6 + 0.4 * presence.shown
                }
                HoverHandler { id: panelHover }

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

                // -------------------------------------------------------- the menu of an app
                QuickPanel {
                    id: appMenu
                    readonly property var app: root.apps.find(a => a.id === root.menuApp) || null
                    readonly property var entry: root.entry(root.menuApp)
                    visible: win.showing === "app"
                    width: 220
                    title: appMenu.entry ? appMenu.entry.name : root.menuApp

                    ListRow {
                        width: parent.width
                        visible: !!appMenu.entry
                        iconName: "plus"
                        text: "New window"
                        onClicked: { root.panel = ""; root.launch(root.menuApp) }
                    }
                    ListRow {
                        width: parent.width
                        iconName: "pin"
                        text: appMenu.app && appMenu.app.pinned ? "Unpin from the dock" : "Pin to the dock"
                        onClicked: { root.panel = ""; root.pin(root.menuApp) }
                    }
                    ListRow {
                        width: parent.width
                        visible: !!appMenu.app && appMenu.app.windows.length > 0
                        iconName: "x"
                        text: appMenu.app && appMenu.app.windows.length > 1 ? "Close all windows" : "Close"
                        onClicked: {
                            root.panel = ""
                            for (const w of appMenu.app.windows) w.close()
                        }
                    }
                }
            }
        }
    }
}
