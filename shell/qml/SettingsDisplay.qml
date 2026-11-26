// Settings › Display: every screen with its scale, its resolution and refresh rate, adaptive sync,
// where it stands beside the others, whether it mirrors another one or is off, and the night
// light.
// The choices are written to ~/.config/strix/monitors.lua (one hl.monitor per screen, read by the
// Hyprland configuration of Strix) and Hyprland reloads; monitors.json beside it keeps them for
// this page, which is also how a screen that is off stays in the list.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Strix

Column {
    id: page

    spacing: Theme.space2

    readonly property string dir: Quickshell.env("HOME") + "/.config/strix"
    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]
    readonly property var places: ["auto", "auto-left", "auto-right", "auto-up", "auto-down"]
    /// Screen name to what was chosen: scale, size ("1920x1080"), rate, place, mirror, off
    property var chosen: ({})

    /// The screens Hyprland shows, then the ones that are off here
    readonly property var screens: {
        const on = Hyprland.monitors.values.map(m => ({
            name: m.name,
            title: m.description || m.name,
            width: m.width,
            height: m.height,
            scale: m.scale,
            modes: (m.lastIpcObject && m.lastIpcObject.availableModes) || [],
            rate: m.lastIpcObject ? m.lastIpcObject.refreshRate : 0
        }))
        const off = Object.keys(page.chosen)
            .filter(name => page.chosen[name].off && !on.some(m => m.name === name))
            .map(name => ({ name: name, title: name, width: 0, height: 0, scale: 1, modes: [], rate: 0 }))
        return on.concat(off)
    }

    FileView {
        id: stored
        path: page.dir + "/monitors.json"
        printErrors: false
        onLoaded: {
            try {
                const read = JSON.parse(text())
                // Until 0.6 the file held only the scale of each screen
                for (const name in read) if (typeof read[name] === "number") read[name] = { scale: read[name] }
                page.chosen = read
            } catch (e) {
                page.chosen = {}
            }
        }
    }
    FileView { id: lua; path: page.dir + "/monitors.lua"; printErrors: false }
    Component.onCompleted: Hyprland.refreshMonitors()

    /// "1920x1080@60.00Hz" as its parts
    function mode(text) {
        const m = /^(\d+x\d+)@([\d.]+)Hz$/.exec(text)
        return m ? { size: m[1], rate: Number(m[2]) } : null
    }
    /// The four largest sizes a screen offers
    function sizes(screen) {
        const all = []
        for (const text of screen.modes) {
            const m = page.mode(text)
            if (m && all.indexOf(m.size) < 0) all.push(m.size)
        }
        const area = s => s.split("x").reduce((a, b) => a * b, 1)
        return all.sort((a, b) => area(b) - area(a)).slice(0, 4)
    }
    /// The rates a screen offers at a size, highest first
    function rates(screen, size) {
        const all = []
        for (const text of screen.modes) {
            const m = page.mode(text)
            if (m && m.size === size && !all.some(r => Math.round(r) === Math.round(m.rate))) all.push(m.rate)
        }
        return all.sort((a, b) => b - a).slice(0, 5)
    }
    function sizeOf(screen) { return (page.chosen[screen.name] || {}).size || screen.width + "x" + screen.height }

    function set(name, key, value) {
        const next = JSON.parse(JSON.stringify(page.chosen))
        next[name] = next[name] || {}
        next[name][key] = value
        page.chosen = next
        // One protected call for each screen: a mistake in one leaves the others as they are
        const lines = ["-- Written by Settings › Display; change it there."]
        for (const output in next) {
            const c = next[output]
            if (c.off) {
                lines.push("pcall(hl.monitor, { output = " + JSON.stringify(output) + ", disabled = true })")
                continue
            }
            const parts = [
                "output = " + JSON.stringify(output),
                "mode = " + JSON.stringify(c.size ? c.size + (c.rate ? "@" + c.rate : "") : "preferred"),
                "position = " + JSON.stringify(c.place || "auto"),
                // Not chosen: the scale it has now, which may be the one Strix gives a laptop
                "scale = " + (c.scale || (page.screens.find(m => m.name === output) || {}).scale || JSON.stringify("auto"))
            ]
            if (c.mirror) parts.push("mirror = " + JSON.stringify(c.mirror))
            if (c.vrr !== undefined) parts.push("vrr = " + c.vrr)
            lines.push("pcall(hl.monitor, { " + parts.join(", ") + " })")
        }
        Quickshell.execDetached(["mkdir", "-p", page.dir])
        stored.setText(JSON.stringify(next, null, 2) + "\n")
        lua.setText(lines.join("\n") + "\n")
        reload.restart()
    }

    // After the files are written; then the list of screens and their modes is read again
    Timer {
        id: reload
        interval: 300
        onTriggered: {
            Quickshell.execDetached(["hyprctl", "reload"])
            again.restart()
        }
    }
    Timer { id: again; interval: 1500; onTriggered: Hyprland.refreshMonitors() }

    Label { textStyle: "title"; color: Theme.text; text: "Display" }

    Repeater {
        model: page.screens
        Column {
            id: screen
            required property var modelData
            readonly property var own: page.chosen[modelData.name] || ({})
            readonly property bool off: !!own.off
            readonly property var others: page.screens.filter(s => s.name !== modelData.name && !(page.chosen[s.name] || {}).off)
            width: page.width
            spacing: Theme.space2

            Label { textStyle: "heading"; color: Theme.text; text: screen.modelData.title; topPadding: Theme.space2 }

            SettingRow {
                // The last screen that is on stays on
                visible: page.screens.length > 1
                width: parent.width
                title: "On"
                text: screen.modelData.name + (screen.off ? "" : " · " + screen.modelData.width + " × " + screen.modelData.height)
                Switch {
                    checked: !screen.off
                    enabled: screen.off || screen.others.length > 0
                    onToggled: page.set(screen.modelData.name, "off", !checked)
                }
            }
            SettingRow {
                visible: !screen.off
                width: parent.width
                title: "Scale"
                Segmented {
                    model: page.scales.map(s => Math.round(s * 100) + "%")
                    currentIndex: {
                        const now = screen.own.scale || screen.modelData.scale
                        let best = 0
                        for (let i = 0; i < page.scales.length; i++)
                            if (Math.abs(page.scales[i] - now) < Math.abs(page.scales[best] - now)) best = i
                        return best
                    }
                    onActivated: index => page.set(screen.modelData.name, "scale", page.scales[index])
                }
            }
            SettingRow {
                visible: !screen.off && page.sizes(screen.modelData).length > 1
                width: parent.width
                title: "Resolution"
                Segmented {
                    model: page.sizes(screen.modelData).map(s => s.replace("x", " × "))
                    currentIndex: Math.max(0, page.sizes(screen.modelData).indexOf(page.sizeOf(screen.modelData)))
                    onActivated: index => {
                        const size = page.sizes(screen.modelData)[index]
                        page.set(screen.modelData.name, "rate", page.rates(screen.modelData, size)[0] || 0)
                        page.set(screen.modelData.name, "size", size)
                    }
                }
            }
            SettingRow {
                visible: !screen.off && page.rates(screen.modelData, page.sizeOf(screen.modelData)).length > 1
                width: parent.width
                title: "Refresh rate"
                Segmented {
                    readonly property var all: page.rates(screen.modelData, page.sizeOf(screen.modelData))
                    model: all.map(r => Math.round(r) + " Hz")
                    currentIndex: {
                        const now = screen.own.rate || screen.modelData.rate
                        return Math.max(0, all.findIndex(r => Math.round(r) === Math.round(now)))
                    }
                    onActivated: index => {
                        page.set(screen.modelData.name, "size", page.sizeOf(screen.modelData))
                        page.set(screen.modelData.name, "rate", all[index])
                    }
                }
            }
            SettingRow {
                visible: !screen.off
                width: parent.width
                title: "Adaptive sync"
                text: "The screen waits for the next picture: no tearing in games and videos, where the screen can do it"
                Segmented {
                    // Hyprland: 0 off, 2 only for a window in full screen, 1 always
                    readonly property var values: [0, 2, 1]
                    model: ["Off", "Full screen", "Always"]
                    currentIndex: Math.max(0, values.indexOf(screen.own.vrr === undefined ? 0 : screen.own.vrr))
                    onActivated: index => page.set(screen.modelData.name, "vrr", values[index])
                }
            }
            SettingRow {
                visible: !screen.off && screen.others.length > 0 && !screen.own.mirror
                width: parent.width
                title: "Place"
                text: "Where it stands beside the other screens"
                Segmented {
                    model: ["Auto", "Left", "Right", "Above", "Below"]
                    currentIndex: Math.max(0, page.places.indexOf(screen.own.place || "auto"))
                    onActivated: index => page.set(screen.modelData.name, "place", page.places[index])
                }
            }
            SettingRow {
                visible: !screen.off && screen.others.length > 0
                width: parent.width
                title: "Mirror"
                text: "Shows what another screen shows"
                Segmented {
                    model: ["Off"].concat(screen.others.map(s => s.name))
                    currentIndex: Math.max(0, screen.others.findIndex(s => s.name === screen.own.mirror) + 1)
                    onActivated: index => page.set(screen.modelData.name, "mirror", index === 0 ? "" : screen.others[index - 1].name)
                }
            }
        }
    }

    Label {
        visible: page.screens.length > 0
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.textFaint
        text: "Hyprland may round a scale to one that divides the screen evenly."
    }

    Label { textStyle: "heading"; color: Theme.text; text: "Colours"; topPadding: Theme.space3 }

    // The night light (strix-nightlight): hyprsunset makes the colors warmer from 20:00 to 7:00
    property bool night: false
    Process {
        id: readNight
        command: ["strix-nightlight", "state"]
        running: true
        stdout: StdioCollector { onStreamFinished: page.night = text.trim() === "on" }
    }
    SettingRow {
        width: page.width
        title: "Night light"
        text: "Warmer colours, by itself from 20:00 to 7:00"
        Switch {
            checked: page.night
            onToggled: {
                page.night = checked
                Quickshell.execDetached(["strix-nightlight", checked ? "on" : "off"])
            }
        }
    }
}
