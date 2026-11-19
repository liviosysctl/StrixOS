// Battery and brightness in a quick panel: the charge with the time left, the brightness of the
// screen (when it has a backlight), the power profile, the night light, staying awake and the way to
// Settings › Power.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Strix

QuickPanel {
    id: root

    /// Reads the brightness again while it is shown: the keys change it behind its back
    property bool active: false

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(root.battery && root.battery.ready && root.battery.isLaptopBattery)
    readonly property real charge: root.hasBattery ? (root.battery.percentage > 1 ? root.battery.percentage / 100 : root.battery.percentage) : 0
    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    readonly property var names: ["Saver", "Balanced", "Performance"]

    function duration(seconds) {
        if (!seconds) return ""
        const h = Math.floor(seconds / 3600)
        const m = Math.round((seconds % 3600) / 60)
        return h > 0 ? h + " h " + m + " min" : m + " min"
    }

    // brightnessctl -m prints device,class,value,percent,max; nothing on a machine without backlight
    property bool hasBacklight: false
    property real brightness: 0
    Process {
        id: readLight
        command: ["brightnessctl", "-m", "-c", "backlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(",")
                root.hasBacklight = f.length >= 5 && Number(f[4]) > 0
                if (root.hasBacklight) root.brightness = Number(f[2]) / Number(f[4])
            }
        }
    }
    // The night light comes on by itself in the evening; here it is switched by hand
    property bool night: false
    Process {
        id: readNight
        command: ["strix-nightlight", "state"]
        stdout: StdioCollector { onStreamFinished: root.night = text.trim() === "on" }
    }
    // Stay awake (strix-idle awake): nothing dims, locks or sleeps by itself, until the logout
    property bool awake: false
    Process {
        id: readAwake
        command: ["strix-idle", "awake", "state"]
        stdout: StdioCollector { onStreamFinished: root.awake = text.trim() === "on" }
    }
    onActiveChanged: if (active) { readLight.running = true; readNight.running = true; readAwake.running = true }
    Component.onCompleted: { readLight.running = true; readNight.running = true; readAwake.running = true }

    title: "Power"
    corner: Label {
        visible: root.hasBattery
        textStyle: "caption"
        color: root.charge < 0.15 && root.battery.state === UPowerDeviceState.Discharging ? Theme.error : Theme.textMuted
        text: Math.round(root.charge * 100) + "%"
    }

    QuickHint {
        visible: root.hasBattery
        text: {
            if (!root.hasBattery) return ""
            const s = root.battery.state
            if (s === UPowerDeviceState.Charging) return "Charging, full in " + root.duration(root.battery.timeToFull)
            if (s === UPowerDeviceState.FullyCharged) return "Full, on power"
            if (s === UPowerDeviceState.PendingCharge) return "On power, not charging"
            return root.duration(root.battery.timeToEmpty) + " left"
        }
    }

    Item {
        visible: root.hasBacklight
        width: parent.width
        height: Theme.controlMd
        Slider {
            x: Theme.space2
            width: parent.width - 2 * Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            iconName: "sun"
            from: 0.05
            to: 1
            value: root.brightness
            onMoved: {
                root.brightness = value
                Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "-e4", "set", Math.round(value * 100) + "%"])
            }
        }
    }

    Item {
        width: parent.width
        height: Theme.controlMd
        Segmented {
            x: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            model: root.profiles.map(p => root.names[p])
            currentIndex: Math.max(0, root.profiles.indexOf(PowerProfiles.profile))
            onActivated: index => PowerProfiles.profile = root.profiles[index]
        }
    }
    Item {
        width: parent.width
        height: Theme.controlMd
        Switch {
            x: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            text: "Night light"
            checked: root.night
            onToggled: {
                root.night = checked
                Quickshell.execDetached(["strix-nightlight", checked ? "on" : "off"])
            }
        }
    }
    Item {
        width: parent.width
        height: Theme.controlMd
        Switch {
            x: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            text: "Stay awake"
            checked: root.awake
            onToggled: {
                root.awake = checked
                Quickshell.execDetached(["strix-idle", "awake", checked ? "on" : "off"])
            }
        }
    }
    ListRow { width: parent.width; iconName: "settings"; text: "Power settings"; onClicked: root.settings("power") }
}
