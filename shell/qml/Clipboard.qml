// The clipboard history (Super V): what was copied, newest first, from cliphist. Type to filter,
// Up and Down choose, Enter copies it again, Delete forgets it, Esc closes.
// The user service strix-clipboard keeps the history (wl-paste --watch cliphist store).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Strix

Scope {
    id: root

    property bool open: false
    /// Lines of `cliphist list`: id, a tab, a preview
    property var entries: []
    property int selected: 0
    property string filter: ""
    readonly property var shown: root.entries.filter(e => root.filter === ""
        || e.text.toLowerCase().indexOf(root.filter) >= 0)

    function show() {
        root.filter = ""
        root.selected = 0
        root.open = true
        list.running = true
    }

    function pick(entry) {
        if (!entry) return
        // cliphist decode wants the whole line, copy it back exactly as it was
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist decode | wl-copy", "sh", entry.line])
        root.open = false
    }

    function forget(entry) {
        if (!entry) return
        if (entry.picture !== "") Quickshell.execDetached(["rm", "-f", entry.picture.slice(7)])
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | cliphist delete", "sh", entry.line])
        root.entries = root.entries.filter(e => e.line !== entry.line)
    }

    /// Where the pictures of the history are unpacked for their previews, gone with the session
    readonly property string pictures: Quickshell.env("XDG_RUNTIME_DIR") + "/strix/clipboard"

    // cliphist shows a picture as "[[ binary data 12 KiB png 640x480 ]]": the newest 40 are
    // unpacked once, by their id, so the rows can show them. The folder is in memory (a tmpfs):
    // a picture that is no longer among them goes
    Process {
        id: list
        command: ["sh", "-c", `mkdir -p "$1" && cliphist list | { n=0; keep=" "; t=$(printf '\\t'); while IFS= read -r line; do
            id=\${line%%"$t"*}
            case "$line" in *"$t[[ binary data "*)
                n=$((n + 1))
                if [ "$n" -le 40 ]; then
                    keep="$keep$id "
                    [ -s "$1/$id" ] || printf '%s' "$line" | cliphist decode >"$1/$id"
                fi ;;
            esac
            printf '%s\\n' "$line"
        done
        for f in "$1"/*; do case "$keep" in *" \${f##*/} "*) ;; *) rm -f "$f" ;; esac; done; }`, "sh", root.pictures]
        stdout: StdioCollector {
            onStreamFinished: {
                root.entries = text.split("\n").filter(l => l.indexOf("\t") > 0).map(l => {
                    const id = l.slice(0, l.indexOf("\t"))
                    const body = l.slice(l.indexOf("\t") + 1)
                    const picture = /^\[\[ binary data .*?(\d+x\d+) \]\]$/.exec(body)
                    return {
                        line: l,
                        text: picture ? "Picture, " + picture[1].replace("x", " x ") : body,
                        picture: picture ? "file://" + root.pictures + "/" + id : ""
                    }
                })
            }
        }
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { if (root.open) root.open = false; else root.show() }
        function clear(): void {
            Quickshell.execDetached(["cliphist", "wipe"])
            Quickshell.execDetached(["rm", "-rf", root.pictures])
            root.entries = []
        }
        function isOpen(): bool { return root.open }
        function count(): int { return root.entries.length }
    }

    Presence { id: presence; open: root.open }

    HyprlandFocusGrab {
        windows: [overlay]
        active: root.open
        onCleared: root.open = false
    }

    PanelWindow {
        id: overlay
        visible: presence.present
        WlrLayershell.namespace: "strix-clipboard"
        WlrLayershell.layer: WlrLayer.Overlay
        // Hyprland gives a layer the keyboard through a focus grab; a click outside ends it
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.alpha(Theme.scrim, Theme.scrim.a * presence.shown)

        MouseArea { anchors.fill: parent; onClicked: root.open = false }

        Surface {
            elevation: "panel"
            // The field and the rows stand one step inside: corners parallel to theirs
            inset: Theme.space2
            // Opening: drops 8px into place from 97% while the scrim fades (motion.md)
            opacity: presence.shown
            scale: 0.97 + 0.03 * presence.shown
            transformOrigin: Item.Top
            transform: Translate { y: -Theme.space2 * (1 - presence.shown) }
            width: 560
            height: column.implicitHeight + 2 * Theme.space2
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: parent.height * 0.14 }

            MouseArea { anchors.fill: parent }

            Column {
                id: column
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space2 }
                spacing: Theme.space2

                SearchField {
                    id: input
                    width: parent.width
                    placeholderText: "Clipboard"
                    KeyCaps { keys: "Esc" }
                    onTextChanged: { root.filter = text.toLowerCase(); root.selected = 0 }
                    onAccepted: root.pick(root.shown[root.selected])
                    Timer {
                        interval: 100
                        repeat: true
                        running: root.open && !input.field.activeFocus
                        onTriggered: input.field.forceActiveFocus()
                    }
                }

                Label {
                    visible: root.shown.length === 0
                    x: Theme.space2
                    height: Theme.control
                    textStyle: "body"
                    color: Theme.textFaint
                    text: root.entries.length === 0 ? "Nothing copied yet" : "Nothing matches"
                }

                ListView {
                    id: rows
                    width: parent.width
                    height: Math.min(contentHeight, 10 * Theme.control)
                    clip: true
                    // Closed, the rows and their pictures go; the entries stay for the next time
                    model: presence.present ? root.shown : []
                    currentIndex: root.selected
                    delegate: ListRow {
                        required property var modelData
                        required property int index
                        width: rows.width
                        text: modelData.text.replace(/\s+/g, " ")
                        iconName: modelData.picture !== "" ? "image" : "copy"
                        selected: index === root.selected
                        onClicked: root.pick(modelData)
                        // A picture gets a taller row with itself at the right
                        implicitHeight: modelData.picture !== "" ? 2 * Theme.control + Theme.space2 : Theme.control
                        Image {
                            visible: modelData.picture !== ""
                            source: modelData.picture
                            anchors { right: parent.right; rightMargin: Theme.space2; verticalCenter: parent.verticalCenter }
                            height: 2 * Theme.control
                            width: 6 * Theme.control
                            sourceSize.height: 120
                            fillMode: Image.PreserveAspectFit
                            horizontalAlignment: Image.AlignRight
                            asynchronous: true
                        }
                    }
                }

                Row {
                    x: Theme.space2
                    spacing: Theme.space4
                    Row { spacing: Theme.space2; KeyCaps { keys: "Enter" } Label { height: Theme.mark; textStyle: "caption"; color: Theme.textFaint; text: "copy" } }
                    Row { spacing: Theme.space2; KeyCaps { keys: "Delete" } Label { height: Theme.mark; textStyle: "caption"; color: Theme.textFaint; text: "forget" } }
                }
            }
        }

        Shortcut { sequence: "Down"; enabled: root.open; onActivated: root.selected = Math.min(root.selected + 1, root.shown.length - 1) }
        Shortcut { sequence: "Up"; enabled: root.open; onActivated: root.selected = Math.max(root.selected - 1, 0) }
        Shortcut { sequence: "Delete"; enabled: root.open; onActivated: root.forget(root.shown[root.selected]) }
        Shortcut {
            sequence: "Escape"
            enabled: root.open
            onActivated: {
                if (input.text !== "") input.text = ""
                else root.open = false
            }
        }
    }
}
