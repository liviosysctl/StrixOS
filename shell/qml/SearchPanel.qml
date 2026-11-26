// Search (Search in StrixUI): one field for apps, actions, settings and commands, centred near the
// top over the dimmed desktop. The search service answers over its socket (Backend "search").
// An empty field is the system menu; Enter on a group opens it, Backspace on an empty field goes
// back up. Up and Down move, Enter starts, Esc clears and a second Esc closes.
//
// When nothing is found, the one row left offers the web. Taking it grows the panel into the
// window of the browser: the field stays where the hand is and becomes the address, the tabs come
// in at its left and the page takes the place of the results. The browser (Zen) is asked for the
// page at the same moment; when the panel stands where a window stands and the browser has one,
// the panel gives way to it.
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
    /// A calculation typed into the field and what it comes to ({ text, value }), else null. It
    /// stands above the results and is what Enter takes (selected is -1) until Down leaves it
    property var answer: null
    property int selected: 0

    /// 1 when the last move went into a group, -1 back out: the list slides in from that side
    property int direction: 0

    /// Nothing found for what was typed: the web is offered
    readonly property bool web: input.text !== "" && root.results.length === 0 && root.answer === null
    /// The panel is on its way to being the browser window, and what was searched for
    property bool browsing: false
    property string page: ""
    /// From the search panel (0) to the browser window (1): every measure of the panel follows it
    property real grown: browsing ? 1 : 0
    Behavior on grown {
        enabled: presence.present
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
        root.direction = 0
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
            root.answer = (r && r.answer) || null
            root.selected = root.answer ? -1 : 0
            if (root.direction !== 0) slide.restart()
        })
    }

    /// Enter: the answer of a calculation goes to the clipboard, a result is run
    function accept() {
        if (root.browsing) {
            return
        } else if (root.web) {
            root.browse(input.text)
        } else if (root.answer && root.selected === -1) {
            // fend marks a rounded value; the number is what is wanted in the clipboard
            Quickshell.execDetached(["wl-copy", root.answer.value.replace(/^approx\. /, "")])
            root.open = false
        } else {
            root.activate(root.results[root.selected])
        }
    }

    function activate(hit) {
        if (!hit) return
        search.call("activate", { id: hit.id }, r => {
            if (r && r.enter) {
                root.trail = root.trail.concat([{ id: hit.id, title: hit.title }])
                root.direction = 1
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

    IpcHandler {
        target: "search"
        function toggle(): void { if (root.open) root.open = false; else root.show(null) }
        function open(scope: string): void { root.show(scope) }
        function apps(): void { root.show("menu:apps") }
        function text(): string { return input.text }
        function isOpen(): bool { return root.open }
        function ready(): bool { return root.open && input.field.activeFocus }
    }

    onOpenChanged: if (!open) { input.text = ""; root.trail = [] }

    // Opening and closing: the panel drops 8px into place from 97% while the scrim fades
    Presence {
        id: presence
        open: root.open
        // Opened again, it is the search
        onPresentChanged: if (!present) root.browsing = false
    }

    HyprlandFocusGrab {
        windows: [overlay]
        active: root.open
        onCleared: root.open = false
    }

    PanelWindow {
        id: overlay
        visible: presence.present
        WlrLayershell.namespace: "strix-search"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        // The browser is a window among the others: the desktop comes back to full light
        color: Theme.alpha(Theme.scrim, Theme.scrim.a * presence.shown * (1 - root.grown))

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Surface {
            id: panel
            elevation: "panel"
            // The field and the rows stand one step inside; grown into the browser it has the
            // corners of a window
            inset: Theme.space2 * (1 - root.grown)
            opacity: presence.shown
            scale: 0.97 + 0.03 * presence.shown
            transformOrigin: Item.Top
            transform: Translate { y: -Theme.space2 * (1 - presence.shown) }
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
                        id: steps
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

                // The answer to a calculation; Enter copies it
                ListRow {
                    visible: root.answer !== null && root.grown < 1
                    opacity: 1 - root.grown
                    width: parent.width
                    selected: root.selected === -1
                    iconName: "corner-down-left"
                    text: root.answer ? root.answer.value : ""
                    detail: "Enter copies"
                    onClicked: { root.selected = -1; root.accept() }
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
                    height: Math.min(contentHeight, 40 * 9)
                    clip: true
                    model: root.results
                    currentIndex: root.selected
                    // The selection glides from hit to hit
                    highlight: Glide {}
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: Theme.durBase
                    highlightMoveVelocity: -1
                    highlightResizeDuration: 0
                    transform: Translate { id: sideways }
                    // New results come in one after the other
                    populate: Transition {
                        id: cascade
                        SequentialAnimation {
                            PropertyAction { property: "opacity"; value: 0 }
                            PauseAnimation { duration: Math.min(cascade.ViewTransition.index, 8) * Theme.stagger + 1 }
                            NumberAnimation { property: "opacity"; to: 1; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                        }
                    }
                    // Into a group the list comes from the right, back out from the left
                    ParallelAnimation {
                        id: slide
                        NumberAnimation { target: sideways; property: "x"; from: root.direction * 12; to: 0; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                        NumberAnimation { target: list; property: "opacity"; from: 0; to: 1; duration: Theme.durBase; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.easeOut }
                    }
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
                        glide: true
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

        Shortcut { sequence: "Down"; enabled: root.open && !root.browsing; onActivated: root.selected = Math.min(root.selected + 1, root.results.length - 1) }
        Shortcut { sequence: "Up"; enabled: root.open && !root.browsing; onActivated: root.selected = Math.max(root.selected - 1, root.answer ? -1 : 0) }
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
                root.direction = -1
                root.refresh("")
            }
        }
    }
}
