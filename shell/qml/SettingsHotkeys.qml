// Settings › Hotkeys: every key of Strix, filtered, and changed one by one: click a key, press the
// new combination (Esc stops, Backspace takes the key away). The search service keeps own keys in
// ~/.config/strix/keys.json and writes keys.lua for Hyprland, which reloads. A key that is taken
// is refused with what has it.
import QtQuick
import Quickshell
import Strix
import Strix.Shell

Column {
    id: page

    property bool active: false
    property var rows: []
    property string filter: ""
    /// The binding that waits for its new keys
    property string recording: ""
    property string error: ""

    spacing: Theme.space2

    function refresh() { search.call("hotkeys", {}, r => page.rows = (r || []).filter(h => !h.scope)) }
    onActiveChanged: if (active) refresh()

    function done(own) {
        page.recording = ""
        page.error = ""
        Quickshell.execDetached(["hyprctl", "reload"])
        page.refresh()
    }

    function setKeys(id, keys) {
        search.call("set_key", { id: id, keys: keys }, page.done)
    }

    /// The keys of a key press, as the cheat sheet writes them; "" for a lone modifier
    function keysOf(event) {
        const named = {
            [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Space]: "Space", [Qt.Key_Tab]: "Tab",
            [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
            [Qt.Key_Print]: "Print", [Qt.Key_Equal]: "=", [Qt.Key_Minus]: "-"
        }
        let key = named[event.key] || ""
        if (!key && event.key >= Qt.Key_A && event.key <= Qt.Key_Z) key = String.fromCharCode(event.key)
        if (!key && event.key >= Qt.Key_0 && event.key <= Qt.Key_9) key = String.fromCharCode(event.key)
        if (!key && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F12) key = "F" + (event.key - Qt.Key_F1 + 1)
        if (!key) return ""
        const mods = []
        if (event.modifiers & Qt.MetaModifier) mods.push("Super")
        if (event.modifiers & Qt.ShiftModifier) mods.push("Shift")
        if (event.modifiers & Qt.ControlModifier) mods.push("Ctrl")
        if (event.modifiers & Qt.AltModifier) mods.push("Alt")
        return mods.concat([key]).join(" ")
    }

    Backend {
        id: search
        service: "search"
        onFailed: (method, message) => page.error = message
    }

    Label { textStyle: "title"; color: Theme.text; text: "Hotkeys" }

    SearchField {
        width: parent.width
        onTextChanged: page.filter = text.toLowerCase()
    }

    Label {
        visible: page.error !== ""
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.error
        text: page.error
    }

    // Takes the key presses while a binding waits for new keys
    Item {
        id: catcher
        width: 1
        height: 1
        focus: page.recording !== ""
        Keys.onPressed: event => {
            event.accepted = true
            if (event.key === Qt.Key_Escape) { page.recording = ""; return }
            if (event.key === Qt.Key_Backspace) { page.setKeys(page.recording, ""); return }
            const keys = page.keysOf(event)
            if (keys !== "") page.setKeys(page.recording, keys)
        }
    }

    Repeater {
        model: page.rows.filter(h => page.filter === ""
            || (h.title + " " + h.target + " " + h.keys + " " + h.group).toLowerCase().indexOf(page.filter) >= 0)
        HotkeyRow {
            required property var modelData
            width: page.width
            action: modelData.title
            target: modelData.target || ""
            keys: page.recording === modelData.id ? "" : (modelData.keys || "off")
            recording: page.recording === modelData.id
            tail: modelData.changed ? "reset" : ""
            onRecord: {
                page.error = ""
                page.recording = modelData.id
                catcher.forceActiveFocus()
            }
            onReset: search.call("reset_key", { id: modelData.id }, page.done)
        }
    }

    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.textFaint
        text: "Click a key and press the new one; Esc stops, Backspace takes the key away. Keys that Hyprland already uses never reach this window: those are taken."
    }
}
