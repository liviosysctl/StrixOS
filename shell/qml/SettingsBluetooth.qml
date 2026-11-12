// Settings › Bluetooth: on and off, the paired devices with their battery, and new ones while
// searching. BlueZ through Quickshell.Bluetooth.
import QtQuick
import Quickshell.Bluetooth
import Strix

Column {
    id: page

    property bool active: false
    spacing: Theme.space2

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: page.adapter
        ? page.adapter.devices.values.slice().sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
        : []

    // Stop searching when the page goes away
    onActiveChanged: if (!active && page.adapter && page.adapter.discovering) page.adapter.discovering = false

    Label { textStyle: "title"; color: Theme.text; text: "Bluetooth" }

    SettingRow {
        width: parent.width
        title: "Bluetooth"
        text: page.adapter === null ? "No Bluetooth on this machine" : ""
        Switch {
            enabled: page.adapter !== null
            checked: !!(page.adapter && page.adapter.enabled)
            onToggled: page.adapter.enabled = checked
        }
    }

    SettingRow {
        visible: !!(page.adapter && page.adapter.enabled)
        width: parent.width
        title: "Find new devices"
        text: page.adapter && page.adapter.discovering ? "Searching; put the device into pairing mode" : ""
        Switch {
            checked: !!(page.adapter && page.adapter.discovering)
            onToggled: page.adapter.discovering = checked
        }
    }

    Repeater {
        model: page.adapter && page.adapter.enabled ? page.devices : []
        SettingRow {
            required property var modelData
            visible: modelData.paired || page.adapter.discovering
            width: page.width
            title: modelData.name || modelData.address
            text: (modelData.connected ? "Connected" : modelData.paired ? "Paired" : "New")
                + (modelData.batteryAvailable ? " · battery " + Math.round(modelData.battery * (modelData.battery > 1 ? 1 : 100)) + "%" : "")
            Row {
                spacing: Theme.space2
                Button {
                    small: true
                    visible: !modelData.paired
                    variant: "primary"
                    loading: modelData.pairing
                    text: "Pair"
                    onClicked: { modelData.trusted = true; modelData.pair() }
                }
                Button {
                    small: true
                    visible: modelData.paired
                    text: modelData.connected ? "Disconnect" : "Connect"
                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                }
                Button {
                    small: true
                    visible: modelData.paired
                    variant: "quiet"
                    text: "Forget"
                    onClicked: modelData.forget()
                }
            }
        }
    }
}
