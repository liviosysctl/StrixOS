// Bluetooth in a quick panel: the switch, the paired devices (a click connects or disconnects,
// with the battery of those that tell it) and the way to Settings › Bluetooth, where new ones pair.
import QtQuick
import Quickshell.Bluetooth
import Strix

QuickPanel {
    id: root

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: root.adapter
        ? root.adapter.devices.values.filter(d => d.paired).sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name)).slice(0, 6)
        : []

    title: "Bluetooth"
    corner: Switch {
        enabled: root.adapter !== null
        checked: !!(root.adapter && root.adapter.enabled)
        onToggled: root.adapter.enabled = checked
    }

    QuickHint {
        visible: !(root.adapter && root.adapter.enabled) || root.devices.length === 0
        text: root.adapter === null ? "No Bluetooth on this machine"
            : !root.adapter.enabled ? "Bluetooth is off" : "No paired devices"
    }
    Repeater {
        model: root.adapter && root.adapter.enabled ? root.devices : []
        ListRow {
            required property var modelData
            width: parent.width
            iconName: "bluetooth"
            text: modelData.name || modelData.address
            selected: modelData.connected
            detail: !modelData.connected ? "Paired"
                : modelData.batteryAvailable ? Math.round(modelData.battery * (modelData.battery > 1 ? 1 : 100)) + "%" : "Connected"
            onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
        }
    }
    ListRow { width: parent.width; iconName: "settings"; text: "Bluetooth settings"; onClicked: root.settings("bluetooth") }
}
