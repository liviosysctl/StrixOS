// Wi-Fi in a quick panel: the switch, the nearest networks (a saved one connects with a click, a
// new one asks for its password in Settings), the switch of Tailscale and the way to
// Settings › Network.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Strix

QuickPanel {
    id: root

    /// Looks for networks only while it is shown
    property bool active: false

    readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var networks: root.wifi
        ? root.wifi.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength)).slice(0, 6)
        : []
    Binding { target: root.wifi; property: "scannerEnabled"; value: root.active; when: root.wifi !== null }

    title: "Wi-Fi"
    corner: Switch {
        checked: Networking.wifiEnabled
        enabled: Networking.wifiHardwareEnabled && root.wifi !== null
        onToggled: Networking.wifiEnabled = checked
    }

    QuickHint {
        visible: root.wifi === null || !Networking.wifiEnabled || root.networks.length === 0
        text: root.wifi === null ? "No Wi-Fi on this machine"
            : !Networking.wifiHardwareEnabled ? "Switched off by a key or the airplane mode"
            : !Networking.wifiEnabled ? "Wi-Fi is off" : "Looking for networks"
    }
    Repeater {
        model: Networking.wifiEnabled ? root.networks : []
        ListRow {
            required property var modelData
            width: parent.width
            iconName: modelData.known || modelData.connected ? "wifi" : "lock"
            text: modelData.name
            selected: modelData.connected
            detail: modelData.connected ? "Connected" : modelData.stateChanging ? "Connecting"
                : modelData.known ? "Saved" : Math.round(modelData.signalStrength * (modelData.signalStrength > 1 ? 1 : 100)) + "%"
            onClicked: {
                if (modelData.connected) return
                if (modelData.known) modelData.connect()
                else root.settings("network")
            }
        }
    }
    // Tailscale (strix-tailnet): the first time it is turned on, the page to sign in opens
    property bool tailnet: false
    Process {
        id: readTailnet
        command: ["strix-tailnet", "state"]
        stdout: StdioCollector { onStreamFinished: root.tailnet = text.trim() === "on" }
    }
    Process {
        id: setTailnet
        onExited: readTailnet.running = true
    }
    onActiveChanged: if (active) readTailnet.running = true
    Component.onCompleted: readTailnet.running = true
    Item {
        width: parent.width
        height: Theme.control
        Switch {
            x: Theme.space2
            anchors.verticalCenter: parent.verticalCenter
            text: "Tailscale"
            checked: root.tailnet
            enabled: !setTailnet.running
            onToggled: {
                root.tailnet = checked
                setTailnet.command = ["strix-tailnet", checked ? "on" : "off"]
                setTailnet.running = true
            }
        }
    }
    ListRow { width: parent.width; iconName: "settings"; text: "Network settings"; onClicked: root.settings("network") }
}
