// The theme picker (ThemePicker in StrixUI): the gods as slanted plates over the dimmed desktop,
// the chosen one in the middle with its caption; Keep stops the change every 10 minutes.
// The session's theme service (strix-theme session, Backend "theme") runs the cycle and the
// choice; Enter sets the machine's theme, which the boot splash follows too.
//
// Super Ctrl Space opens it (ipc: theme picker). Left and Right or the wheel browse, Enter or a
// click on the middle plate chooses, K keeps, Esc closes.
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

    /// The gods in the order of the design system, then the themes from theme repositories
    readonly property var themes: {
        const all = (root.state && root.state.themes) || []
        const gods = Theme.order.map(id => all.find(t => t.id === id)).filter(t => t)
        const outside = all.filter(t => Theme.order.indexOf(t.id) < 0)
        return gods.concat(outside)
    }
    readonly property var shown: root.themes[root.selected] || null

    function picture(t) {
        if (!t) return ""
        return Theme.gods[t.id] ? Theme.wallpaper(t.id) : "file://" + t.dir + "/wallpaper.jpg"
    }

    function caption(t) {
        if (!t) return ""
        if (Theme.gods[t.id]) return Theme.gods[t.id].plate
        if (Theme.external && Theme.external.id === t.id && Theme.external.plate) return Theme.external.plate
        return t.description
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

    function choose(id) {
        root.error = ""
        service.call("set", { theme: id }, s => {
            root.take(s)
            root.open = false
        })
    }

    function keep(on) {
        service.call("keep", { keep: on }, s => root.take(s))
    }

    function browse(step) {
        if (root.themes.length === 0) return
        root.browsed = true
        root.selected = (root.selected + step + root.themes.length) % root.themes.length
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
            console.warn("Strix theme: " + method + ": " + message)
        }
        onConnectedChanged: if (connected) root.refresh()
    }

    // The time to the next turn, between two answers of the service
    Timer {
        interval: 1000
        repeat: true
        running: root.state !== null
        onTriggered: {
            if (root.remaining > 0) root.remaining -= 1
            else root.refresh()
        }
    }

    IpcHandler {
        target: "theme"
        function picker(): void { if (root.open) root.open = false; else root.show() }
        function keep(): void { root.keep(!(root.state && root.state.keep)) }
        function set(id: string): void { root.choose(id) }
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
        visible: root.open
        WlrLayershell.namespace: "strix-theme-picker"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.background

        Wallpaper {
            anchors.fill: parent
            source: root.picture(root.shown)
            dim: true
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

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                textStyle: "micro"
                color: Theme.textFaint
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.2
                text: "Theme"
            }

            // The plates: the chosen one wide in the middle, its neighbours to each side
            Row {
                id: plates
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: -24
                height: 250
                Repeater {
                    model: root.themes
                    SlantCard {
                        required property var modelData
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        source: root.picture(modelData)
                        name: modelData.name
                        caption: modelData.description
                        accent: modelData.accent || Theme.accent
                        selected: index === root.selected
                        opacity: Math.abs(index - root.selected) > 3 ? 0.25 : 1
                        onClicked: {
                            if (index === root.selected) root.choose(modelData.id)
                            else { root.browsed = true; root.selected = index }
                        }
                    }
                }
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(parent.width - 2 * Theme.space6, 720)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textStyle: "aside"
                color: Theme.textMuted
                text: root.caption(root.shown)
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space5

                Segmented {
                    anchors.verticalCenter: parent.verticalCenter
                    model: (root.shown && root.shown.variants || ["dark"]).length > 1
                        ? root.shown.variants
                        : ["Dark", { text: "Light", enabled: false }]
                    currentIndex: 0
                }

                Switch {
                    id: keepSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Keep this theme"
                    checked: !!(root.state && root.state.keep)
                    onToggled: root.keep(checked)
                }
                KeyCaps { anchors.verticalCenter: parent.verticalCenter; keys: "K" }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    textStyle: "caption"
                    color: Theme.textFaint
                    text: root.state === null ? ""
                        : (root.state.keep ? "next turn in " : "next theme in ") + root.clock(root.remaining)
                }
            }

            Label {
                visible: root.error !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                textStyle: "caption"
                color: Theme.error
                text: root.error
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.space4
                Row { spacing: Theme.space1; KeyCaps { keys: "Left Right" } Label { textStyle: "caption"; color: Theme.textFaint; text: "browse" } }
                Row { spacing: Theme.space1; KeyCaps { keys: "Enter" } Label { textStyle: "caption"; color: Theme.textFaint; text: "choose" } }
                Row { spacing: Theme.space1; KeyCaps { keys: "Esc" } Label { textStyle: "caption"; color: Theme.textFaint; text: "close" } }
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

        Shortcut { sequence: "Left"; enabled: root.open; onActivated: root.browse(-1) }
        Shortcut { sequence: "Right"; enabled: root.open; onActivated: root.browse(1) }
        Shortcut { sequences: ["Return", "Enter"]; enabled: root.open; onActivated: if (root.shown) root.choose(root.shown.id) }
        Shortcut { sequence: "K"; enabled: root.open; onActivated: root.keep(!(root.state && root.state.keep)) }
        Shortcut { sequence: "Escape"; enabled: root.open; onActivated: root.open = false }
    }
}
