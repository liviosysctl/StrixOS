// Search (Search in StrixUI): one field for apps, actions, settings and commands, centred near the
// top over the dimmed desktop. The search service answers over its socket (Backend "search").
// An empty field is the system menu; Enter on a group opens it, Backspace on an empty field goes
// back up. Up and Down move, Enter starts, Esc clears and a second Esc closes.
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
        if (root.answer && root.selected === -1) {
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
    Presence { id: presence; open: root.open }

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
        color: Theme.alpha(Theme.scrim, Theme.scrim.a * presence.shown)

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Surface {
            id: panel
            elevation: "panel"
            opacity: presence.shown
            scale: 0.97 + 0.03 * presence.shown
            transformOrigin: Item.Top
            transform: Translate { y: -Theme.space2 * (1 - presence.shown) }
            width: 640
            height: column.implicitHeight + 2 * Theme.space2
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.14 }

            MouseArea { anchors.fill: parent }

            Column {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space2 }
                spacing: Theme.space2

                Row {
                    spacing: Theme.space2
                    width: parent.width
                    Label {
                        visible: root.trail.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        textStyle: "aside"
                        color: Theme.accentText
                        text: root.trail.map(t => t.title).filter(t => t).join(" › ")
                    }
                    SearchField {
                        id: input
                        width: parent.width - (root.trail.length ? x : 0)
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
                    visible: root.answer !== null
                    width: parent.width
                    selected: root.selected === -1
                    iconName: "corner-down-left"
                    text: root.answer ? root.answer.value : ""
                    detail: "Enter copies"
                    onClicked: { root.selected = -1; root.accept() }
                }

                ListView {
                    id: list
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
        }

        Shortcut { sequence: "Down"; enabled: root.open; onActivated: root.selected = Math.min(root.selected + 1, root.results.length - 1) }
        Shortcut { sequence: "Up"; enabled: root.open; onActivated: root.selected = Math.max(root.selected - 1, root.answer ? -1 : 0) }
        Shortcut {
            sequence: "Escape"
            enabled: root.open
            onActivated: {
                if (input.text !== "") input.text = ""
                else root.open = false
            }
        }
        Shortcut {
            sequence: "Backspace"
            enabled: root.open && input.text === "" && root.trail.length > 0
            onActivated: {
                root.trail = root.trail.slice(0, -1)
                root.direction = -1
                root.refresh("")
            }
        }
    }
}
