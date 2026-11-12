// Settings › Network: Wi-Fi on and off, the networks around with their signal, connect (with the
// password when the network asks for one and is not known yet), disconnect and forget. A cable
// shows as Wired. NetworkManager through Quickshell.Networking; scanning only while visible.
import QtQuick
import Quickshell.Networking
import Strix

Column {
    id: page

    /// The page is on screen: scan for networks
    property bool active: false
    /// The network that asks for its password
    property var asking: null
    property string error: ""

    spacing: Theme.space2

    readonly property var devices: Networking.devices.values
    readonly property var wifi: page.devices.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wired: page.devices.find(d => d.type === DeviceType.Wired) || null
    readonly property var networks: page.wifi
        ? page.wifi.networks.values.slice().sort((a, b) => (b.connected - a.connected) || (b.signalStrength - a.signalStrength))
        : []

    Binding { target: page.wifi; property: "scannerEnabled"; value: page.active; when: page.wifi !== null }

    function join(net) {
        page.error = ""
        if (net.known) { net.connect(); return }
        page.asking = net
    }

    Label { textStyle: "title"; color: Theme.text; text: "Network" }

    SettingRow {
        width: parent.width
        title: "Wi-Fi"
        text: !Networking.wifiHardwareEnabled ? "Switched off by a key or the airplane mode"
            : page.wifi === null ? "No Wi-Fi on this machine" : ""
        Switch {
            checked: Networking.wifiEnabled
            enabled: Networking.wifiHardwareEnabled && page.wifi !== null
            onToggled: Networking.wifiEnabled = checked
        }
    }

    SettingRow {
        visible: page.wired !== null
        width: parent.width
        title: "Wired"
        text: page.wired && page.wired.connected ? "Connected" : "No cable"
    }

    Label {
        visible: page.error !== ""
        textStyle: "caption"
        color: Theme.error
        text: page.error
    }

    Repeater {
        model: Networking.wifiEnabled ? page.networks : []
        Item {
            required property var modelData
            width: page.width
            height: column.implicitHeight + Theme.space2

            Connections {
                target: modelData
                function onConnectionFailed(reason) {
                    page.error = modelData.name + ": " + ConnectionFailReason.toString(reason)
                    if (reason === ConnectionFailReason.NoSecrets) page.asking = modelData
                }
            }

            Column {
                id: column
                width: parent.width
                spacing: Theme.space1

                Row {
                    width: parent.width
                    spacing: Theme.space2
                    Icon { name: "wifi"; color: modelData.connected ? Theme.accentText : Theme.textMuted; anchors.verticalCenter: parent.verticalCenter }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 260
                        elide: Text.ElideRight
                        textStyle: "label"
                        color: Theme.text
                        text: modelData.name
                    }
                    Meter {
                        anchors.verticalCenter: parent.verticalCenter
                        label: ""
                        value: modelData.signalStrength > 1 ? modelData.signalStrength / 100 : modelData.signalStrength
                        valueText: ""
                    }
                    Button {
                        small: true
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.connected
                        text: "Disconnect"
                        onClicked: modelData.disconnect()
                    }
                    Button {
                        small: true
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !modelData.connected
                        variant: "primary"
                        loading: modelData.stateChanging
                        text: "Connect"
                        onClicked: page.join(modelData)
                    }
                    Button {
                        small: true
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.known
                        variant: "quiet"
                        text: "Forget"
                        onClicked: modelData.forget()
                    }
                }

                Row {
                    visible: page.asking === modelData
                    spacing: Theme.space2
                    TextField {
                        id: secret
                        width: 280
                        echoMode: TextInput.Password
                        placeholderText: "Password of " + modelData.name
                        onAccepted: go.clicked()
                    }
                    Button {
                        id: go
                        text: "Join"
                        variant: "primary"
                        enabled: secret.text.length >= 8
                        onClicked: {
                            modelData.connectWithPsk(secret.text)
                            secret.text = ""
                            page.asking = null
                        }
                    }
                }
            }
        }
    }
}
