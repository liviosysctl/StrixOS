// Warns once when the battery runs low while it discharges: at 15 % a notification, at 5 % an
// urgent one that stays. Plugging in resets both, so the next discharge warns again.
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Scope {
    id: root

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: !!(root.battery && root.battery.ready && root.battery.isLaptopBattery)
    readonly property real charge: root.hasBattery ? (root.battery.percentage > 1 ? root.battery.percentage / 100 : root.battery.percentage) : 1
    readonly property bool discharging: root.hasBattery && root.battery.state === UPowerDeviceState.Discharging

    /// 0 nothing said yet, 1 low said, 2 critical said
    property int said: 0

    function check() {
        if (!root.discharging) { root.said = 0; return }
        if (root.charge <= 0.05 && root.said < 2) {
            root.said = 2
            Quickshell.execDetached(["notify-send", "--app-name=Power", "--urgency=critical", "--icon=battery-caution",
                "Battery almost empty", Math.round(root.charge * 100) + "% left. Plug in now."])
        } else if (root.charge <= 0.15 && root.said < 1) {
            root.said = 1
            Quickshell.execDetached(["notify-send", "--app-name=Power", "--icon=battery-low",
                "Battery low", Math.round(root.charge * 100) + "% left"])
        }
    }

    onChargeChanged: check()
    onDischargingChanged: check()
}
