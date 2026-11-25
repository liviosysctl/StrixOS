// Search (Search in StrixUI): one field for apps, actions, settings and commands, centred near the
// top over the dimmed desktop. The search service answers over its socket (Backend "search").
// An empty field is the system menu; Enter on a group opens it, Backspace on an empty field goes
// back up. Up and Down move, Enter starts, Esc clears and a second Esc closes.
// Below the rest, from three letters on, the Store's best packages that are not installed (the
// Store service, Backend "store"): Enter opens the Store at the package.
//
// When nothing is found, the one row left offers the web. Taking it grows the panel into the
// window of the browser: the field stays where the hand is and becomes the address, the tabs come
// in at its left and the page takes the place of the results. The browser (Zen) is asked for the
// page at the same moment; when the panel stands where a window stands and the browser has one,
// the panel gives way to it. As on main.
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
    /// The group shown, with the titles on the way there
    property var trail: []
    property var results: []
    /// The Store's packages for the text, shown after the other results
    property var packages: []
    readonly property var all: root.results.concat(root.packages)
    property int selected: 0

    /// Nothing found for what was typed: the web is offered
    readonly property bool web: input.text !== "" && root.all.length === 0
    /// The panel is on its way to being the browser window, and what was searched for
    property bool browsing: false
    property string page: ""
    /// From the search panel (0) to the browser window (1): every measure of the panel follows it
    property real grown: browsing ? 1 : 0
    Behavior on grown {
        enabled: root.open
        NumberAnimation { duration: Theme.durReveal; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeInOut }
    }
    function mix(from, to) { return from + (to - from) * root.grown }

    /// The browser has a window: one that was open already, or the one it opens now
    property bool arrived: false
    /// Asks the browser for what was typed, an address as it is and words as a search, while
    /// the panel grows to where its window stands
    function browse(text) {
        root.page = text
        root.arrived = ToplevelManager.toplevels.values.some(window => (window.appId || "").startsWith("zen"))
        root.browsing = true
        const address = /^([a-z][a-z0-9+.-]*:\/\/\S+|localhost(:\d+)?(\/\S*)?|[^\s\/]+\.[^\s\/]+(\/\S*)?)$/i.test(text.trim())
        Quickshell.execDetached(["uwsm", "app", "--", "zen-beta"].concat(address ? [text.trim()] : ["--search", text]))
    }
    // Arrived: the window of the browser takes the focus and the panel leaves. A browser that
    // had to start is waited for, but not for ever
    function hand() {
        if (!root.browsing || root.grown < 1 || !root.arrived) return
        Hyprland.dispatch("hl.dsp.focus({ window = \"class:^zen\" })")
        handover.restart()
    }
    onGrownChanged: {
        root.hand()
        if (root.grown === 1 && root.browsing && !root.arrived) patience.restart()
    }
    onArrivedChanged: root.hand()
    Timer { id: handover; interval: 400; onTriggered: if (root.browsing) root.open = false }
    Timer { id: patience; interval: 8000; onTriggered: if (root.browsing) root.open = false }
    Connections {
        target: Hyprland
        enabled: root.browsing
        function onRawEvent(event) {
            // openwindow: address, workspace, class, title
            if (event.name === "openwindow" && event.data.split(",")[2].startsWith("zen")) root.arrived = true
        }
    }

    function show(scope) {
        root.trail = scope ? [{ id: scope, title: "" }] : []
        root.open = true
        root.refresh("")
    }

    function refresh(text) {
        const scope = root.trail.length ? root.trail[root.trail.length - 1].id : null
        const params = scope ? { scope: scope } : {}
        if (text !== "") {
            params.text = text
            params.limit = 40
        }
        search.call(text !== "" ? "query" : "browse", params, r => {
            root.results = (r && r.results) || []
            root.selected = 0
        })
        root.packages = []
        if (!scope && text.trim().length >= 3) {
            const asked = text
            store.call("search", { text: text, limit: 3 }, r => {
                if (asked !== input.text) return
                root.packages = ((r && r.results) || []).filter(p => !p.installed).map(p => ({
                    id: "package:" + p.attr,
                    attr: p.attr,
                    kind: "package",
                    title: p.name || p.pname,
                    path: ["Store", p.unfree ? "Proprietary" : p.version],
                    icon: "package",
                    hits: []
                }))
            })
        }
    }

    /// Enter: the web when nothing was found, else the selected result
    function accept() {
        if (root.browsing) return
        if (root.web) root.browse(input.text)
        else root.activate(root.all[root.selected])
    }

    function activate(hit) {
        if (!hit) return
        if (hit.kind === "package") {
            root.open = false
            Quickshell.execDetached(["qs", "-c", "strix", "ipc", "call", "store", "find", hit.attr])
            return
        }
        search.call("activate", { id: hit.id }, r => {
            if (r && r.enter) {
                root.trail = root.trail.concat([{ id: hit.id, title: hit.title }])
                input.text = ""
                root.refresh("")
            } else {
                root.open = false
            }
        })
    }

    Backend {
        id: search
        service: "search"
        onFailed: (method, message) => console.warn("Strix search: " + method + ": " + message)
    }

    // Without the Store service (the live ISO) or before its index is there, no packages
    Backend {
        id: store
        service: "store"
    }

    IpcHandler {
        target: "search"
        function toggle(): void { if (root.open) root.open = false; else root.show(null) }
        function open(scope: string): void { root.show(scope) }
        function apps(): void { root.show("menu:apps") }
        function text(): string { return input.text }
        function isOpen(): bool { return root.open }
        function ready(): bool { return root.open && input.field.activeFocus }
    }

    // Opened again, it is the search
    onOpenChanged: if (!open) { input.text = ""; root.trail = []; root.browsing = false }

    HyprlandFocusGrab {
        windows: [overlay]
        active: root.open
        onCleared: root.open = false
    }

    PanelWindow {
        id: overlay
        visible: root.open
        WlrLayershell.namespace: "strix-search"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        // The browser is a window among the others: the desktop comes back to full light
        color: Theme.alpha(Theme.scrim, Theme.scrim.a * (1 - root.grown))

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Surface {
            id: panel
            elevation: "panel"
            // The search: 640 wide, near the top. The browser: where a tiled window stands, a
            // gap of two steps from the bar and the edges of the screen
            readonly property int gap: 2 * Theme.space1
            /// The strip of the browser's tabs and the height of its rows
            readonly property int side: 264
            readonly property int row: Theme.control + Theme.space2 - Theme.lineBold
            x: root.mix((parent.width - 640) / 2, gap)
            y: root.mix(parent.height * 0.14, Theme.barHeight + gap)
            width: root.mix(640, parent.width - 2 * gap)
            height: root.mix(column.implicitHeight + 2 * Theme.space2, parent.height - Theme.barHeight - 2 * gap)

            MouseArea { anchors.fill: parent }

            // The tabs, down the left side: they open like a drawer while the panel grows
            Item {
                x: Theme.space2
                y: Theme.space2
                width: panel.side * root.grown
                height: parent.height - 2 * Theme.space2
                visible: root.grown > 0
                opacity: root.grown
                clip: true

                Column {
                    width: panel.side
                    spacing: Theme.lineBold
                    Rule { width: parent.width; height: Theme.space4 }
                    ListRow { width: parent.width; height: panel.row; iconName: "plus"; text: "New tab"; detail: "Ctrl T" }
                    ListRow {
                        width: parent.width
                        height: panel.row
                        iconName: "search"
                        text: root.page
                        selected: true
                    }
                }
            }

            Column {
                id: column
                x: Theme.space2 + (panel.side + Theme.space2) * root.grown
                y: Theme.space2
                width: parent.width - x - Theme.space2
                spacing: Theme.space2

                Row {
                    spacing: Theme.space2
                    width: parent.width
                    // The strip, back, forward and again come out in front of the field, as Zen has them
                    Row {
                        visible: root.grown > 0
                        opacity: root.grown
                        width: implicitWidth * root.grown
                        clip: true
                        spacing: Theme.space1
                        IconButton { iconName: "app-window" }
                        IconButton { iconName: "chevron-left" }
                        IconButton { iconName: "chevron-right" }
                        IconButton { iconName: "rotate-cw" }
                    }
                    Label {
                        visible: root.trail.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        textStyle: "aside"
                        color: Theme.accentText
                        text: root.trail.map(t => t.title).filter(t => t).join(" › ")
                    }
                    SearchField {
                        id: input
                        width: parent.width - x
                        KeyCaps { keys: "Esc" }
                        onTextChanged: root.refresh(text)
                        onAccepted: root.accept()
                        Timer {
                            interval: 100
                            repeat: true
                            running: root.open && !input.field.activeFocus
                            onTriggered: input.field.forceActiveFocus()
                        }
                    }
                }

                // Nothing found: the web, in the browser this panel grows into
                ListRow {
                    visible: root.web && root.grown < 1
                    opacity: 1 - root.grown
                    width: parent.width
                    selected: true
                    iconName: "search"
                    text: "Search the web for \u201c" + input.text + "\u201d"
                    detail: "Enter opens the browser"
                    onClicked: root.accept()
                }

                ListView {
                    id: list
                    visible: root.grown < 1
                    opacity: 1 - root.grown
                    width: parent.width
                    height: Math.min(contentHeight, 9 * (Theme.control + Theme.space3))
                    clip: true
                    model: root.all
                    currentIndex: root.selected
                    delegate: SearchHit {
                        required property var modelData
                        required property int index
                        width: list.width
                        text: modelData.title
                        hits: modelData.hits || []
                        path: modelData.path || []
                        kind: modelData.kind
                        iconName: modelData.icon || "circle"
                        keys: modelData.keys || modelData.value || ""
                        enterText: modelData.enter ? "›" : ""
                        selected: index === root.selected
                        onClicked: root.activate(modelData)
                    }
                }
            }

            // The page takes the place of the results, under the address: what was searched for
            // stands there until the window of the browser shows the page itself
            Rectangle {
                x: column.x
                y: Theme.space2 + panel.row + Theme.space2
                width: column.width
                height: parent.height - y - Theme.space2
                visible: root.grown > 0
                opacity: root.grown
                radius: Theme.radiusMd
                // A well in the glass of the window
                color: Theme.alpha(Theme.text, 0.04)
                clip: true

                Column {
                    anchors.centerIn: parent
                    spacing: Theme.space2
                    Label { anchors.horizontalCenter: parent.horizontalCenter; textStyle: "title"; color: Theme.text; text: root.page }
                }
            }
        }

        Shortcut { sequence: "Down"; enabled: root.open && !root.browsing; onActivated: root.selected = Math.min(root.selected + 1, root.all.length - 1) }
        Shortcut { sequence: "Up"; enabled: root.open && !root.browsing; onActivated: root.selected = Math.max(root.selected - 1, 0) }
        Shortcut {
            sequence: "Escape"
            enabled: root.open
            onActivated: {
                // On the way to the browser there is no way back: it is already loading
                if (root.browsing) return
                if (input.text !== "") input.text = ""
                else root.open = false
            }
        }
        Shortcut {
            sequence: "Backspace"
            enabled: root.open && !root.browsing && input.text === "" && root.trail.length > 0
            onActivated: {
                root.trail = root.trail.slice(0, -1)
                root.refresh("")
            }
        }
    }
}
