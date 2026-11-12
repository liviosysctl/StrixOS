// Settings › Display: every screen with its size and its scale. A new scale is written to
// ~/.config/strix/monitors.lua (one hl.monitor per screen, read by the Hyprland configuration of
// Strix) and Hyprland reloads; monitors.json beside it keeps the choices for this page.
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
    /// Screen name to scale, as stored
    property var chosen: ({})

    FileView {
        id: stored
        path: page.dir + "/monitors.json"
        printErrors: false
        onLoaded: { try { page.chosen = JSON.parse(text()) } catch (e) { page.chosen = {} } }
    }
    FileView { id: lua; path: page.dir + "/monitors.lua"; printErrors: false }

    function setScale(name, scale) {
        const next = Object.assign({}, page.chosen)
        next[name] = scale
        page.chosen = next
        const lines = ["-- Written by Settings › Display; change the scale there."]
        for (const output in next)
            lines.push('hl.monitor({ output = ' + JSON.stringify(output) + ', mode = "preferred", position = "auto", scale = ' + next[output] + ' })')
        Quickshell.execDetached(["mkdir", "-p", page.dir])
        stored.setText(JSON.stringify(next, null, 2) + "\n")
        lua.setText(lines.join("\n") + "\n")
        reload.restart()
    }

    // After the files are written
    Timer { id: reload; interval: 300; onTriggered: Quickshell.execDetached(["hyprctl", "reload"]) }

    Label { textStyle: "title"; color: Theme.text; text: "Display" }

    Repeater {
        model: Hyprland.monitors.values
        SettingRow {
            required property var modelData
            width: page.width
            title: modelData.description || modelData.name
            text: modelData.name + " · " + modelData.width + " × " + modelData.height
            Segmented {
                model: page.scales.map(s => Math.round(s * 100) + "%")
                currentIndex: {
                    const now = page.chosen[modelData.name] || modelData.scale
                    let best = 0
                    for (let i = 0; i < page.scales.length; i++)
                        if (Math.abs(page.scales[i] - now) < Math.abs(page.scales[best] - now)) best = i
                    return best
                }
                onActivated: index => page.setScale(modelData.name, page.scales[index])
            }
        }
    }

    Label {
        width: parent.width
        wrapMode: Text.WordWrap
        textStyle: "caption"
        color: Theme.textFaint
        text: "Hyprland may round a scale to one that divides the screen evenly."
    }
}
