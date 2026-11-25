// Settings › Power: the battery, the power profile (power-profiles-daemon through UPower), when
// the screen dims, locks and goes off and the machine sleeps (strix-idle, on power and on battery), what
// closing the lid does (strix.desktop.lid in machine.nix), suspend and hibernate now.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Strix

Column {
    id: page

    spacing: Theme.space2

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(page.battery && page.battery.ready && page.battery.isLaptopBattery)
    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    readonly property var names: ["Power saver", "Balanced", "Performance"]
    property string lid: "suspend"

    /// Reads the times while the page is shown
    property bool active: false
    /// What happens when nobody is at the machine (strix-idle): seconds for ac and battery, 0 never
    property var idle: ({ ac: {}, battery: {} })
    /// The set that is shown: "ac" or "battery"
    property string source: "ac"
    readonly property var steps: ({
        dim: [0, 60, 120, 240, 600],
        lock: [0, 120, 300, 600, 1800],
        off: [0, 300, 600, 900, 1800],
        sleep: [0, 900, 1800, 3600, 7200]
    })
    function label(seconds) {
        return seconds === 0 ? "Never" : seconds < 3600 ? seconds / 60 + " min" : seconds / 3600 + " h"
    }
    function setIdle(action, seconds) {
        const next = JSON.parse(JSON.stringify(page.idle))
        next[page.source][action] = seconds
        page.idle = next
        Quickshell.execDetached(["strix-idle", "set", page.source, action, String(seconds)])
    }
    Process {
        id: readIdle
        command: ["strix-idle", "show"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.idle = JSON.parse(text) } catch (e) {} }
        }
    }
    onActiveChanged: if (active) readIdle.running = true

    FileView {
        path: "/etc/xdg/strix/lid"
        printErrors: false
        onLoaded: page.lid = text().trim()
    }

    function duration(seconds) {
        if (!seconds) return ""
        const h = Math.floor(seconds / 3600)
        const m = Math.round((seconds % 3600) / 60)
        return h > 0 ? h + " h " + m + " min" : m + " min"
    }

    Label { textStyle: "title"; color: Theme.text; text: "Power" }

    SettingRow {
        visible: page.hasBattery
        width: parent.width
        title: "Battery"
        text: {
            if (!page.hasBattery) return ""
            const pct = Math.round((page.battery.percentage > 1 ? page.battery.percentage / 100 : page.battery.percentage) * 100) + "%"
            const s = page.battery.state
            if (s === UPowerDeviceState.Charging) return pct + ", charging, full in " + page.duration(page.battery.timeToFull)
            if (s === UPowerDeviceState.FullyCharged) return pct + ", full"
            return pct + ", " + page.duration(page.battery.timeToEmpty) + " left"
        }
    }

    SettingRow {
        width: parent.width
        title: "Power profile"
        text: PowerProfiles.degradationReason !== PerformanceDegradationReason.None
            ? "Performance is held back: " + PerformanceDegradationReason.toString(PowerProfiles.degradationReason) : ""
        Segmented {
            model: page.profiles.map(p => page.names[p])
            currentIndex: Math.max(0, page.profiles.indexOf(PowerProfiles.profile))
            onActivated: index => PowerProfiles.profile = page.profiles[index]
        }
    }

    Label { textStyle: "heading"; color: Theme.text; text: "When nobody is there"; topPadding: Theme.space3 }
    SettingRow {
        visible: page.hasBattery
        width: parent.width
        title: "These times are for"
        Segmented {
            model: ["On power", "On battery"]
            currentIndex: page.source === "battery" ? 1 : 0
            onActivated: index => page.source = index === 1 ? "battery" : "ac"
        }
    }
    Repeater {
        model: [
            { action: "dim", title: "Dim the screen" },
            { action: "lock", title: "Lock" },
            { action: "off", title: "Screen off" },
            { action: "sleep", title: "Sleep" }
        ]
        SettingRow {
            required property var modelData
            width: page.width
            title: modelData.title
            Segmented {
                model: page.steps[modelData.action].map(s => page.label(s))
                currentIndex: {
                    const now = (page.idle[page.source] || {})[modelData.action] || 0
                    const steps = page.steps[modelData.action]
                    let best = 0
                    for (let i = 0; i < steps.length; i++)
                        if (Math.abs(steps[i] - now) < Math.abs(steps[best] - now)) best = i
                    return best
                }
                onActivated: index => page.setIdle(modelData.action, page.steps[modelData.action][index])
            }
        }
    }

    SettingRow {
        width: parent.width
        title: "Closing the lid"
        text: ({ suspend: "Suspends", hibernate: "Hibernates", lock: "Locks the screen", ignore: "Does nothing" })[page.lid]
            + ". To change it: strix.desktop.lid in /etc/nixos/machine.nix"
    }

    SettingRow {
        width: parent.width
        title: "Now"
        Row {
            spacing: Theme.space2
            Button { text: "Suspend"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
            Button { text: "Hibernate"; onClicked: Quickshell.execDetached(["systemctl", "hibernate"]) }
        }
    }
}
