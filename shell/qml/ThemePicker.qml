// The theme picker (ThemePicker in StrixUI): the gods as slanted plates over the dimmed desktop,
// the chosen one in the middle with its name; Keep stops the change every 10 minutes.
// The session's theme service (strix-theme session, Backend "theme") runs the cycle and the
// choice; Enter sets the machine's theme, which the boot splash follows too.
//
// Super G opens it (ipc: theme picker). Left and Right or the wheel browse, Space (or
// Enter) or a click on the middle plate chooses, K keeps, Super L turns dark to light and
// back, Esc closes.
// It holds its pictures only while it is open, and the ones that are seen small or dimmed are
// decoded small: closed, the picker costs no memory worth naming.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Strix
import Strix.Shell

Scope {
    id: root

    property bool open: false
    /// The service's state: theme, keep, remaining, themes
    property var state: null
    property int selected: 0
    property string error: ""
    property int remaining: 0
    /// Browsed since it opened: a late answer of the service does not move the choice back
    property bool browsed: false
    /// Open, or still fading out: the wallpaper behind changes without its reveal meanwhile
    readonly property bool present: presence.present
    /// A theme is being applied: the reveal runs and the service has not answered yet
    property bool applying: false
    property bool answered: false

    /// The gods in the order of the design system, then the themes from theme repositories
    readonly property var themes: {
        const all = (root.state && root.state.themes) || []
        const gods = Theme.order.map(id => all.find(t => t.id === id)).filter(t => t)
        const outside = all.filter(t => Theme.order.indexOf(t.id) < 0)
        return gods.concat(outside)
    }
    readonly property var shown: root.themes[root.selected] || null

    /// The engraving of a theme, in the variant given or else the one that is on
    function picture(t, kind) {
        if (!t) return ""
        if (!Theme.gods[t.id]) return "file://" + t.dir + "/wallpaper.jpg"
        const file = Theme.gods[t.id].wallpaper
        return Theme.wallpapers + ((kind || Theme.variant) === "light" ? file.replace(".jpg", "-light.jpg") : file)
    }

    function take(s) {
        if (!s) return
        root.state = s
        root.remaining = s.remaining
    }

    function refresh() {
        service.call("state", {}, s => root.take(s))
    }

    function show() {
        root.error = ""
        root.applying = false
        reveal.clear()
        turn.clear()
        root.browsed = false
        const at = root.state ? root.themes.findIndex(t => t.id === root.state.theme) : -1
        root.selected = at < 0 ? 0 : at
        root.open = true
        service.call("state", {}, s => {
            root.take(s)
            if (root.browsed) return
            const now = root.themes.findIndex(t => t.id === s.theme)
            root.selected = now < 0 ? 0 : now
        })
    }

    /// Applies a theme: its engraving grows as a circle from `from` (the plate that was chosen),
    /// then the picker fades once the service has answered too (Theme apply in motion.md)
    function choose(id, from) {
        if (root.applying) return
        root.error = ""
        const t = root.themes.find(x => x.id === id)
        root.applying = true
        root.answered = false
        reveal.play(from || Qt.point(reveal.width / 2, reveal.height / 2), root.picture(t))
        service.call("set", { theme: id }, s => {
            root.take(s)
            root.answered = true
            root.done()
        })
    }

    function done() {
        if (!root.applying || !root.answered || reveal.busy) return
        root.applying = false
        root.open = false
    }

    /// Where the middle plate stands, for the reveal
    function middle() {
        const plate = plateRepeater.itemAt(root.selected)
        return plate ? plate.mapToItem(reveal, plate.width / 2, plate.height / 2) : null
    }

    /// Dark or light: the theme stays, its other variant comes, and every god after it in the
    /// same. With the picker open the other engraving grows as a circle from the middle plate
    /// over the one behind the plates, as a chosen theme does over the desktop
    function variant(kind) {
        const now = root.state ? root.state.variant : Theme.variant
        if (root.open && !root.applying && root.shown && kind !== now && (root.shown.variants || []).indexOf(kind) >= 0)
            turn.play(root.middle() || Qt.point(turn.width / 2, turn.height / 2), root.picture(root.shown, kind))
        service.call("variant", { variant: kind }, s => root.take(s))
    }

    function keep(on) {
        service.call("keep", { keep: on }, s => root.take(s))
    }

    function browse(step) {
        if (root.themes.length === 0) return
        root.browsed = true
        root.selected = Math.max(0, Math.min(root.themes.length - 1, root.selected + step))
    }

    function clock(seconds) {
        const m = Math.floor(seconds / 60)
        const s = seconds % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    Backend {
        id: service
        service: "theme"
        onEvent: (name, data) => { if (name === "changed") root.take(data) }
        onFailed: (method, message) => {
            root.error = message
            if (root.applying) {
                root.applying = false
                reveal.clear()
            }
            console.warn("Strix theme: " + method + ": " + message)
        }
        onConnectedChanged: if (connected) root.refresh()
    }

    // The time to the next turn, between two answers of the service. Only the open picker shows
    // it; show() asks the service again
    Timer {
        interval: 1000
        repeat: true
        running: root.open && root.state !== null
        onTriggered: {
            if (root.remaining > 0) root.remaining -= 1
            else root.refresh()
        }
    }

    IpcHandler {
        target: "theme"
        function picker(): void { if (root.open) root.open = false; else root.show() }
        function keep(): void { root.keep(!(root.state && root.state.keep)) }
        function variant(): void { root.variant(root.state && root.state.variant === "light" ? "dark" : "light") }
        // With the picker open the reveal starts from its middle plate, else from the screen's middle
        function set(id: string): void { root.choose(id, root.open ? root.middle() : null) }
        function next(): void { service.call("next", {}, s => root.take(s)) }
        function isOpen(): bool { return root.open }
        function current(): string { return root.state ? root.state.theme : "" }
        function kept(): bool { return !!(root.state && root.state.keep) }
        function shown(): string { return root.shown ? root.shown.id : "" }
        function ready(): bool { return root.open && keys.activeFocus && root.state !== null }
    }

    HyprlandFocusGrab {
        windows: [overlay]
        active: root.open
        onCleared: root.open = false
    }

    PanelWindow {
        id: overlay
        visible: presence.present
        WlrLayershell.namespace: "strix-theme-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        // Opens with a fade while the plates rise into place; after a theme is applied it fades
        // over the desktop, which already shows the new theme
        Presence {
            id: presence
            open: root.open
            leaveDuration: Theme.durBase
            // Gone from the screen, it lets go of every picture
            onPresentChanged: if (!present) {
                reveal.clear()
                turn.clear()
            }
        }

        Item {
            id: scene
            anchors.fill: parent
            opacity: presence.shown

            Rectangle { anchors.fill: parent; color: Theme.background }

            // The engraving of the plate in the middle. Browsing fades the next one over the
            // last, in the time the track takes to slide
            Item {
                id: backdrop
                anchors.fill: parent
                readonly property url wanted: presence.present ? root.picture(root.shown) : ""
                /// What it shows. It follows `wanted` once browsing rests: held keys turn the
                /// plates only, and the engraving behind comes with the plate they stop at
                property url target: wanted
                /// The upper layer shows the target, else the lower one
                property bool upper: false
                onWantedChanged: rest.restart()
                onTargetChanged: {
                    if (backdrop.target.toString() === "") {
                        lower.source = ""
                        over.source = ""
                        return
                    }
                    if (backdrop.upper) lower.source = backdrop.target
                    else over.source = backdrop.target
                    backdrop.upper = !backdrop.upper
                }
                Component.onCompleted: lower.source = backdrop.target
                Timer {
                    id: rest
                    interval: root.browsed ? Theme.durBase : 1
                    // Dark to light waits for its circle, which brings the picture itself
                    onTriggered: if (!turn.busy) backdrop.target = backdrop.wanted
                }

                // Dimmed and a little blurred, half the size of the file is all that is seen
                Wallpaper { id: lower; anchors.fill: parent; dim: true; sourceSize: Qt.size(0, 720) }
                Wallpaper {
                    id: over
                    anchors.fill: parent
                    dim: true
                    sourceSize: Qt.size(0, 720)
                    opacity: backdrop.upper ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durSlow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut } }
                }

                // Dark to light and back: the other engraving grows from the middle plate, as dim
                // as the one it covers. Grown, it stays until the layers below show the same
                CircleReveal {
                    id: turn
                    anchors.fill: parent
                    sourceSize: Qt.size(0, 720)
                    onFinished: {
                        backdrop.target = backdrop.wanted
                        settle.tries = 0
                        settle.restart()
                    }
                }
                Rectangle {
                    readonly property real r: turn.progress * turn.reach
                    visible: turn.progress > 0
                    x: turn.origin.x - r
                    y: turn.origin.y - r
                    width: 2 * r
                    height: 2 * r
                    radius: r
                    color: "black"
                    opacity: 1 - Theme.dimWallpaper
                }
                Timer {
                    id: settle
                    property int tries: 0
                    // The time the layers below take to fade to the new picture
                    interval: Theme.durSlow
                    onTriggered: {
                        // The service has not answered yet: the old variant is still below
                        if (backdrop.target.toString() !== turn.source.toString() && ++tries < 8) {
                            backdrop.target = backdrop.wanted
                            restart()
                        } else {
                            turn.clear()
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.open = false
                onWheel: wheel => root.browse(wheel.angleDelta.y < 0 || wheel.angleDelta.x < 0 ? 1 : -1)
            }

            Column {
                anchors.centerIn: parent
                spacing: Theme.space5
                width: parent.width
                transform: Translate { y: Theme.space3 * (1 - presence.shown) }

                // The carousel of StrixUI: the track slides so the chosen plate stays in the middle,
                // while it widens and its neighbours narrow (geometry of .k-carousel in bundle.css)
                Item {
                    width: parent.width
                    height: 300
                    clip: true

                    Row {
                        id: plates
                        // The slant of a card overlaps its neighbour and leaves a gap of 3
                        readonly property int overlap: 37
                        readonly property int gap: 3
                        readonly property int narrow: 96
                        readonly property int wide: 420
                        readonly property int step: narrow - overlap + gap
                        /// Where the carousel stands, in plates. One value moves the track and
                        /// widens the plates, and it keeps its speed when the choice moves on
                        /// before it has arrived: held keys turn it evenly instead of starting
                        /// the move again with every repeat
                        property real at: root.selected
                        Behavior on at {
                            enabled: root.open && !Theme.reducedMotion
                            SmoothedAnimation { duration: Theme.durBase; velocity: -1 }
                        }
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: gap - overlap
                        x: parent.width / 2 - (at * step + wide / 2)

                        Repeater {
                            id: plateRepeater
                            model: root.themes
                            SlantCard {
                                required property var modelData
                                required property int index
                                anchors.verticalCenter: parent.verticalCenter
                                source: presence.present ? root.picture(modelData) : ""
                                name: modelData.name
                                accent: modelData.accent || Theme.accent
                                selected: index === root.selected
                                lift: Math.max(0, 1 - Math.abs(index - plates.at))
                                onClicked: {
                                    if (index === root.selected) root.choose(modelData.id, root.middle())
                                    else { root.browsed = true; root.selected = index }
                                }
                            }
                        }
                    }
                }

                // What belongs to the choice stands on one plate under the carousel: dark or
                // light, keeping the theme, and the keys
                Surface {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - 2 * Theme.space6, 640)
                    height: foot.implicitHeight + 2 * Theme.space3
                    elevation: "panel"
                    // Dark or light and the switch stand one step and a half inside
                    inset: Theme.space3

                    // A click on the plate is not a click beside the picker
                    MouseArea { anchors.fill: parent }

                    Column {
                        id: foot
                        x: Theme.space3
                        y: Theme.space3
                        width: parent.width - 2 * Theme.space3
                        spacing: Theme.space3

                        Item {
                            width: parent.width
                            height: Theme.control

                            // Dark or light, for every theme that has both: the choice stays through the change of gods
                            Segmented {
                                id: variantSwitch
                                anchors.verticalCenter: parent.verticalCenter
                                readonly property var kinds: root.shown && root.shown.variants || ["dark"]
                                readonly property int now: Math.max(0, kinds.indexOf(root.state ? root.state.variant : "dark"))
                                model: kinds.length > 1
                                    ? kinds.map(v => v.charAt(0).toUpperCase() + v.slice(1))
                                    : ["Dark", { text: "Light", enabled: false }]
                                onNowChanged: currentIndex = now
                                Component.onCompleted: currentIndex = now
                                onActivated: index => { if (kinds.length > 1) root.variant(kinds[index]) }
                            }

                            // The switch and its key belong together
                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.space2
                                Switch {
                                    id: keepSwitch
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Keep this theme"
                                    checked: !!(root.state && root.state.keep)
                                    onToggled: root.keep(checked)
                                }
                                KeyCaps { anchors.verticalCenter: parent.verticalCenter; keys: "K" }
                            }

                            Label {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                textStyle: "caption"
                                color: Theme.textFaint
                                text: root.state === null ? ""
                                    : (root.state.keep ? "next turn in " : "next theme in ") + root.clock(root.remaining)
                            }
                        }

                        Label {
                            visible: root.error !== ""
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            textStyle: "caption"
                            color: Theme.error
                            text: root.error
                        }

                        Rectangle { width: parent.width; height: Theme.lineHair; color: Theme.border }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Theme.space4
                            Row { spacing: Theme.space2; KeyCaps { keys: "Left Right" } Label { height: Theme.mark; textStyle: "caption"; color: Theme.textFaint; text: "browse" } }
                            Row { spacing: Theme.space2; KeyCaps { keys: "Space" } Label { height: Theme.mark; textStyle: "caption"; color: Theme.textFaint; text: "choose" } }
                            Row { spacing: Theme.space2; KeyCaps { keys: "Super L" } Label { height: Theme.mark; textStyle: "caption"; color: Theme.textFaint; text: "light or dark" } }
                            Row { spacing: Theme.space2; KeyCaps { keys: "Esc" } Label { height: Theme.mark; textStyle: "caption"; color: Theme.textFaint; text: "close" } }
                        }
                    }
                }
            }

            // Takes the keyboard while the picker is open, for the shortcuts below
            Item {
                id: keys
                focus: true
                Timer {
                    interval: 150
                    repeat: true
                    running: root.open && !keys.activeFocus
                    onTriggered: keys.forceActiveFocus()
                }
            }

            Shortcut { sequence: "Left"; enabled: root.open && !root.applying; onActivated: root.browse(-1) }
            Shortcut { sequence: "Right"; enabled: root.open && !root.applying; onActivated: root.browse(1) }
            Shortcut { sequences: ["Space", "Return", "Enter"]; enabled: root.open && !root.applying; onActivated: if (root.shown) root.choose(root.shown.id, root.middle()) }
            Shortcut { sequence: "K"; enabled: root.open && !root.applying; onActivated: root.keep(!(root.state && root.state.keep)) }
            Shortcut { sequence: "Escape"; enabled: root.open && !root.applying; onActivated: root.open = false }

            // The chosen engraving, growing from its plate over everything
            CircleReveal {
                id: reveal
                anchors.fill: parent
                onFinished: root.done()
            }

            // Nothing to click while the theme is applied
            MouseArea { anchors.fill: parent; enabled: root.applying }
        }
    }
}
