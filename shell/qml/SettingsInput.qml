// Settings › Input: the layouts of the keyboard, the mouse and the touchpad. The choices are
// written to ~/.config/strix/input.lua (read by the Hyprland configuration of Strix) and Hyprland
// reloads; input.json beside it keeps them for this page. What is not chosen here stays as the
// machine has it (machine.nix for the layout).
import QtQuick
import Quickshell
import Quickshell.Io
import Strix

Column {
    id: page

    spacing: Theme.space2

    readonly property string dir: Quickshell.env("HOME") + "/.config/strix"
    readonly property var speeds: [-0.6, -0.3, 0, 0.3, 0.6]
    /// layouts ("ch,us"), speed, flat, mouseNatural, tap, touchpadNatural, whileTyping
    property var chosen: ({})
    function value(key, fallback) { return page.chosen[key] === undefined ? fallback : page.chosen[key] }

    FileView {
        id: stored
        path: page.dir + "/input.json"
        printErrors: false
        onLoaded: { try { page.chosen = JSON.parse(text()) } catch (e) { page.chosen = {} } }
    }
    FileView { id: lua; path: page.dir + "/input.lua"; printErrors: false }

    function set(key, value) {
        const next = Object.assign({}, page.chosen)
        next[key] = value
        page.chosen = next
        // One call for each choice: a name this Hyprland does not know leaves the others alone
        const lines = ["-- Written by Settings › Input; change it there."]
        const put = body => lines.push("pcall(hl.config, { input = { " + body + " } })")
        if (next.layouts) {
            put("kb_layout = " + JSON.stringify(next.layouts) + ", kb_variant = \"\"")
            if (next.layouts.indexOf(",") > 0) put("kb_options = \"grp:alt_shift_toggle\"")
        }
        if (next.speed !== undefined) put("sensitivity = " + next.speed)
        if (next.flat !== undefined) put("accel_profile = " + JSON.stringify(next.flat ? "flat" : "adaptive"))
        if (next.mouseNatural !== undefined) put("natural_scroll = " + next.mouseNatural)
        if (next.touchpadNatural !== undefined) put("touchpad = { natural_scroll = " + next.touchpadNatural + " }")
        if (next.whileTyping !== undefined) put("touchpad = { disable_while_typing = " + next.whileTyping + " }")
        if (next.tap !== undefined) {
            put("touchpad = { [\"tap-to-click\"] = " + next.tap + " }")
            put("touchpad = { tap_to_click = " + next.tap + " }")
        }
        Quickshell.execDetached(["mkdir", "-p", page.dir])
        stored.setText(JSON.stringify(next, null, 2) + "\n")
        lua.setText(lines.join("\n") + "\n")
        reload.restart()
    }

    // After the files are written
    Timer { id: reload; interval: 300; onTriggered: Quickshell.execDetached(["hyprctl", "reload"]) }

    Label { textStyle: "title"; color: Theme.text; text: "Input" }

    Label { textStyle: "heading"; color: Theme.text; text: "Keyboard" }
    SettingRow {
        width: page.width
        title: "Layouts"
        text: "As xkb names with commas, the first is the one at the start: ch, us, de. Alt Shift switches."
        TextField {
            id: layouts
            width: 180
            placeholderText: "as installed"
            text: page.value("layouts", "")
            onAccepted: page.set("layouts", text.replace(/\s+/g, "").toLowerCase())
        }
    }

    Label { textStyle: "heading"; color: Theme.text; text: "Mouse and touchpad"; topPadding: Theme.space3 }
    SettingRow {
        width: page.width
        title: "Pointer speed"
        Segmented {
            model: ["Slowest", "Slow", "Normal", "Fast", "Fastest"]
            currentIndex: Math.max(0, page.speeds.indexOf(page.value("speed", 0)))
            onActivated: index => page.set("speed", page.speeds[index])
        }
    }
    SettingRow {
        width: page.width
        title: "Acceleration"
        text: "Off moves the pointer exactly as far as the hand, at any speed"
        Switch { checked: !page.value("flat", false); onToggled: page.set("flat", !checked) }
    }
    SettingRow {
        width: page.width
        title: "Natural scrolling with the mouse"
        text: "The page follows the wheel"
        Switch { checked: page.value("mouseNatural", false); onToggled: page.set("mouseNatural", checked) }
    }
    SettingRow {
        width: page.width
        title: "Tap to click"
        Switch { checked: page.value("tap", true); onToggled: page.set("tap", checked) }
    }
    SettingRow {
        width: page.width
        title: "Natural scrolling on the touchpad"
        text: "The page follows the fingers"
        Switch { checked: page.value("touchpadNatural", true); onToggled: page.set("touchpadNatural", checked) }
    }
    SettingRow {
        width: page.width
        title: "Touchpad off while typing"
        Switch { checked: page.value("whileTyping", true); onToggled: page.set("whileTyping", checked) }
    }
}
