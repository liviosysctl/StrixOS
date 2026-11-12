// Settings › Power: the battery, the power profile (power-profiles-daemon through UPower), what
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
            Button { small: true; text: "Suspend"; onClicked: Quickshell.execDetached(["systemctl", "suspend"]) }
            Button { small: true; text: "Hibernate"; onClicked: Quickshell.execDetached(["systemctl", "hibernate"]) }
        }
    }
}
