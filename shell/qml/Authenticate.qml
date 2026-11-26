// The password an app needs for more rights (polkit): changing the machine's theme, mounting a
// drive of another user, Settings writing for the machine. Quickshell is the polkit agent of the
// session; this is its window, in the middle over a scrim, with the keyboard to itself until it is
// answered. Enter allows, Esc cancels. A wrong password shakes the field and asks again; several
// requests are answered one after the other.
import QtQuick
import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland
import Strix

Scope {
    id: root

    readonly property var flow: agent.flow
    property string error: ""

    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: {
            root.error = ""
            field.text = ""
        }
    }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() {
            root.error = "Wrong password"
            field.text = ""
            field.shake()
        }
    }

    function allow() {
        if (!root.flow || !root.flow.isResponseRequired) return
        root.error = ""
        root.flow.submit(field.text)
        field.text = ""
    }

    function cancel() {
        if (root.flow) root.flow.cancelAuthenticationRequest()
    }

    Presence { id: presence; open: agent.isActive }

    PanelWindow {
        visible: presence.present
        WlrLayershell.namespace: "strix-authenticate"
        WlrLayershell.layer: WlrLayer.Overlay
        // A password goes nowhere else while it is asked for
        WlrLayershell.keyboardFocus: agent.isActive ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Theme.alpha(Theme.scrim, Theme.scrim.a * presence.shown)

        Surface {
            elevation: "panel"
            opacity: presence.shown
            scale: 0.98 + 0.02 * presence.shown
            width: 380
            height: body.implicitHeight + 2 * Theme.space5
            anchors.centerIn: parent

            Column {
                id: body
                x: Theme.space5
                y: Theme.space5
                width: parent.width - 2 * Theme.space5
                spacing: Theme.space2

                Row {
                    spacing: Theme.space2
                    Icon { name: "lock"; size: 20; color: Theme.accentText; anchors.verticalCenter: parent.verticalCenter }
                    Label { textStyle: "title"; color: Theme.accentText; text: "Password needed" }
                }

                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: Theme.textMuted
                    lineHeightMode: Text.ProportionalHeight
                    lineHeight: 1.4
                    text: root.flow ? root.flow.message : ""
                }

                Label {
                    width: parent.width
                    visible: text !== ""
                    textStyle: "caption"
                    color: Theme.textFaint
                    text: root.flow && root.flow.selectedIdentity ? "As " + root.flow.selectedIdentity.displayName : ""
                }

                Item { width: 1; height: Theme.space2 }

                TextField {
                    id: field
                    width: parent.width
                    placeholderText: root.flow && root.flow.inputPrompt !== "" ? root.flow.inputPrompt.replace(/:\s*$/, "") : "Password"
                    echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    enabled: root.flow ? root.flow.isResponseRequired : false
                    error: root.error !== "" ? root.error
                        : root.flow && root.flow.supplementaryIsError ? root.flow.supplementaryMessage : ""
                    help: root.flow && !root.flow.supplementaryIsError ? root.flow.supplementaryMessage : ""
                    onAccepted: root.allow()
                    // Esc in the field comes up to here: the field does not take it
                    Keys.onEscapePressed: root.cancel()
                }

                // The window gets the keyboard only once it is shown
                Timer {
                    interval: 100
                    repeat: true
                    running: agent.isActive && field.enabled && !field.field.activeFocus
                    onTriggered: field.field.forceActiveFocus()
                }

                Row {
                    anchors.right: parent.right
                    spacing: Theme.space2
                    Button { text: "Cancel"; variant: "quiet"; onClicked: root.cancel() }
                    Button {
                        text: "Allow"
                        variant: "primary"
                        enabled: root.flow ? root.flow.isResponseRequired : false
                        onClicked: root.allow()
                    }
                }
            }
        }
    }
}
